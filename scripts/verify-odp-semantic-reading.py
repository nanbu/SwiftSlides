#!/usr/bin/env python3
"""公開CLIのODP数式/高度図形を独立XML parserと任意のODF RNGで照合する。"""
import argparse
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DRAW = "urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"
SVG = "urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0"
MATH = "http://www.w3.org/1998/Math/MathML"
XML = "http://www.w3.org/XML/1998/namespace"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", type=Path, default=ROOT / ".build/release/swiftslides")
    parser.add_argument("--schema-rng", type=Path)
    args = parser.parse_args()
    path = ROOT / "Tests/SwiftSlidesTests/Fixtures/semantic-reading.odp"
    model = json.loads(subprocess.check_output([str(args.cli.resolve()), "read-json", str(path)], text=True))
    with zipfile.ZipFile(path) as package:
        content = ET.fromstring(package.read("content.xml"))
        element = next(n for n in content.iter(f"{{{DRAW}}}custom-shape") if n.get(f"{{{XML}}}id") == "enhanced")
        native = element.find(f"{{{DRAW}}}enhanced-geometry")
        shape = next(n for n in model["slides"][0]["elements"] if n["id"] == "enhanced")
        geometry = shape["enhancedGeometry"]
        box = list(map(float, native.get(f"{{{SVG}}}viewBox").split()))
        assert [geometry["viewBox"][k] for k in ["x", "y", "width", "height"]] == box
        assert geometry["modifiers"] == list(map(float, native.get(f"{{{DRAW}}}modifiers").split()))
        assert geometry["shapeType"] == native.get(f"{{{DRAW}}}type")
        assert geometry["mirrorHorizontal"] is False and geometry["mirrorVertical"] is True
        assert [c["kind"] for c in geometry["path"]] == list("MLCQABTUVWXYZNFS")
        assert geometry["path"][0]["arguments"] == [{"number": {"_0": n}} for n in [0, 0, 50, 50]]
        assert geometry["path"][1]["arguments"] == [{"modifier": {"_0": 0}}, {"formula": {"_0": "edge"}}]
        assert geometry["equations"] == [{"name": n.get(f"{{{DRAW}}}name"), "formula": n.get(f"{{{DRAW}}}formula")} for n in native.findall(f"{{{DRAW}}}equation")]
        assert geometry["source"]["attributes"][DRAW + "|enhanced-path"] == native.get(f"{{{DRAW}}}enhanced-path")
        assert geometry["handles"][0]["attributes"][DRAW + "|handle-position"] == native.find(f"{{{DRAW}}}handle").get(f"{{{DRAW}}}handle-position")
        original = ET.fromstring(package.read("Formula/content.xml"))
        equation = next(n for n in model["slides"][0]["elements"] if n["id"] == "package-math")["equation"]
        row = original.find(f"{{{MATH}}}semantics/{{{MATH}}}mrow")
        tokens = {f"{{{MATH}}}{n}" for n in ["mi", "mn", "mo", "ms", "mtext"]}
        expected = "".join(n.text or "" for n in row.iter() if n.tag in tokens)
        def lexical(node):
            if node["kind"] == "annotation":
                return ""
            return node.get("text", "") + "".join(map(lexical, node["children"]))
        assert equation["dialect"] == "mathML" and equation["part"] == "Formula/content.xml"
        assert lexical(equation["root"]) == expected == "a2+x3y12∑0n12z20"
        fraction = equation["root"]["children"][0]["children"][0]["children"][0]
        assert [c["kind"] for c in fraction["children"]] == ["identifier", "number"]
        assert [lexical(c) for c in fraction["children"]] == ["".join(n.itertext()) for n in row.find(f"{{{MATH}}}mfrac")]
        annotation = original.find(f"{{{MATH}}}semantics/{{{MATH}}}annotation")
        assert annotation.text not in expected
        inline = next(n for n in model["slides"][0]["elements"] if n["id"] == "text-math")["text"]["paragraphs"][0]["runs"]
        assert [n["text"] for n in inline] == ["Before", "b4", "After"]
        assert inline[1]["equation"]["dialect"] == "mathML"
        if args.schema_rng:
            from lxml import etree
            schema = etree.RelaxNG(etree.parse(str(args.schema_rng)))
            checked = 0
            for part in ["content.xml", "styles.xml"]:
                tree = etree.fromstring(package.read(part))
                extensions = tree.xpath('//*[namespace-uri()="urn:fictional:future" and not(ancestor::*[namespace-uri()="http://www.w3.org/1998/Math/MathML"])]')
                assert len(extensions) == (1 if part == "content.xml" else 0)
                for extension in extensions:
                    extension.getparent().remove(extension)
                # RNGはmath内部を任意XMLとして許す。数式の意味検査は上の独立照合とSwiftで行う。
                schema.assertValid(tree)
                checked += 1
            assert checked == 2
            print("ODF 1.3 RNG: 2 XML passed; one intentional foreign geometry node excluded")
    print("ODP independent XML check: 16 path commands, formula tokens/operands, inline order passed")


if __name__ == "__main__":
    main()
