#!/usr/bin/env python3
"""Validate fixture-scoped capability declarations and generate the format-specific API data."""
import argparse
import copy
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OPERATIONS = {"inspect", "read", "create", "edit", "preserve", "convert", "render", "play"}
STATUSES = {"supported", "partial", "preserveOnly", "unsupported", "notApplicable", "unverified"}
PROFILES_BY_FORMAT = {"pptx": {"ooxmlTransitional", "ooxmlStrict", "ooxmlAgile", "ooxmlStandard"}, "pptm": {"ooxmlTransitional", "ooxmlStrict"}, "odp": {"odf12", "odf13", "odf14"}, "keynote": {"keynoteIWA"}, "ppt": {"pptBinary"}, "keynoteLegacy": {"keynoteXML"}, "sxi": {"impressXML"}}
FORMATS = set(PROFILES_BY_FORMAT)


def regression_tests(source):
    # helper関数を証拠として登録しない。現行のSwift Testing宣言を扱う。
    return set(re.findall(r"@Test(?:\((?:[^()]|\([^()]*\))*\))?\s*(?:@\w+\s*)*func\s+(\w+)\s*\(", source))


def validate(data, features, tests, fixtures):
    if data["schemaVersion"] != 1 or not data["capabilities"]:
        raise ValueError("空の台帳または未対応schema")
    evidence = data["evidence"]
    if not evidence or len({e["id"] for e in evidence}) != len(evidence):
        raise ValueError("空または重複した証拠ID")
    by_id = {e["id"]: e for e in evidence}
    for item in evidence + data["capabilities"]:
        if item["format"] not in FORMATS or item["profile"] not in PROFILES_BY_FORMAT.get(item["format"], set()):
            raise ValueError("不明な形式・プロファイル")
        if item["operation"] not in OPERATIONS:
            raise ValueError("不明な操作")
    for item in evidence:
        if item["fixture"] not in fixtures or fixtures[item["fixture"]] != item["fixtureSHA256"]:
            raise ValueError("fixtureの欠落またはSHA-256不一致: " + item["id"])
        if item["test"] not in tests or not item["scope"].strip():
            raise ValueError("証拠のテストまたは検証範囲がありません: " + item["id"])
    seen = set()
    used = set()
    for item in data["capabilities"]:
        if item.get("provider") not in (None,"SlideDecrypt"):
            raise ValueError("不明な提供製品")
        key = tuple(item[k] for k in ["format", "profile", "feature", "operation"]) + (item.get("provider"),)
        if key in seen:
            raise ValueError("能力宣言の重複")
        seen.add(key)
        if item["feature"] not in features or item["status"] not in STATUSES or not item["notes"].strip():
            raise ValueError("不明な機能・状態または空の境界説明")
        if item["status"] in {"supported", "partial", "preserveOnly"} and not item["evidence"]:
            raise ValueError("対応能力に証拠がありません")
        if len(set(item["evidence"])) != len(item["evidence"]):
            raise ValueError("同じ証拠の重複")
        for ref in item["evidence"]:
            if ref not in by_id:
                raise ValueError("証拠IDがありません")
            source = by_id[ref]
            if any(source[k] != item[k] for k in ["format", "profile", "operation"]):
                raise ValueError("別形式・別プロファイル・別操作の証拠")
            used.add(ref)
    if used != set(by_id):
        raise ValueError("参照されない証拠")


def render(data, formats=("pptm", "pptx"), module="PPTX", provider=None):
    data = copy.deepcopy(data)
    data["capabilities"] = [item for item in data["capabilities"] if item["format"] in formats and item.get("provider") == provider]
    used = {ref for item in data["capabilities"] for ref in item["evidence"]}
    data["evidence"] = [item for item in data["evidence"] if item["id"] in used]
    def literal(value):
        return json.dumps(value, ensure_ascii=False)

    lines = [
        "// docs/capabilities.jsonから生成。直接編集せずscripts/build-capabilities.pyを使う。",
        "import SlideCore", "", "enum " + module + "FeatureCapabilities {",
        "    private static let evidence: [CapabilityEvidence] = [",
    ]
    indices = {}
    for index, item in enumerate(data["evidence"]):
        indices[item["id"]] = index
        fields = ", ".join(k + ": " + literal(item[k]) for k in ["id", "fixture", "fixtureSHA256", "test", "scope"])
        lines.append("        .init(" + fields + "),")
    lines += ["    ]", "", "    static func features(for format: PresentationFormat) -> [FeatureCapability] {", "        switch format {"]
    for format in sorted(formats):
        lines += ["        case ." + format + ":", "            return ["]
        for item in data["capabilities"]:
            if item["format"] != format:
                continue
            refs = ", ".join("evidence[" + str(indices[e]) + "]" for e in item["evidence"])
            lines.append("                .init(feature: " + literal(item["feature"]) + ", profile: ." + item["profile"] +
                         ", operation: ." + item["operation"] + ", status: ." + item["status"] +
                         ", evidence: [" + refs + "], notes: " + literal(item["notes"]) + "),")
        lines += ["            ]"]
    lines += ["        default: return []", "        }", "    }", "}", ""]
    return "\n".join(lines)


