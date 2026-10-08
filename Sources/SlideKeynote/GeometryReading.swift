import Foundation
import SlideCore

extension KeynoteSource {
    // TSD.PathSourceArchive / TSP.Pathの確認済み数値命令だけを共通モデルへ移す。
    // 原本の座標領域を保ち、parameterized pathを近似のプリセットへ置き換えない。
    func nativeGeometry(_ source: [KeynoteField]) throws -> CustomGeometry? {
        let kinds = source.filter { (3...8).contains($0.number) }
        guard kinds.count == 1 else { return nil }
        let bezier: [KeynoteField]
        if let editable = try child(source, 8) {
            var paths: [GeometryPath] = []
            let size = try child(editable,2), width = try size.flatMap { try number($0,1) }, height = try size.flatMap { try number($0,2) }
            guard width.map({ $0 >= 0 }) ?? true, height.map({ $0 >= 0 }) ?? true else { throw SlideError.corruptedPackage("Keynote editable pathの負の寸法") }
            for subpath in editable where subpath.number == 1 {
                try Task.checkCancellation()
                let fields = try subpath.message(maxFields:options.limits.maxXMLNodes)
                let closed = try Wire.scalar(fields,2)
                guard closed <= 1 else { throw SlideError.corruptedPackage("Keynote editable pathのclosed値") }
                let nodes = try fields.filter { $0.number == 1 }.map { field -> (GeometryPoint,GeometryPoint,GeometryPoint) in
                    let fields = try field.message(maxFields:options.limits.maxXMLNodes)
                    func point(_ n: UInt32) throws -> GeometryPoint { guard let p = try child(fields,n), let x = try number(p,1), let y = try number(p,2) else { throw SlideError.corruptedPackage("Keynote editable pathの点欠落") }; return .init(x:String(x),y:String(y)) }
                    return try (point(1),point(2),point(3))
                }
                guard let first = nodes.first else { continue }
                var commands: [PathCommand] = [.move(first.1)]
                for i in nodes.indices.dropFirst() { commands.append(.cubic(control1:nodes[i-1].2,control2:nodes[i].0,end:nodes[i].1)) }
                if closed != 0 { commands.append(.cubic(control1:nodes.last!.2,control2:first.0,end:first.1)); commands.append(.close) }
                paths.append(.init(width:width,height:height,commands:commands))
            }
            return .init(paths:paths)
        }
        if let value = try child(source, 5) { bezier = value }
        else if let connection = try child(source, 7), let value = try child(connection, 1) { bezier = value }
        else { return nil }
        guard let path = try child(bezier, 3) else { return nil }
        var width: Double?, height: Double?
        if let size = try child(bezier, 2) {
            width = try number(size, 1); height = try number(size, 2)
            guard width.map({ $0 >= 0 }) ?? true, height.map({ $0 >= 0 }) ?? true else { throw SlideError.corruptedPackage("Keynoteパスの負の寸法") }
        }
        var commands: [PathCommand] = []
        for field in path where field.number == 1 {
            try Task.checkCancellation()
            let command = try field.message(maxFields: options.limits.maxXMLNodes), kind = try Wire.scalar(command, 1)
            guard (1...5).contains(kind) else { return nil }
            let points = try command.filter { $0.number == 2 }.map { value -> GeometryPoint in
                let fields = try value.message(maxFields: options.limits.maxXMLNodes)
                guard let x = try number(fields, 1), let y = try number(fields, 2) else { throw SlideError.corruptedPackage("Keynoteパスの座標欠落") }
                return .init(x: String(x), y: String(y))
            }
            guard points.count == [1: 1, 2: 1, 3: 2, 4: 3, 5: 0][kind] else { throw SlideError.corruptedPackage("Keynoteパス命令の点数不正") }
            switch kind {
            case 1: commands.append(.move(points[0]))
            case 2: commands.append(.line(points[0]))
            case 3: commands.append(.quadratic(control: points[0], end: points[1]))
            case 4: commands.append(.cubic(control1: points[0], control2: points[1], end: points[2]))
            default: commands.append(.close)
            }
        }
        return .init(paths: [.init(width: width, height: height, commands: commands)])
    }

    func parameterizedGeometry(_ fields: [KeynoteField]) throws -> NativeGeometry {
        let source = fields.reduce(into:Data()) { $0.append($1.rawData) }
        let registry: [String:KeynoteMessageSchema] = [
            "path":.init([1:.init("isFlippedHorizontally",.bool),2:.init("isFlippedVertically",.bool),3:.init("pointPath",.message("pointPath")),4:.init("scalarPath",.message("scalarPath")),6:.init("callout",.message("callout")),9:.init("localizationKey",.string),10:.init("name",.string)]),
            "point":.init([1:.init("x",.float),2:.init("y",.float)]),
            "size":.init([1:.init("width",.float),2:.init("height",.float)]),
            "pointPath":.init([1:.init("type",.uint),2:.init("point",.message("point")),3:.init("naturalSize",.message("size"))]),
            "scalarPath":.init([1:.init("type",.uint),2:.init("scalar",.float),3:.init("naturalSize",.message("size")),4:.init("continuousCurve",.bool)]),
            "callout":.init([1:.init("naturalSize",.message("size")),2:.init("tailPosition",.message("point")),3:.init("tailSize",.float),4:.init("cornerRadius",.float),5:.init("centerTail",.bool)])
        ]
        let properties = try KeynoteSchemaReader.read(source,schema:"path",registry:registry,limits:options.limits)
        var kind = "path"
        if let point = try child(fields,3), let type = try Self.optionalInteger(point,1) { kind = [0:"leftArrow",1:"rightArrow",10:"doubleArrow",100:"star",200:"plus"][type] ?? "point:\(type)" }
        if let scalar = try child(fields,4), let type = try Self.optionalInteger(scalar,1) { kind = [0:"roundedRectangle",1:"regularPolygon",2:"chevron"][type] ?? "scalar:\(type)" }
        if fields.contains(where:{ $0.number == 6 }) { kind = "callout" }
        return .init(dialect:"keynote:TSD.PathSource",kind:kind,properties:properties,source:source)
    }
}
