import Foundation
import SwiftSlides

let arguments = CommandLine.arguments.dropFirst()
guard let command = arguments.first else { print("swiftslides inspect|text|copy|sample <path> [output]"); exit(2) }
let paths = Array(arguments.dropFirst())
guard let first = paths.first else { exit(2) }
do {
    switch command {
    case "inspect":
        let result = try Presentation.inspect(contentsOf:URL(filePath:first))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        print(String(decoding:try encoder.encode(result),as:UTF8.self))
    case "text": print(try Presentation(contentsOf:URL(filePath:first)).plainText)
    case "copy":
        guard paths.count == 2 else { exit(2) }
        let result = try Presentation(contentsOf:URL(filePath:first)).write(to:URL(filePath:paths[1]))
        for warning in result.warnings { print(warning.message) }
    case "sample":
        var presentation = Presentation(metadata:.init(title:"事業改善提案",creator:"SwiftSlides Example"))
        let titleStyle = TextStyle(font:.init(family:"Aptos Display",size:30,eastAsianFamily:"Yu Gothic"),bold:true,color:.theme("dk2"))
        let bodyStyle = TextStyle(font:.init(family:"Aptos",size:18,eastAsianFamily:"Yu Gothic"),color:.theme("dk2"))
        var overview = Slide(name:"提案の全体像",notes:.init("この資料は架空の事業データを使った作例です。"),background:.solid(.white))
        overview.addText("収益性を高める3つの施策",frame:.init(x:40,y:30,width:880,height:56),style:titleStyle)
        overview.addText("現状の課題から実行計画へ",frame:.init(x:40,y:94,width:880,height:30),style:bodyStyle)
        overview.addLine(from:(40,136),to:(920,136),stroke:.init(color:.theme("accent1"),width:2))
        let frames = try Layout.grid(in:.init(x:40,y:176,width:880,height:236),rows:1,columns:3,gap:24)
        for (i,copy) in ["01  顧客価値\n重点顧客に集中する","02  業務効率\n手順を標準化する","03  成長投資\n成果を毎月検証する"].enumerated() {
            overview.addShape(.roundedRectangle,frame:frames[i],fill:.solid(.theme("lt2")),stroke:.init(color:.theme("accent1"),width:1.5),text:.init(copy,style:bodyStyle,alignment:.center,insets:.init(18),verticalAlignment:.center))
        }
        overview.addText("経営判断：90日間の実証から始める",frame:.init(x:40,y:450,width:880,height:40),style:.init(font:.init(size:20,eastAsianFamily:"Yu Gothic"),bold:true,color:.theme("accent1")))
        presentation.slides.append(overview)
        var roadmap = Slide(name:"実行計画",background:.solid(.white))
        roadmap.addText("90日間の実行計画",frame:.init(x:40,y:30,width:880,height:60),style:titleStyle)
        let steps = try Layout.grid(in:.init(x:60,y:130,width:840,height:110),rows:1,columns:3,gap:48)
        for (i,copy) in ["1〜30日\n計測・仮説","31〜60日\n施策の実証","61〜90日\n評価・拡大"].enumerated() { roadmap.addShape(.rectangle,frame:steps[i],fill:.solid(.theme("accent1")),text:.init(copy,style:.init(font:.init(size:20,eastAsianFamily:"Yu Gothic"),bold:true,color:.white),alignment:.center,verticalAlignment:.center)) }
        for i in 0..<2 { roadmap.addLine(from:(steps[i].maxX+8,185),to:(steps[i+1].minX-8,185),stroke:.init(color:.theme("dk2"),width:2,endArrow:.triangle)) }
        let header = ["施策","担当","確認する成果"].map { TableCell($0,style:.init(font:.init(size:16,eastAsianFamily:"Yu Gothic"),bold:true,color:.white),fill:.solid(.theme("accent1"))) }
        let rows = [header,["顧客集中","営業","継続率"].map { TableCell($0,style:bodyStyle,fill:.solid(.theme("lt2"))) },["業務標準化","運用","作業時間"].map { TableCell($0,style:bodyStyle) }]
        roadmap.addTable(.init(columnWidths:[250,180,410],rowHeights:[44,52,52],rows:rows),frame:.init(x:60,y:296,width:840,height:148))
        presentation.slides.append(roadmap)
        try presentation.write(to:URL(filePath:first))
        print("保存しました: \(first)")
    default: exit(2)
    }
} catch { fputs("\(error)\n",stderr); exit(1) }
