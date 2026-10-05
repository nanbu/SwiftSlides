#!/usr/bin/env python3
"""Render the planning catalog; it does not change the implemented support ledger."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STATUSES = {
    "basic": "基本範囲あり",
    "partial": "部分対応",
    "preserved": "原本保持中心",
    "none": "未実装",
    "refused": "拒否",
    "notApplicable": "対象外",
}


def render(data):
    sources = {s["id"]: s for s in data["sources"]}
    phases = set(data["phases"])
    seen = set()
    categories = data["categories"]
    if len(sources) != len(data["sources"]):
        raise ValueError("資料IDが重複しています")
    for category in categories:
        for source in category["sources"]:
            if source not in sources:
                raise ValueError("不明な資料ID: " + source)
        for feature in category["features"]:
            if feature["id"] in seen:
                raise ValueError("機能IDが重複しています: " + feature["id"])
            seen.add(feature["id"])
            if feature["phase"] not in phases:
                raise ValueError("不明な工程: " + feature["phase"])
            if feature["baseline"] not in STATUSES:
                raise ValueError("不明な状態: " + feature["baseline"])
            for key in ["name", "model", "acceptance"]:
                if not feature[key].strip():
                    raise ValueError("空の項目: " + feature["id"] + ":" + key)
    if not seen:
        raise ValueError("機能がありません")

    def cell(value):
        return str(value).replace("|", "\\|").replace("\n", "<br>")

    def table(headers, rows):
        return ["| " + " | ".join(headers) + " |", "|" + "---|" * len(headers)] + [
            "| " + " | ".join(cell(c) for c in row) + " |" for row in rows
        ]

    lines = [
        "# 読み書き再現の機能台帳", "",
        "将来設計。`feature-catalog.json`から生成。直接編集せず、`python3 scripts/build-feature-catalog.py`を実行する。整合検査は`--check`。", "",
        f"{len(categories)}分類・{len(seen)}機能。基準日: {data['date']}。現行SwiftSlides参照: `{data['baselineRevision']}`。", "",
        "[形式調査](format-research.md) · [API設計](api-design.md) · [実装計画](implementation-roadmap.md) · [実装済み対応表](support.json)", "",
        "## 台帳の読み方", "",
        "これは完全再現のための作業分類であり、全スキーマ属性の列挙完了や互換性保証ではない。分類ごとの形式欄は調査・実装で扱う表現と探索先であり、全機能が3形式に存在するという主張ではない。形式固有の項目は共通モデルへ丸めず、固有モデルまたは原本として保持する。Keynoteの内部フィールドは実サンプルと型registryで確定する。", "",
        "各行は原則として次の5方向で分解して実装・検証する。実装時には形式・プロファイルごとの状態とfixtureを追加する。", "",
    ]
    lines += table(["方向", "共通の受入条件"], [
        ["読取", "値・省略・参照・順序を区別。未知情報は位置つき診断と原本保持。破損を空データに変えない"],
        ["新規生成", "対象形式に存在する機能だけを有効な構造で出力。存在しない機能はnotApplicable/unsupported"],
        ["編集保存", "変更対象と必要な依存だけを更新。参照・未知情報・署名への影響を検査"],
        ["原本保持", "未変更保存は全バイト一致。部分編集は対象外パーツと未知フィールドを保全"],
        ["形式変換", "表現可能な意味を移す。外観・動作・編集可能性の差を計画に出し、許可のない損失を拒否"],
    ])
    lines += ["", "現行欄はPPTX/PPTMのコード調査による概要。行の全受入条件の達成や、新しい実アプリ検証を意味しない。ODPはmimetype検出のみで読書きコーデックなし、Keynoteもコーデックなし。両形式の各行の実装状態はすべて未実装。原本保持中心でも任意編集を許可する意味ではなく、影響が安全と判断できる範囲だけ保存できる。", ""]
    lines += table(["現行欄", "意味"], [[k, v] for k, v in {
        "基本範囲あり": "基本のread/write/editがあるが行の全条件は未達",
        "部分対応": "読取と生成・編集で境界が異なる",
        "原本保持中心": "未解釈または未対応部分を原本で保持。編集モデルは不十分",
        "未実装": "専用のAPI/処理なし",
        "拒否": "現行では明示的に失敗する",
        "対象外": "PPTX固有の実装状態としては該当しない",
    }.items()])
    lines += ["", "工程は主なモデル・初回対応を入れる順番。P2はODP読取、P3はODP生成・編集、P6はKeynote、P7は旧形式・暗号、P8は描画・再生。共通機能の工程表示だけで全形式の同時完成を意味しない。", ""]
    for category in categories:
        lines += [f"## {category['id']} {category['name']}", "", category["scope"], ""]
        lines += table(["形式", "表現・探索先"], [[k, v] for k, v in category["native"].items()])
        refs = [f"[{sid}]({sources[sid]['url']})" for sid in category["sources"]]
        lines += ["", "根拠・探索資料: " + "、".join(refs) + "。内部表現候補は規範仕様と解析資料を区別して検証する。", ""]
        lines += table(["ID", "機能", "API/モデル案", "工程", "現行PPTX", "固有の受入条件"], [
            [f["id"], f["name"], f["model"], f["phase"], STATUSES[f["baseline"]], f["acceptance"]]
            for f in category["features"]
        ])
        lines += [""]
    lines += ["## 根拠の種類", ""]
    lines += table(["ID", "資料", "種類"], [[s["id"], f"[{s['title']}]({s['url']})", s["kind"]] for s in data["sources"]])
    lines += ["", "追加の未知要素はこの台帳へ分類し、詳細スキーマ台帳でQName/field/record単位の未分類を追う。達成条件は[形式調査](format-research.md)と[実装計画](implementation-roadmap.md)に従う。", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    data = json.loads((ROOT / "docs/feature-catalog.json").read_text())
    output = render(data)
    target = ROOT / "docs/feature-catalog.md"
    if args.check:
        if not target.exists() or target.read_text() != output:
            raise SystemExit("機能台帳の生成結果が一致しません")
        print("機能台帳のID・資料・工程・生成結果: 整合")
    else:
        target.write_text(output)
        print(f"機能台帳を生成: {sum(len(c['features']) for c in data['categories'])}機能")


if __name__ == "__main__":
    main()
