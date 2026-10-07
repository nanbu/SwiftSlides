import Foundation
import SlideCore

enum ModelValidation {
    static func number(_ n: Double, nonnegative: Bool = false) throws { guard n.isFinite, abs(n) < 1e11, !nonnegative || n >= 0 else { throw SlideError.invalidModel("非有限・範囲外・負の寸法") } }
    static func string(_ s: String) throws { guard s.unicodeScalars.allSatisfy({ v in v.value == 9 || v.value == 10 || v.value == 13 || v.value >= 32 && v.value != 0xFFFE && v.value != 0xFFFF }) else { throw SlideError.invalidModel("XMLに保存できない制御文字") } }
    static func color(_ c: Color) throws {
        switch c {
        case .rgb(let hex): guard hex.count == 6, hex.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { throw SlideError.invalidModel("RGBは6桁の16進数です") }
        case .value: break // 読取投影は保全可。書換えはXML writerで拒否する。
        case .theme(let key): guard ["dk1","lt1","dk2","lt2","accent1","accent2","accent3","accent4","accent5","accent6","hlink","folHlink","bg1","bg2","tx1","tx2","phClr"].contains(key) else { throw SlideError.invalidModel("未知のテーマ色") }
        }
    }
    static func fill(_ f: Fill?) throws { if case .solid(let c) = f { try color(c) } }
    static func stroke(_ s: Stroke?) throws { if let s { try color(s.color); try number(s.width,nonnegative:true) } }
    static func rect(_ r: Rect) throws { try number(r.x); try number(r.y); try number(r.width,nonnegative:true); try number(r.height,nonnegative:true) }
    static func insets(_ i: Insets?) throws { if let i { for value in [i.top,i.left,i.bottom,i.right] { try number(value,nonnegative:true) } } }
    static func style(_ s: TextStyle, allowSupplemental: Bool = false) throws {
        if let size = s.font.size { guard size >= 1, size <= 4000 else { throw SlideError.invalidModel("フォントサイズは1〜4000ptです") }; try number(size) }
        for text in [s.font.family,s.font.eastAsianFamily,s.font.complexScriptFamily,s.language].compactMap({ $0 }) { try string(text) }
        guard allowSupplemental || s.font.supplementalFamilies.isEmpty else { throw SlideError.invalidModel("script別補助フォントはThemeで指定します") }
        for (script,family) in s.font.supplementalFamilies { guard script.count == 4 else { throw SlideError.invalidModel("scriptタグは4文字です") }; try string(script); try string(family) }
        if let c = s.color { try color(c) }
    }
    static func paragraphStyle(_ s: ParagraphStyle) throws {
            if let l = s.level, !(0...8).contains(l) { throw SlideError.invalidModel("段落レベルは0〜8です") }
            for n in [s.leftMargin,s.indent,s.spaceBefore,s.spaceAfter,s.lineSpacing].compactMap({$0}) { try number(n) }
            if s.lineSpacingValue == nil, let l = s.lineSpacing, l < 0 { throw SlideError.invalidModel("行間は正です") }
            if case .character(let c) = s.bullet { guard c.count == 1 else { throw SlideError.invalidModel("箇条書きの記号は1文字です") }; try string(c) }
            if case .numbered(let type,let start) = s.bullet { let allowed = ["alphaLcParenBoth","alphaUcParenBoth","alphaLcParenR","alphaUcParenR","alphaLcPeriod","alphaUcPeriod","arabicParenBoth","arabicParenR","arabicPeriod","arabicPlain","romanLcParenBoth","romanUcParenBoth","romanLcParenR","romanUcParenR","romanLcPeriod","romanUcPeriod","circleNumDbPlain","circleNumWdBlackPlain","circleNumWdWhitePlain","arabicDbPeriod","arabicDbPlain","ea1ChsPeriod","ea1ChsPlain","ea1ChtPeriod","ea1ChtPlain","ea1JpnChsDbPeriod","ea1JpnKorPlain","ea1JpnKorPeriod","arabic1Minus","arabic2Minus","hebrew2Minus","thaiAlphaPeriod","thaiAlphaParenR","thaiAlphaParenBoth","thaiNumPeriod","thaiNumParenR","thaiNumParenBoth","hindiAlphaPeriod","hindiNumPeriod","hindiNumParenR","hindiAlpha1Period"]; guard allowed.contains(type), (1...32767).contains(start) else { throw SlideError.invalidModel("箇条書き番号の種類・開始値が不正です") } }
        for value in [s.effectiveLineSpacing,s.effectiveSpaceBefore,s.effectiveSpaceAfter].compactMap({ $0 }) {
            switch value { case .points(let n), .percentage(let n): try number(n,nonnegative:true) }
        }
    }
    static func text(_ t: TextBody?) throws {
        try Task.checkCancellation()
        guard let t else { return }; try insets(t.insets)
        for p in t.paragraphs {
            try Task.checkCancellation()
            try paragraphStyle(p.style)
            try style(p.defaultTextStyle); try style(p.endTextStyle)
            for run in p.runs { try string(run.text); try style(run.style); if let link = run.link { switch link { case .external(let u), .slide(let u): try string(u); guard !u.isEmpty else { throw SlideError.invalidModel("空のリンク") } } } }
        }
    }
    static func element(_ e: Element, ids: inout Set<String>, depth: Int) throws {
        try Task.checkCancellation()
        guard depth < 128, !e.id.isEmpty, ids.insert(e.id).inserted else { throw SlideError.invalidModel("要素IDの重複またはグループが深すぎます") }
        try string(e.name); if let f = e.frame { try rect(f) }; try number(e.rotation); try fill(e.fill); try stroke(e.stroke); try text(e.text)
        if let geometry = e.geometry { guard !geometry.preset.isEmpty, geometry.preset.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) }) else { throw SlideError.invalidModel("図形プリセット名が不正です") } }
        if let image = e.image {
            try string(image.alternativeText)
            if image.data != nil { guard ["image/png","image/jpeg","image/gif","image/tiff","image/bmp","image/svg+xml","image/x-emf","image/x-wmf"].contains(image.contentType ?? "") else { throw SlideError.invalidModel("新規画像のContent-Typeが未対応です") } }
        }
        if let t = e.table {
            guard !t.columnWidths.isEmpty, !t.rows.isEmpty, t.rowHeights.count == t.rows.count, t.rows.allSatisfy({ $0.count == t.columnWidths.count }) else { throw SlideError.invalidModel("表の行列数・寸法数が不整合です") }
            for width in t.columnWidths { try number(width,nonnegative:true) }; for height in t.rowHeights { try number(height,nonnegative:true) }
            for row in t.rows { for cell in row { try text(cell.text); try fill(cell.fill); try stroke(cell.border); try insets(cell.insets); guard cell.rowSpan >= 1, cell.columnSpan >= 1 else { throw SlideError.invalidModel("セル結合のサイズが不正です") } } }
            if let style = t.styleID { try string(style) }
        }
        if e.kind == .connector, e.text != nil { throw SlideError.invalidModel("線のラベルは別のテキストボックスで指定します") }
        switch e.kind {
        case .shape,.connector: guard e.image == nil, e.table == nil, e.children.isEmpty else { throw SlideError.invalidModel("図形に別種類の内容が指定されています") }
        case .image: guard e.text == nil, e.table == nil, e.children.isEmpty else { throw SlideError.invalidModel("画像に別種類の内容が指定されています") }
        case .table: guard e.table != nil, e.text == nil, e.image == nil, e.children.isEmpty else { throw SlideError.invalidModel("表の内容が不整合です") }
        case .group: guard e.text == nil, e.image == nil, e.table == nil else { throw SlideError.invalidModel("グループに別種類の内容が指定されています") }
        case .opaque: break
        }
        if let child = e.childFrame { try rect(child) }
        for child in e.children { try element(child,ids:&ids,depth:depth+1) }
    }
    static func presentation(_ p: Presentation) throws {
        try Task.checkCancellation()
        try number(p.size.width); try number(p.size.height); guard p.size.width > 0, p.size.height > 0 else { throw SlideError.invalidModel("スライド寸法は正です") }
        if let number = p.firstSlideNumber, !(Int(Int32.min)...Int(Int32.max)).contains(number) { throw SlideError.invalidModel("最初のスライド番号が範囲外です") }
        for value in [p.metadata.title,p.metadata.subject,p.metadata.creator,p.metadata.description,p.metadata.keywords].compactMap({$0}) { try string(value) }
        try string(p.theme.name); try style(.init(font:p.theme.titleFont),allowSupplemental:true); try style(.init(font:p.theme.bodyFont),allowSupplemental:true)
        for key in ["dk1","lt1","dk2","lt2","accent1","accent2","accent3","accent4","accent5","accent6","hlink","folHlink"] { guard let hex = p.theme.colors[key] else { throw SlideError.invalidModel("テーマ色 \(key) がありません") }; try color(.rgb(hex)) }
        var slideIDs: Set<String> = []
        for slide in p.slides { guard !slide.id.isEmpty, slideIDs.insert(slide.id).inserted else { throw SlideError.invalidModel("スライドIDが重複しています") }; try string(slide.name); try fill(slide.background); try text(slide.notes); var ids: Set<String> = []; for e in slide.elements { try element(e,ids:&ids,depth:0) } }
    }
}
