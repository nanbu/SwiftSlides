import Foundation
import SlideCore

extension KeynoteSource {
    func listEntries(_ id:UInt64,depth:Int = 0,seen:Set<UInt64> = []) throws -> [UInt64:[KeynoteField]] {
        guard depth < options.limits.maxXMLDepth,!seen.contains(id) else { throw SlideError.corruptedPackage("Keynote表list循環") }
        let o=try object(id);guard [6005,6011,6201].contains(o.type) else { throw SlideError.corruptedPackage("Keynote表list型不正") }
        var result:[UInt64:[KeynoteField]]=[:],seen=seen;seen.insert(id)
        for e in o.fields where e.number == 3 {
            let f=try e.message(maxFields:options.limits.maxXMLNodes),key=try Wire.scalar(f,1)
            guard result[key] == nil else { throw SlideError.corruptedPackage("Keynote表list key重複") };result[key]=f
        }
        if o.type != 6011 {
            for e in o.fields where e.number == 4 {
                for (key,value) in try listEntries(Wire.scalar(e.message(maxFields:options.limits.maxXMLNodes),1),depth:depth+1,seen:seen) {
                    guard result[key] == nil else { throw SlideError.corruptedPackage("Keynote表segment key重複") };result[key]=value
                }
            }
        };return result
    }
    func nativeTable(_ info:KeynoteObject,budget:inout Int,cellBudget:inout Int) throws -> Table {
        let model=try object(ref(info.fields,2));guard model.type == 6001 else { throw SlideError.corruptedPackage("Keynote tableModel型不正") }
        let f=model.fields,r=try Wire.scalar(f,6),c=try Wire.scalar(f,7)
        guard r > 0,c > 0,r <= UInt64(options.limits.maxTableCells-cellBudget),c <= UInt64(options.limits.maxTableCells-cellBudget)/r else { throw SlideError.limitExceeded("Keynote表セル展開量") }
        let rows=Int(r),columns=Int(c);cellBudget += rows*columns
        let store=try fields(Self.bytes(f,4))
        var strings:[UInt64:String]=[:],rich:[UInt64:TextBody]=[:],formulas:[UInt64:Data]=[:]
        if store.contains(where: { $0.number == 6 }) { for (id, entry) in try listEntries(ref(store, 6)) { formulas[id] = try Self.bytes(entry, 5) } }
        if store.contains(where:{ $0.number == 4 }) { for (id,e) in try listEntries(ref(store,4)) { if let s=try Self.string(e,3) { strings[id]=s } } }
        if store.contains(where:{ $0.number == 17 }) {
            for (id,e) in try listEntries(ref(store,17)) where e.contains(where:{ $0.number == 9 }) {
                let payload=try object(ref(e,9));rich[id]=try text(ref(payload.fields,1),budget:&budget)
            }
        }
        let styleEntries = try store.contains(where: { $0.number == 5 }) ? listEntries(ref(store,5)) : [:]
        let formatEntries = try store.contains(where: { $0.number == 22 }) ? listEntries(ref(store,22)) : [:]
        let errorEntries = try store.contains(where: { $0.number == 12 }) ? listEntries(ref(store,12)) : [:]
        var table=Table(columnWidths:Array(repeating:try number(f,17) ?? 0,count:columns),rowHeights:Array(repeating:try number(f,16) ?? 0,count:rows),rows:Array(repeating:Array(repeating:TableCell(),count:columns),count:rows),styleID:f.contains(where:{ $0.number == 3 }) ? String(try ref(f,3)) : nil)
        guard (table.rowHeights+table.columnWidths).allSatisfy({ $0 >= 0 }) else { throw SlideError.corruptedPackage("Keynote表寸法不正") }
        func headers(_ id:UInt64,dimension:inout [Double]) throws {
            let o=try object(id);var seen=Set<UInt64>()
            for e in o.fields where e.number == 2 {
                let f=try e.message(maxFields:options.limits.maxXMLNodes),i=try Wire.scalar(f,1)
                guard i < UInt64(dimension.count),seen.insert(i).inserted else { throw SlideError.corruptedPackage("Keynote表header index不正") }
                if let value=try number(f,2),value != 0 { guard value >= 0 else { throw SlideError.corruptedPackage("Keynote表header負の寸法") };dimension[Int(i)]=value }
            }
        }
        if let rowHeaders=try child(store,1) { for bucket in rowHeaders where bucket.number == 2 { try headers(Wire.scalar(bucket.message(maxFields:options.limits.maxXMLNodes),1),dimension:&table.rowHeights) } }
        if store.contains(where:{ $0.number == 2 }) { try headers(ref(store,2),dimension:&table.columnWidths) }
        guard let tiles=try child(store,3) else { throw SlideError.corruptedPackage("Keynote表tiles不在") }
        let tileSize=try Self.optionalInteger(tiles,2) ?? 256;guard tileSize > 0 else { throw SlideError.corruptedPackage("Keynote tile寸法不正") }
        var occupied=Set<Int>()
        for entry in tiles where entry.number == 1 {
            let e=try entry.message(maxFields:options.limits.maxXMLNodes),tileID=try Wire.scalar(e,1),tile=try object(ref(e,2))
            guard tile.type == 6002 else { throw SlideError.corruptedPackage("Keynote tile型不正") }
            guard try Self.optionalInteger(tile.fields,7) == 1 else { throw SlideError.unsupportedContainer("Keynote表のpre-BNC storageを原本に保持します") }
            let (base,overflow)=tileID.multipliedReportingOverflow(by:tileSize);guard !overflow else { throw SlideError.corruptedPackage("Keynote tile offset桁あふれ") }
            for row in tile.fields where row.number == 5 {
                try Task.checkCancellation()
                let f=try row.message(maxFields:options.limits.maxXMLNodes),local=try Wire.scalar(f,1)
                guard local < tileSize,base < r,local < r-base else { throw SlideError.corruptedPackage("Keynote tile row範囲不正") }
                let ri=Int(base+local),bytes=[UInt8](try Self.bytes(f,6)),offsetBytes=[UInt8](try Self.bytes(f,7)),wide=(try Self.optionalInteger(f,8)) == 1
                guard offsetBytes.count % 2 == 0 else { throw SlideError.corruptedPackage("Keynote cell offsets長不正") }
                var offsets:[Int]=[]
                for i in stride(from:0,to:offsetBytes.count,by:2) { let n=Int(Int16(bitPattern:UInt16(offsetBytes[i]) | UInt16(offsetBytes[i+1])<<8));offsets.append(n < 0 ? -1 : wide ? n*4 : n) }
                guard offsets.dropFirst(columns).allSatisfy({ $0 == -1 }) else { throw SlideError.corruptedPackage("Keynoteセル列範囲不正") }
                offsets=Array(offsets.prefix(columns))
                let actual=offsets.filter { $0 >= 0 };guard actual.count == Int(try Wire.scalar(f,2)),actual == actual.sorted(),Set(actual).count == actual.count else { throw SlideError.corruptedPackage("Keynote cell offsets順序/count不正") }
                for column in offsets.indices where offsets[column] >= 0 {
                    let start=offsets[column],end=offsets.dropFirst(column+1).first { $0 >= 0 } ?? bytes.count
                    guard start < end,end <= bytes.count,occupied.insert(ri*columns+column).inserted else { throw SlideError.corruptedPackage("Keynote cell record範囲/重複不正") }
                    let record=try NativeCellRecord(Array(bytes[start..<end]));var cell=TableCell()
                    switch record.type {
                    case 0,1: break
                    case 4: cell.value = .init(type: "formula", lexicalValue: record.decimal ?? record.double.map(String.init(describing:))); if let value = cell.value?.lexicalValue { cell.text = .init(value) }
                    case 8: cell.value = .init(type: "error", lexicalValue: nil)
                    case 2,10: let s=record.decimal ?? record.double.map(String.init(describing:));cell.value = .init(type:"float",lexicalValue:s);cell.text = .init(s ?? "")
                    case 3: guard let id=record.stringID,let s=strings[id] else { throw SlideError.corruptedPackage("Keynoteセル文字参照不在") };cell.text = .init(s);cell.value = .init(type:"string",lexicalValue:s)
                    case 5: if let seconds=record.seconds { let date=Date(timeIntervalSinceReferenceDate:seconds),formatter=ISO8601DateFormatter();formatter.timeZone=TimeZone(secondsFromGMT:0);let value=formatter.string(from:date);guard !value.isEmpty else { throw SlideError.corruptedPackage("Keynoteセル日時範囲不正") };cell.value = .init(type:"date",lexicalValue:value);cell.text = .init(value) }
                    case 6: if let value=record.double { let text=value == 0 ? "false" : "true";cell.value = .init(type:"boolean",lexicalValue:text);cell.text = .init(text) }
                    case 7: if let value=record.double { let text="PT\(value)S";cell.value = .init(type:"time",lexicalValue:text);cell.text = .init(text) }
                    case 9: if let id=record.richID { guard let body=rich[id] else { throw SlideError.corruptedPackage("Keynoteセルrich参照不在") };cell.text=body } else if let id=record.stringID { guard let s=strings[id] else { throw SlideError.corruptedPackage("Keynoteセル文字参照不在") };cell.text = .init(s) }
                    default: throw SlideError.unsupportedContainer("Keynoteセル型\(record.type)・formula/errorは原本に保持します")
                    }
                    if let fid = record.formulaID { guard let formula = formulas[fid] else { throw SlideError.corruptedPackage("Keynote式参照不在") }; cell.nativeFormula = try nativeFormula(formula, row: ri, column: column) }
                    var properties: [String:NativeValue] = [:]
                    for key in ["cellStyle", "textStyle"] {
                        if let sid = record.references[key], sid != 0 {
                            guard let entry = styleEntries[sid] else { throw SlideError.corruptedPackage("Keynoteセルstyle参照不在") }
                            let objectID = try ref(entry,4)
                            if key == "cellStyle" { try applyCellStyle(objectID,cell:&cell) }
                            else {
                                let style = try characterStyle(objectID)
                                for pi in cell.text.paragraphs.indices {
                                    cell.text.paragraphs[pi].style = style.paragraph.overlaying(cell.text.paragraphs[pi].style)
                                    cell.text.paragraphs[pi].defaultTextStyle = style.text.overlaying(cell.text.paragraphs[pi].defaultTextStyle)
                                    for ri in cell.text.paragraphs[pi].runs.indices { cell.text.paragraphs[pi].runs[ri].style = style.text.overlaying(cell.text.paragraphs[pi].runs[ri].style) }
                                }
                            }
                        }
                    }
                    for key in ["numberFormat","currencyFormat","dateFormat","durationFormat","textFormat","booleanFormat"] {
                        if let id = record.references[key], id != 0 {
                            guard let entry = formatEntries[id] else { throw SlideError.corruptedPackage("Keynoteセルformat参照不在") }
                            properties[key] = .bytes(entry.reduce(into:Data()) { $0.append($1.rawData) })
                        }
                    }
                    if let id = record.errorID, let entry = errorEntries[id] { properties["error"] = .bytes(entry.reduce(into:Data()) { $0.append($1.rawData) }) }
                    cell.nativeProperties = .init(storageVersion:5,references:record.references,properties:properties,source:Data(bytes[start..<end]))
                    guard cell.text.plainText.utf8.count <= options.limits.maxPartBytes-budget else { throw SlideError.limitExceeded("Keynote表の文字展開量") };budget += cell.text.plainText.utf8.count
                    table.rows[ri][column]=cell
                }
            }
        }
        try applyMerges(model: f, store: store, table: &table)
        return table
    }
    func applyCellStyle(_ id: UInt64, cell: inout TableCell) throws {
        for object in try styleLayers(id) where object.type == 6004 {
            guard let props = try child(object.fields,11) else { continue }
            if let fill = try child(props,1) { cell.fill = try nativeFill(fill,part:object.part) }
            if let wrap = try Self.optionalInteger(props,3) { cell.text.wrapsText = wrap != 0 }
            if let alignment = try Self.optionalInteger(props,8) { cell.text.verticalAlignment = [0:.top,1:.center,2:.bottom][alignment] }
            if let padding = try child(props,9) {
                cell.insets = try .init(top:number(padding,2) ?? 0,left:number(padding,1) ?? 0,bottom:number(padding,4) ?? 0,right:number(padding,3) ?? 0)
            }
            for (field, edge) in [(UInt32(10),TableCellBorder.Edge.top),(11,.right),(12,.bottom),(13,.left)] {
                if let source = try child(props,field) {
                    var borders = cell.borders ?? []; borders.removeAll { $0.edge == edge }
                    borders.append(try .init(edge:edge,stroke:nativeStroke(source),isExplicitlyNone:source.isEmpty)); cell.borders = borders
                }
            }
        }
    }

}

