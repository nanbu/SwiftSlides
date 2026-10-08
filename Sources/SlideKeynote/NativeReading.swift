import Foundation
import SlideCore

// 型・field番号はkeynote-parserの14.4 registryと公開wire schemaに基づく。
// セルv5の配列はSwiftSheets（MIT）の読取契約を参照。未知属性は原本索引に残す。
extension KeynoteSource {
    func child(_ f:[KeynoteField],_ n:UInt32) throws -> [KeynoteField]? {
        guard f.contains(where:{ $0.number == n }) else { return nil }
        return try fields(Self.bytes(f,n))
    }
    func number(_ f:[KeynoteField],_ n:UInt32) throws -> Double? {
        let values=f.filter { $0.number == n };guard !values.isEmpty else { return nil }
        guard values.count == 1,let value=values[0].float64 ?? values[0].float32.map(Double.init),value.isFinite else { throw SlideError.corruptedPackage("Keynote数値field不正: \(n)") };return value
    }
    func nativeColor(_ f:[KeynoteField]) throws -> Color? {
        let model=try Wire.scalar(f,1),alpha=try number(f,6)
        let rgb:[Double]
        if model == 1 {
            guard (try Self.optionalInteger(f,12) ?? 1) == 1 else { return nil } // P3はsRGBへ推測変換しない。
            rgb=try [3,4,5].map { try Self.float(f,UInt32($0)) }
        } else if model == 3 { let w=try Self.float(f,11);rgb=[w,w,w] }
        else { return nil }
        guard rgb.allSatisfy({ (0...1).contains($0) }),alpha.map({ (0...1).contains($0) }) ?? true else { throw SlideError.corruptedPackage("Keynote色範囲不正") }
        let hex=rgb.map { String(format:"%02X",Int(($0*255).rounded())) }.joined()
        return alpha.map { .value(.init(base:.sRGB(hex),transforms:[.init(name:"alpha",value:String($0*100_000))])) } ?? .rgb(hex)
    }
    func nativeFill(_ f:[KeynoteField],part:String) throws -> Fill? {
        if let c=try child(f,1) { return try nativeColor(c).map(Fill.solid) }
        if let g=try child(f,2) {
            var stops:[GradientStop]=[]
            for field in g where field.number == 2 {
                let s=try field.message(maxFields:options.limits.maxXMLNodes)
                guard let c=try child(s,1),let color=try nativeColor(c),let position=try number(s,2) else { return nil }
                guard (0...1).contains(position) else { throw SlideError.corruptedPackage("Keynote gradient位置不正") }
                stops.append(.init(position:position,color:color))
            }
            let type=try Self.optionalInteger(g,1) ?? 0,angle=try child(g,5).flatMap { try number($0,2) }
            return .gradient(.init(stops:stops,angle:angle,path:type == 1 ? "circle" : nil))
        }
        if let image=try child(f,3),image.contains(where:{ $0.number == 6 }) {
            let id=try ref(image,6),reference=PartReference(relationshipID:String(id),path:assets[id],externalTarget:dataReferences.first { $0.id == id }?.remoteURL)
            return .picture(.init(part:part,image:reference,isTiled:(try Self.optionalInteger(image,2)) == 2))
        }
        // 空FillArchiveは明示的な塗りなし。未知extensionはnoneに変えない。
        return f.isEmpty ? Fill.none : nil
    }
    func nativeStroke(_ f:[KeynoteField]) throws -> Stroke? {
        guard let c=try child(f,1),let color=try nativeColor(c),let width=try number(f,2) else { return nil }
        guard width >= 0 else { throw SlideError.corruptedPackage("Keynote負の線幅") }
        return .init(color:color,width:width)
    }
    func styleLayers(_ id:UInt64,depth:Int = 0,seen:Set<UInt64> = []) throws -> [KeynoteObject] {
        guard depth < options.limits.maxXMLDepth,!seen.contains(id) else { throw SlideError.corruptedPackage("Keynote style参照循環") }
        let value=try object(id);var seen=seen;seen.insert(id)
        guard [2021,2022,2025,3015,3016,6003,6004].contains(value.type) else { return [value] }
        var base=try fields(Self.bytes(value.fields,1))
        if value.type == 2025 { base=try fields(Self.bytes(base,1)) }
        let parents=base.contains(where:{ $0.number == 3 }) ? try styleLayers(ref(base,3),depth:depth+1,seen:seen) : []
        return parents+[value]
    }
    func characterStyle(_ id:UInt64) throws -> (text:TextStyle,paragraph:ParagraphStyle) {
        var text=TextStyle(),paragraph=ParagraphStyle()
        for object in try styleLayers(id) where [2021,2022].contains(object.type) {
            if let f=try child(object.fields,11) {
                let value=try TextStyle(font:.init(family:Self.string(f,5),size:number(f,3)),bold:Self.optionalInteger(f,1).map { $0 != 0 },italic:Self.optionalInteger(f,2).map { $0 != 0 },underline:Self.optionalInteger(f,11).map { $0 != 0 },color:child(f,7).flatMap(nativeColor),language:Self.string(f,9))
                var appearanceText = value
                let strike = try Self.optionalInteger(f, 12).map { String($0) }, caps = try Self.optionalInteger(f, 13).map { [UInt64(0): "none", 1: "all", 2: "small", 3: "title"][$0] ?? "native:\($0)" }
                let underline = try Self.optionalInteger(f, 11).map { String($0) }
                let baselinePoints = try number(f, 14), fontSize = value.font.size ?? text.font.size
                let baseline = baselinePoints.flatMap { shift in fontSize.flatMap { $0 > 0 ? shift / $0 : nil } }
                appearanceText.appearance = try .init(spacing: number(f, 27), baseline: baseline, baselinePoints: baselinePoints, capitalization: caps, strike: strike, underlineStyle: underline, kerning: number(f, 15))
                text=text.overlaying(appearanceText)
                if try Self.optionalInteger(f,4) == 1 { text.font.family=nil }
                if try Self.optionalInteger(f,6) == 1 { text.color=nil }
                if try Self.optionalInteger(f,8) == 1 { text.language=nil }
            }
            if let f=try child(object.fields,12) {
                let align=try Self.optionalInteger(f,1).flatMap { [UInt64(0):TextAlignment.left,1:.right,2:.center,3:.justified][$0] }
                paragraph=try paragraph.overlaying(.init(alignment:align,leftMargin:number(f,11),indent:number(f,7),spaceBefore:number(f,21),spaceAfter:number(f,20)))
            }
        }
        return (text,paragraph)
    }
    func attributedText(_ string:String,storage:KeynoteObject) throws -> TextBody {
        func entries(_ n:UInt32) throws -> [(Int,UInt64?)] {
            guard let table=try child(storage.fields,n) else { return [] }
            var result:[(Int,UInt64?)]=[],last = -1
            for entry in table where entry.number == 1 {
                let f=try entry.message(maxFields:options.limits.maxXMLNodes),offset=try Wire.scalar(f,1)
                guard offset <= UInt64(string.utf16.count),Int(offset) > last else { throw SlideError.corruptedPackage("Keynote文字run範囲/順序不正") };last=Int(offset)
                let id=f.contains(where:{ $0.number == 2 }) ? try ref(f,2) : nil
                result.append((Int(offset),id))
            };return result
        }
        let chars=try entries(8),paras=try entries(5),links=try entries(11)
        var styles:[UInt64:(text:TextStyle,paragraph:ParagraphStyle)]=[:],urls:[UInt64:String]=[:]
        for (_,id) in chars+paras { if let id,styles[id] == nil { styles[id]=try characterStyle(id) } }
        for (_,id) in links { if let id { let o=try object(id);if o.type == 2032,let url=try Self.string(o.fields,2) { urls[id]=url } } }
        func active(_ values:[(Int,UInt64?)],_ offset:Int) -> UInt64? { values.last { $0.0 <= offset }?.1 }
        func substring(_ a:Int,_ b:Int) throws -> String {
            guard let start=String.Index(string.utf16.index(string.utf16.startIndex,offsetBy:a),within:string),let end=String.Index(string.utf16.index(string.utf16.startIndex,offsetBy:b),within:string) else { throw SlideError.corruptedPackage("Keynote文字runがUTF16 surrogateを分割") };return String(string[start..<end])
        }
        var result=TextBody(),offset=0
        for line in string.split(separator:"\n",omittingEmptySubsequences:false) {
            try Task.checkCancellation()
            let end=offset+line.utf16.count,base=active(paras,offset).flatMap { styles[$0] },cuts=Set([offset,end]+(chars+links).map(\.0).filter { $0 > offset && $0 < end }).sorted()
            var p=Paragraph(style:base?.paragraph ?? .init(),defaultTextStyle:base?.text ?? .init())
            for (a,b) in zip(cuts,cuts.dropFirst()) { let style=active(chars,a).flatMap { styles[$0]?.text } ?? .init(),url=active(links,a).flatMap { urls[$0] };p.runs.append(try .init(substring(a,b),style:p.defaultTextStyle.overlaying(style),link:url.map(Link.external))) }
            result.paragraphs.append(p);offset=end+1
        }
        return result
    }
    func shapeStyle(_ id:UInt64,element:inout Element) throws {
        for object in try styleLayers(id) {
            var f=object.fields
            if object.type == 2025 {
                if let props=try child(f,11),var text=element.text {
                    text.verticalAlignment=try Self.optionalInteger(props,2).flatMap { [UInt64(0):VerticalAlignment.top,1:.center,2:.bottom][$0] }
                    if let padding=try child(props,6) { text.insets=try .init(top:number(padding,2) ?? 0,left:number(padding,1) ?? 0,bottom:number(padding,4) ?? 0,right:number(padding,3) ?? 0) }
                    element.text=text
                }
                f=try fields(Self.bytes(f,1))
            }
            if [2025,3015].contains(object.type),let props=try child(f,11) {
                if let fill=try child(props,1) { element.fill=try nativeFill(fill,part:object.part) }
                if let stroke=try child(props,2) { element.stroke=try nativeStroke(stroke) }
            }
        }
    }
    func nativeChart(_ object:KeynoteObject) throws -> Chart {
        let f=try fields(Self.bytes(object.fields,10000)),kind=try Self.optionalInteger(f,1) ?? 0,direction=try Self.optionalInteger(f,5) ?? 0
        var series:[ChartSeries]=[]
        if let grid=try child(f,7),direction == 1 || direction == 2 {
            let rowNames=try grid.filter { $0.number == 1 }.map { guard let s=$0.utf8 else { throw SlideError.corruptedPackage("Keynote chart row名UTF8不正") };return s },columnNames=try grid.filter { $0.number == 2 }.map { guard let s=$0.utf8 else { throw SlideError.corruptedPackage("Keynote chart column名UTF8不正") };return s }
            var rows:[[Double?]]=[]
            for row in grid where row.number == 3 {
                let f=try row.message(maxFields:options.limits.maxXMLNodes)
                rows.append(try f.filter { $0.number == 1 }.map { try number($0.message(maxFields:options.limits.maxXMLNodes),1) })
            }
            let count=direction == 1 ? max(rows.count,rowNames.count) : max(rows.map(\.count).max() ?? 0,columnNames.count)
            guard count <= options.limits.maxTableCells,rows.reduce(0,{ $0+$1.count }) <= options.limits.maxTableCells else { throw SlideError.limitExceeded("Keynote chart grid") }
            for index in 0..<count {
                let names=direction == 1 ? columnNames : rowNames,titleNames=direction == 1 ? rowNames : columnNames
                let values=direction == 1 ? (rows.indices.contains(index) ? rows[index] : []) : rows.map { $0.indices.contains(index) ? $0[index] : nil }
                let categories=ChartData(source:.stringLiteral,formula:nil,pointCount:names.count,formatCode:nil,points:names.enumerated().map { .init(index:$0.offset,text:$0.element) },rawXML:"")
                let data=ChartData(source:.numberLiteral,formula:nil,pointCount:values.count,formatCode:nil,points:values.enumerated().compactMap { i,v in v.map { .init(index:i,text:String($0)) } },rawXML:"")
                series.append(.init(index:index,order:index,title:titleNames.indices.contains(index) ? titleNames[index] : nil,titleData:nil,categories:categories,values:data,fill:nil,stroke:nil,rawXML:""))
            }
        }
        return .init(part:.init(relationshipID:String(object.id),path:object.part),groups:[.init(kind:"keynote:\(kind)",grouping:nil,orientation:direction == 1 ? "row" : direction == 2 ? "column" : nil,series:series,axisIDs:[],rawXML:"")],axes:try nativeAxes(f),title:nil,legendPosition:nil,externalData:nil,rawXML:"")
    }
    func nativeTime(_ object:KeynoteObject,slide:inout Slide) throws {
        let ns="urn:swiftslides:keynote:timing"
        func properties(_ f:[KeynoteField],_ names:[UInt32:String]) throws -> [String:String] {
            var result:[String:String]=[:]
            for (n,name) in names {
                if let field=f.first(where:{ $0.number == n }) {
                    if let i=field.integer { result[name]=String(i) }
                    else if [1,5].contains(field.wireType),let v=try number(f,n) { result[name]=String(v) }
                    else if let s=field.utf8 { result[name]=s }
                }
            };return result
        }
        if let transition=try child(object.fields,4),let attrs=try child(transition,2) {
            let animation=try child(attrs,8) ?? attrs
            func ms(_ n:UInt32) throws -> UInt32? { guard let value=try number(animation,n) else { return nil };guard value >= 0,value*1000 <= Double(UInt32.max) else { throw SlideError.corruptedPackage("Keynote時間範囲不正") };return UInt32((value*1000).rounded()) }
            let automatic=try Self.optionalInteger(animation,6)
            slide.transition=try .init(effect:Self.string(animation,2),effectNamespace:ns,advancesOnClick:automatic.map { $0 == 0 },advanceAfterMilliseconds:ms(5),durationMilliseconds:ms(3))
        }
        var nodes:[TimingNode]=[],targets:[String]=[]
        for field in object.fields where field.number == 2 {
            let build=try self.object(Wire.scalar(field.message(maxFields:options.limits.maxXMLNodes),1));guard build.type == 8 else { throw SlideError.corruptedPackage("Keynote build型不正") }
            let attrs=try fields(Self.bytes(build.fields,4));var values=try properties(attrs,[4:"eventTrigger",9:"rotationAngle",10:"rotationDirection",11:"scaleSize",12:"colorAlpha",13:"acceleration",14:"curveStyle",17:"chartRotation3D",19:"bounce",20:"textDelivery",21:"deliveryOption",23:"decay",24:"repeatCount",25:"actionScale",26:"jiggleIntensity",27:"startOffset",28:"endOffset",29:"motionBlur",30:"includeEndpoints",33:"shine",34:"scaleAmount",35:"travelDistance",36:"cursor",37:"alignToPath"])
            values["objectID"]=String(build.id);values["delivery"]=try Self.string(build.fields,2)
            if build.fields.contains(where:{ $0.number == 1 }) { let id=try ref(build.fields,1);_ = try self.object(id);let target=String(id);values["target"]=target;targets.append(target) }
            if let animation=try child(attrs,18) { values.merge(try properties(animation,[1:"animationType",2:"effect",3:"duration",4:"direction",5:"delay",6:"automatic"])) { _,v in v } }
            var node = TimingNode(name:"build",namespace:ns,attributes:values)
            var native: [String:NativeValue] = ["source":.bytes(build.rawData)]
            if let path = try child(attrs,22) { let geometry = try parameterizedGeometry(path); native["motionPath"] = .object(geometry.properties); native["motionPathKind"] = .string(geometry.kind) }
            if let animation = try child(attrs,18) {
                for number in [UInt32(8),9,10] { if let path = try child(animation,number) { native["timingCurve\(number-7)"] = try .object(parameterizedGeometry(path).properties) } }
                for (number,name) in [(UInt32(11),"randomSeed"),(12,"customDetail"),(13,"curveTheme1"),(14,"curveTheme2"),(15,"curveTheme3"),(16,"rightToLeft")] {
                    if let field = animation.first(where:{ $0.number == number }) {
                        if let n = field.integer { native[name] = .unsigned(n) }
                        else if let n = field.float64 { guard n.isFinite else { throw SlideError.corruptedPackage("Keynote buildの非有限値") }; native[name] = .number(n) }
                        else if let text = field.utf8 { native[name] = .string(text) }
                    }
                }
            }
            node.nativeProperties = native; nodes.append(node)
        }
        for field in object.fields where field.number == 43 || field.number == 3 {
            let id:UInt64?,f:[KeynoteField]
            if field.number == 43 { let object=try self.object(Wire.scalar(field.message(maxFields:options.limits.maxXMLNodes),1));guard object.type == 153 else { throw SlideError.corruptedPackage("Keynote buildChunk型不正") };id=object.id;f=object.fields }
            else { id=nil;f=try field.message(maxFields:options.limits.maxXMLNodes) }
            var attrs=try properties(f,[2:"index",3:"delay",4:"duration",5:"automatic",6:"referent"])
            if let id { attrs["objectID"]=String(id) };if f.contains(where:{ $0.number == 1 }) { let id=try ref(f,1);guard try self.object(id).type == 8 else { throw SlideError.corruptedPackage("Keynote chunkのbuild参照型不正") };attrs["buildID"]=String(id) }
            nodes.append(.init(name:"chunk",namespace:ns,attributes:attrs))
        }
        if !nodes.isEmpty { slide.timing = .init(root:.init(name:"timeline",namespace:ns,children:nodes),targetElementIDs:targets) }
    }
}