def self_test():
    declarations = "func helper() {}\n@Test func check() {}\n@Test(arguments: [1, 2]) func scoped(_ n: Int) {}\n@Test @MainActor func ui() {}"
    if regression_tests(declarations) != {"check", "scoped", "ui"}:
        raise RuntimeError("回帰テストとhelperの区別に失敗しました")
    proof = dict(id="E01", format="pptx", profile="ooxmlTransitional", operation="read", fixture="sample.pptx",
                 fixtureSHA256="a" * 64, test="readSample", scope="架空資料の本文")
    row = dict(format="pptx", profile="ooxmlTransitional", operation="read", feature="TXT-001", status="partial",
               evidence=["E01"], notes="本文のみ")
    data = dict(schemaVersion=1, evidence=[proof], capabilities=[row])
    context = ({"TXT-001"}, {"readSample"}, {"sample.pptx": "a" * 64})
    validate(data, *context)
    mutations = [
        lambda d: d.update(capabilities=[]),
        lambda d: d["capabilities"].append(copy.deepcopy(row)),
        lambda d: d["capabilities"][0].update(feature="unknown"),
        lambda d: d["capabilities"][0].update(profile="future"),
        lambda d: d["capabilities"][0].update(status="unknown"),
        lambda d: d["capabilities"][0].update(operation="unknown"),
        lambda d: d["capabilities"][0].update(evidence=[]),
        lambda d: d["evidence"][0].update(test="missing"),
        lambda d: d["evidence"][0].update(fixtureSHA256="b" * 64),
        lambda d: d["evidence"][0].update(profile="ooxmlStrict"),
        lambda d: d["evidence"][0].update(operation="preserve"),
        lambda d: d["evidence"][0].update(format="pptm"),
        lambda d: d["capabilities"][0].update(evidence=["missing"]),
    ]
    for mutate in mutations:
        broken = copy.deepcopy(data)
        mutate(broken)
        try:
            validate(broken, *context)
        except ValueError:
            continue
        raise RuntimeError("能力台帳の負例を見落としました")
    print(f"能力台帳の負例: {len(mutations)}件を拒否")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    self_test()
    if args.self_test:
        return
    data = json.loads((ROOT / "docs/capabilities.json").read_text())
    catalog = json.loads((ROOT / "docs/feature-catalog.json").read_text())
    features = {f["id"] for c in catalog["categories"] for f in c["features"]}
    tests = set()
    for path in (ROOT / "Tests").rglob("*.swift"):
        tests.update(regression_tests(path.read_text()))
    fixtures = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                for p in (ROOT / "Tests/SwiftSlidesTests/Fixtures").iterdir() if p.is_file()}
    validate(data, features, tests, fixtures)
    for module, formats in [("PPTX", ("pptm", "pptx")), ("ODP", ("odp",)), ("Keynote", ("keynote",)), ("Legacy", ("ppt", "keynoteLegacy", "sxi")), ("Decrypt", ("pptx", "odp", "keynote"))]:
        output = render(data, formats, module, "SlideDecrypt" if module == "Decrypt" else None)
        target = ROOT / ("Sources/Slide" + module + "/FeatureCapabilities.swift")
        if args.check:
            if not target.exists() or target.read_text() != output:
                raise SystemExit("能力宣言の生成結果が一致しません: " + module)
        else:
            target.write_text(output)
    print(f"詳細能力: {len(data['capabilities'])}宣言・{len(data['evidence'])}証拠の整合")


if __name__ == "__main__":
    main()