private struct NativeCellRecord {
    let type:UInt8
    var references: [String:UInt64] = [:]
    var decimal:String?,double:Double?,seconds:Double?,stringID:UInt64?,richID:UInt64?,formulaID:UInt64?,errorID:UInt64?
    init(_ b:[UInt8]) throws {
        guard b.count >= 12 else { throw SlideError.corruptedPackage("Keynoteセルheader切断") }
        guard b[0] == 5 else { throw SlideError.unsupportedContainer("Keynoteセルstorage版\(b[0])を原本に保持します") };type=b[1]
        let flags=b[8..<12].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8*$1.offset) };var offset=12
        guard flags & ~0x000f_ffff == 0 else { throw SlideError.unsupportedContainer("Keynote未知セルfieldを原本に保持します") }
        func take(_ n:Int) throws -> [UInt8] { guard n <= b.count-offset else { throw SlideError.corruptedPackage("Keynoteセルfield切断") };defer { offset += n };return Array(b[offset..<offset+n]) }
        func floating() throws -> Double { let bytes=try take(8),bits=bytes.enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8*$1.offset) },value=Double(bitPattern:bits);guard value.isFinite else { throw SlideError.corruptedPackage("Keynote非有限セル数値") };return value }
        if flags & 1 != 0 {
            let d=try take(16),exponent=(Int(d[15]&0x7f)<<7 | Int(d[14]>>1))-0x1820
            var significand=Decimal(Int(d[14]&1))
            for i in stride(from:13,through:0,by:-1) { significand=significand*256+Decimal(Int(d[i])) }
            decimal=(d[15]&0x80 == 0 ? "" : "-")+String(describing:significand)+(exponent == 0 ? "" : "e\(exponent)")
        }
        if flags & 2 != 0 { double=try floating() };if flags & 4 != 0 { seconds=try floating() }
        for bit in 3...19 where flags & (1<<bit) != 0 {
            let bytes=try take(4),n=bytes.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8*$1.offset) }
            let names = [3:"string",4:"richText",5:"cellStyle",6:"textStyle",7:"conditionalStyle",8:"conditionalRuleStyle",9:"formula",10:"control",11:"error",12:"suggestion",13:"numberFormat",14:"currencyFormat",15:"dateFormat",16:"durationFormat",17:"textFormat",18:"booleanFormat",19:"comment"]
            references[names[bit]!] = UInt64(n)
            if bit == 3 { stringID=UInt64(n) };if bit == 4 { richID=UInt64(n) };if bit == 9 { formulaID=UInt64(n) };if bit == 11 { errorID=UInt64(n) }
        }
        guard b.dropFirst(offset).allSatisfy({ $0 == 0 }) else { throw SlideError.unsupportedContainer("Keynoteセル末尾の未知fieldを保持します") }
    }
}
