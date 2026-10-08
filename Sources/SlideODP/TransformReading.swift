import Foundation
import SlideCore

public enum ODPTransformReader {
    /// dr3d:transform。ODF 1.2–1.4の角度規定は度（draw:transformと異なる）。
    public static func read3D(_ raw: String, maxOperations: Int = 10_000) throws -> AffineTransform3D {
        let text = raw as NSString, regex = try NSRegularExpression(pattern:#"([A-Za-z]+)\s*\(([^()]*)\)"#)
        var index = 0, count = 0, result = try AffineTransform3D()
        while index < text.length {
            try Task.checkCancellation()
            if [9,10,13,32].contains(text.character(at:index)) { index += 1; continue }
            count += 1; guard count <= maxOperations, let match = regex.firstMatch(in:raw,options:.anchored,range:NSRange(location:index,length:text.length-index)) else { throw SlideError.corruptedPackage("ODP 3D変形の字句/予算") }
            let name = text.substring(with:match.range(at:1)), args = try text.substring(with:match.range(at:2)).split(whereSeparator:{ $0.isWhitespace || $0 == "," }).map { value -> Double in guard let n = Double(value), n.isFinite else { throw SlideError.corruptedPackage("ODP 3D変形の数値") }; return n }
            var matrix = [1.0,0,0,0,1,0,0,0,1,0,0,0]
            switch name {
            case "matrix": guard args.count == 12 else { throw SlideError.corruptedPackage("ODP 3D matrix成分数") }; matrix = args
            case "scale": guard args.count == 3 else { throw SlideError.corruptedPackage("ODP 3D scale成分数") }; matrix[0] = args[0]; matrix[4] = args[1]; matrix[8] = args[2]
            case "translate": guard args.count == 3 else { throw SlideError.corruptedPackage("ODP 3D translate成分数") }; matrix.replaceSubrange(9...11,with:args)
            case "rotatex","rotatey","rotatez":
                guard args.count == 1 else { throw SlideError.corruptedPackage("ODP 3D rotate成分数") }
                let c = cos(args[0] * .pi / 180), s = sin(args[0] * .pi / 180)
                if name == "rotatex" { matrix[4]=c; matrix[5]=s; matrix[7] = -s; matrix[8]=c }
                else if name == "rotatey" { matrix[0]=c; matrix[2] = -s; matrix[6]=s; matrix[8]=c }
                else { matrix[0]=c; matrix[1]=s; matrix[3] = -s; matrix[4]=c }
            default: throw SlideError.unsupportedContainer("ODP 3D変形: \(name)")
            }
            result = try result.followed(by:AffineTransform3D(matrix)); index = NSMaxRange(match.range)
        }
        return result
    }
    /// 変換を原本の記載順に適用する。角度は明示された単位で解釈し、operationsにはradianを返す。
    public static func read(_ raw: String, angleUnit: ODFTransformAngleUnit = .radians, maxOperations: Int = 10_000) throws -> DrawingTransform {
        let text = raw as NSString, regex = try NSRegularExpression(pattern: #"([A-Za-z]+)\s*\(([^()]*)\)"#)
        var cursor = 0, operations: [TransformOperation] = [], matrix = AffineTransform2D.identity
        func scalar(_ s: String) throws -> Double { guard let n = Double(s), n.isFinite else { throw SlideError.corruptedPackage("ODP transform数値") }; return n }
        func angle(_ s: String) throws -> Double {
            if s.hasSuffix("deg") { return try scalar(String(s.dropLast(3))) * .pi / 180 }
            if s.hasSuffix("grad") { return try scalar(String(s.dropLast(4))) * .pi / 200 }
            if s.hasSuffix("rad") { return try scalar(String(s.dropLast(3))) }
            return try scalar(s) * (angleUnit == .degrees ? .pi / 180 : 1)
        }
        while cursor < text.length {
            try Task.checkCancellation()
            if [9, 10, 13, 32, 44].contains(text.character(at: cursor)) { cursor += 1; continue }
            guard operations.count < maxOperations else { throw SlideError.limitExceeded("ODP transform予算") }
            guard let match = regex.firstMatch(in: raw, options: .anchored, range: NSRange(location: cursor, length: text.length - cursor)) else { throw SlideError.corruptedPackage("ODP transform字句") }
            let name = text.substring(with: match.range(at: 1)), args = text.substring(with: match.range(at: 2)).split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
            let values: [Double], next: AffineTransform2D
            switch name {
            case "matrix":
                guard args.count == 6 else { throw SlideError.corruptedPackage("ODP matrix引数数") }
                values = try args.enumerated().map { index, raw in try index < 4 ? scalar(raw) : (Double(raw).flatMap { $0.isFinite ? $0 : nil } ?? ODF.length(raw)) }
                next = .init(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
            case "translate": guard (1...2).contains(args.count) else { throw SlideError.corruptedPackage("ODP translate引数数") }; values = try args.map(ODF.length); next = .init(tx: values[0], ty: values.count == 2 ? values[1] : 0)
            case "scale": guard (1...2).contains(args.count) else { throw SlideError.corruptedPackage("ODP scale引数数") }; values = try args.map(scalar); next = .init(a: values[0], d: values.count == 2 ? values[1] : values[0])
            case "rotate", "skewX", "skewY":
                guard args.count == 1 else { throw SlideError.corruptedPackage("ODP angle引数数") }; values = try [angle(args[0])]; let a = values[0]
                if name == "rotate" { next = .init(a: cos(a), b: sin(a), c: -sin(a), d: cos(a)) }
                else if name == "skewX" { next = .init(c: tan(a)) } else { next = .init(b: tan(a)) }
            default: throw SlideError.unsupportedContainer("ODP transform: \(name)")
            }
            matrix = matrix.followed(by: next)
            guard next.isFinite, matrix.isFinite else { throw SlideError.corruptedPackage("ODP transform非有限結果") }
            operations.append(.init(name: name, arguments: values, matrix: next)); cursor = NSMaxRange(match.range)
        }
        return .init(rawValue: raw, operations: operations, matrix: matrix)
    }
}
extension ODPPageParser {
    func textPath(_ node: MarkupNode) throws -> TextPathProperties? {
        guard node.attributes.keys.contains(where: { $0.hasPrefix(ODF.key(ODF.draw, "text-path")) || $0 == ODF.key(ODF.draw, "text-rotate-angle") }) else { return nil }
        func flag(_ name: String) throws -> Bool? { guard let raw = node.odf(ODF.draw, name) else { return nil }; guard ["true", "false", "1", "0"].contains(raw) else { throw SlideError.corruptedPackage("ODP text-path真偽値") }; return raw == "true" || raw == "1" }
        let rotation = try node.odf(ODF.draw, "text-rotate-angle").map { raw -> Double in guard let n = Double(raw), n.isFinite else { throw SlideError.corruptedPackage("ODP text-path角度") }; return n }
        return try .init(enabled: flag("text-path"), mode: node.odf(ODF.draw, "text-path-mode"), scale: node.odf(ODF.draw, "text-path-scale"), sameLetterHeights: flag("text-path-same-letter-heights"), rotateAngle: rotation, source: SourceXMLNode(node))
    }
}
