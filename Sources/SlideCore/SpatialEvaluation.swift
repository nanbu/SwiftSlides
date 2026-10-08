import Foundation

/// 原本の座標領域の列優先3×4 affine行列。
public struct AffineTransform3D: Sendable, Equatable, Codable {
    public let values: [Double]
    public init(_ values: [Double] = [1,0,0,0,1,0,0,0,1,0,0,0]) throws {
        guard values.count == 12, values.allSatisfy(\.isFinite) else { throw SlideError.invalidModel("3D affineの成分数/非有限値") }; self.values = values
    }
    private enum CodingKeys: String, CodingKey { case values }
    public init(from decoder: any Decoder) throws { let c = try decoder.container(keyedBy:CodingKeys.self); try self.init(c.decode([Double].self,forKey:.values)) }
    public func applying(to point: Vector3, direction: Bool = false) -> Vector3 {
        let v = values, t = direction ? 0.0 : 1.0
        return .init(x:v[0]*point.x+v[3]*point.y+v[6]*point.z+v[9]*t,y:v[1]*point.x+v[4]*point.y+v[7]*point.z+v[10]*t,z:v[2]*point.x+v[5]*point.y+v[8]*point.z+v[11]*t)
    }
    public func followed(by next: AffineTransform3D) throws -> AffineTransform3D {
        var output: [Double] = []
        for i in 0..<4 { let p = next.applying(to:.init(x:values[3*i],y:values[3*i+1],z:values[3*i+2]),direction:i<3); output += [p.x,p.y,p.z] }
        return try .init(output)
    }
}
/// 曲面は解析的な軸・断面・押出し/回転指示のまま返す。三角形への近似はしない。
public struct SpatialGeometryEvaluation: Sendable, Equatable {
    public let transform: AffineTransform3D
    public let cubeCorners: [Vector3]?
    public let ellipsoidCenter: Vector3?
    public let ellipsoidAxes: [Vector3]?
    public let profile: VectorPath?
    public let extrusionDepth: Double?
    public let rotationAngle: Double?
}
public struct VectorPath: Sendable, Equatable, Codable {
    public struct Command: Sendable, Equatable, Codable { public let name: String; public let relative: Bool; public let values: [Double] }
    public let commands: [Command]
    public let source: String
    public static func readSVG(_ source: String, maxOperations: Int = 100_000) throws -> Self {
        let text = source as NSString, token = try NSRegularExpression(pattern:#"[MmZzLlHhVvCcSsQqTtAa]|[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?"#)
        var index = 0, count = 0, command: String?, values: [Double] = [], commands: [Command] = []
        let arity = ["M":2,"Z":0,"L":2,"H":1,"V":1,"C":6,"S":4,"Q":4,"T":2,"A":7]
        func flush() throws {
            guard let command else { guard values.isEmpty else { throw SlideError.corruptedPackage("SVGパスの先頭命令") }; return }
            let upper = command.uppercased(), n = arity[upper]!
            guard n == 0 ? values.isEmpty : !values.isEmpty && values.count % n == 0 else { throw SlideError.corruptedPackage("SVGパスの引数数") }
            if upper == "A" { for i in stride(from:0,to:values.count,by:7) { guard values[i] >= 0, values[i+1] >= 0, [0,1].contains(values[i+3]), [0,1].contains(values[i+4]) else { throw SlideError.corruptedPackage("SVG楕円弧の半径/flag") } } }
            commands.append(.init(name:upper,relative:command != upper,values:values)); values = []
        }
        while index < text.length {
            try Task.checkCancellation()
            if [9,10,13,32,44].contains(text.character(at:index)) { index += 1; continue }
            // SVGのarc flagは数値tokenではなく1文字。隣接する01や座標との連結も合法。
            if command?.uppercased() == "A", [3,4].contains(values.count % 7) {
                let flag = text.character(at:index)
                guard flag == 48 || flag == 49 else { throw SlideError.corruptedPackage("SVG楕円弧のflag") }
                count += 1; guard count <= maxOperations else { throw SlideError.limitExceeded("SVGパス予算") }
                values.append(Double(flag - 48)); index += 1; continue
            }
            count += 1; guard count <= maxOperations, let match = token.firstMatch(in:source,options:.anchored,range:NSRange(location:index,length:text.length-index)) else { throw SlideError.corruptedPackage("SVGパスの字句/予算") }
            let value = text.substring(with:match.range); index = NSMaxRange(match.range)
            if arity[value.uppercased()] != nil { try flush(); command = value }
            else { guard let number = Double(value), number.isFinite else { throw SlideError.corruptedPackage("SVGパスの数値") }; values.append(number) }
        }
        try flush()
        guard commands.isEmpty || commands.first?.name == "M" else { throw SlideError.corruptedPackage("SVGパスのmove不在") }
        return .init(commands:commands,source:source)
    }
}
extension SpatialGeometry {
    public func evaluated(parentTransform: AffineTransform3D? = nil) throws -> SpatialGeometryEvaluation {
        let own = try AffineTransform3D(matrix ?? [1,0,0,0,1,0,0,0,1,0,0,0]), transform = try parentTransform.map { try own.followed(by:$0) } ?? own
        var corners: [Vector3]?, center: Vector3?, axes: [Vector3]?
        if kind == .cube {
            guard let low = vectors["min-edge"], let high = vectors["max-edge"], low.x <= high.x, low.y <= high.y, low.z <= high.z else { throw SlideError.invalidModel("cubeの範囲が未指定または逆転") }
            corners = [low.x,high.x].flatMap { x in [low.y,high.y].flatMap { y in [low.z,high.z].map { z in transform.applying(to:.init(x:x,y:y,z:z)) } } }
        } else if kind == .sphere {
            guard let c = vectors["center"], let size = vectors["size"], size.x >= 0, size.y >= 0, size.z >= 0 else { throw SlideError.invalidModel("sphereの中心/寸法が未指定または負") }
            center = transform.applying(to:c)
            axes = [Vector3(x:size.x/2,y:0,z:0),.init(x:0,y:size.y/2,z:0),.init(x:0,y:0,z:size.z/2)].map { transform.applying(to:$0,direction:true) }
        }
        let rawPath = source.attributes["urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0|d"]
        let profile = try rawPath.map { try VectorPath.readSVG($0) }
        for point in (corners ?? []) + (axes ?? []) + (center.map { [$0] } ?? []) {
            guard point.x.isFinite, point.y.isFinite, point.z.isFinite else { throw SlideError.invalidModel("3D幾何の非有限結果") }
        }
        return .init(transform:transform,cubeCorners:corners,ellipsoidCenter:center,ellipsoidAxes:axes,profile:profile,extrusionDepth:values["depth"],rotationAngle:values["end-angle"])
    }
}
