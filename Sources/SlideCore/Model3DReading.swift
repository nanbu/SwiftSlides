import Foundation
import CoreFoundation

/// 3D資源のJSON。未知extensionも型を落とさず保持する。
public indirect enum ModelJSONValue: Sendable, Equatable, Codable {
    case null, boolean(Bool), number(Double), string(String), array([ModelJSONValue]), object([String: ModelJSONValue])
    public subscript(_ key: String) -> ModelJSONValue? { if case .object(let o) = self { o[key] } else { nil } }
    public var array: [ModelJSONValue]? { if case .array(let a) = self { a } else { nil } }
    public var object: [String: ModelJSONValue]? { if case .object(let a) = self { a } else { nil } }
    public var string: String? { if case .string(let a) = self { a } else { nil } }
    public var number: Double? { if case .number(let a) = self { a } else { nil } }
    public var integer: Int? { guard let n = number, n.isFinite, n >= 0, n < Double(Int.max), n.rounded() == n else { return nil }; return Int(n) }
    public var boolean: Bool? { if case .boolean(let a) = self { a } else { nil } }
}
public struct Model3DNode: Sendable, Equatable, Codable {
    public let name: String?
    public let children: [Int]
    public let mesh: Int?
    public let skin: Int?
    public let camera: Int?
    /// glTF列優先4×4。TRSの入力はT*R*Sとして合成。
    public let matrix: [Double]
    public let source: ModelJSONValue
}
public struct Model3DPrimitive: Sendable, Equatable, Codable {
    public let attributes: [String: Int]
    public let indices: Int?
    public let material: Int?
    public let mode: Int
    public let source: ModelJSONValue
}
public struct Model3DMesh: Sendable, Equatable, Codable {
    public let name: String?
    public let primitives: [Model3DPrimitive]
    public let weights: [Double]?
    public let source: ModelJSONValue
}
public struct Model3DAccessor: Sendable, Equatable, Codable {
    public let componentType: Int
    public let count: Int
    public let type: String
    public let normalized: Bool
    public let source: ModelJSONValue
}
/// glTF/GLBの場面graphとmesh。画像・skin・animation・materialの全属性はsourceでも取得できる。
public final class Model3DDocument: Sendable {
    public let nodes: [Model3DNode]
    public let meshes: [Model3DMesh]
    public let accessors: [Model3DAccessor]
    public let scenes: [[Int]]
    public let defaultScene: Int?
    public let source: ModelJSONValue
    public let originalData: Data
    public let unresolvedResources: [String]
    public let requiredExtensions: [String]
    private let buffers: [Data?]
    private let views: [ModelJSONValue]
    private let limits: PackageLimits
    fileprivate init(nodes: [Model3DNode], meshes: [Model3DMesh], accessors: [Model3DAccessor], scenes: [[Int]], defaultScene: Int?, source: ModelJSONValue, originalData: Data, buffers: [Data?], views: [ModelJSONValue], unresolvedResources: [String], requiredExtensions: [String], limits: PackageLimits) {
        self.nodes = nodes; self.meshes = meshes; self.accessors = accessors; self.scenes = scenes; self.defaultScene = defaultScene; self.source = source; self.originalData = originalData; self.buffers = buffers; self.views = views; self.unresolvedResources = unresolvedResources; self.requiredExtensions = requiredExtensions; self.limits = limits
    }
    /// accessorを数値配列へ展開する。正規化整数、stride、matrixの列padding、sparseを解釈する。
    public func values(forAccessor index: Int, maxComponents: Int = 1_000_000) throws -> [[Double]] {
        guard accessors.indices.contains(index) else { throw SlideError.invalidModel("3D accessor index") }
        let accessor = accessors[index], dimensions = ["SCALAR": (1,1), "VEC2": (2,1), "VEC3": (3,1), "VEC4": (4,1), "MAT2": (2,2), "MAT3": (3,3), "MAT4": (4,4)]
        guard let (rows, columns) = dimensions[accessor.type], let size = [5120:1,5121:1,5122:2,5123:2,5125:4,5126:4][accessor.componentType], maxComponents > 0, accessor.count <= maxComponents / (rows * columns) else { throw SlideError.limitExceeded("3D accessor展開予算/type") }
        _ = size
        func read(viewIndex: Int, offset: Int, count: Int, component: Int, normalized: Bool, rows: Int, columns: Int, sparse: Bool = false) throws -> [[Double]] {
            guard views.indices.contains(viewIndex), let buffer = views[viewIndex]["buffer"]?.integer, buffers.indices.contains(buffer), let data = buffers[buffer], let viewLength = views[viewIndex]["byteLength"]?.integer else { throw SlideError.missingPart("3D buffer/view: \(viewIndex)") }
            let view = views[viewIndex], base = view["byteOffset"]?.integer ?? 0
            guard let size = [5120:1,5121:1,5122:2,5123:2,5125:4,5126:4][component] else { throw SlideError.corruptedPackage("3D component type") }
            let colBytes = columns > 1 ? ((rows * size + 3) / 4) * 4 : rows * size, bytes = columns * colBytes
            let stride = sparse ? bytes : view["byteStride"]?.integer ?? bytes
            guard offset >= 0, offset % size == 0, base % size == 0, stride >= bytes, stride % size == 0, base <= data.count, viewLength <= data.count - base, offset <= viewLength, count == 0 || (bytes <= viewLength - offset && count - 1 <= (viewLength - offset - bytes) / stride) else { throw SlideError.corruptedPackage("3D accessor範囲/stride") }
            return try (0..<count).map { element in
                try Task.checkCancellation()
                return try (0..<(rows * columns)).map { c in
                    let start = base + offset + element * stride + (c / rows) * colBytes + (c % rows) * size
                    var bits: UInt32 = 0; for byte in 0..<size { bits |= UInt32(data[start + byte]) << (8 * byte) }
                    let value: Double
                    switch component {
                    case 5120: let n = Double(Int8(bitPattern: UInt8(bits))); value = normalized ? max(-1,n / 127) : n
                    case 5121: value = normalized ? Double(bits) / 255 : Double(bits)
                    case 5122: let n = Double(Int16(bitPattern: UInt16(bits))); value = normalized ? max(-1,n / 32767) : n
                    case 5123: value = normalized ? Double(bits) / 65535 : Double(bits)
                    case 5125: value = Double(bits)
                    default: value = Double(Float(bitPattern: bits))
                    }
                    guard value.isFinite else { throw SlideError.corruptedPackage("3D accessor非有限数") }; return value
                }
            }
        }
        var result = Array(repeating: Array(repeating: 0.0, count: rows * columns), count: accessor.count)
        if let view = accessor.source["bufferView"]?.integer { result = try read(viewIndex: view, offset: accessor.source["byteOffset"]?.integer ?? 0, count: accessor.count, component: accessor.componentType, normalized: accessor.normalized, rows: rows, columns: columns) }
        if let sparse = accessor.source["sparse"] {
            guard let count = sparse["count"]?.integer, count > 0, count <= accessor.count, let indices = sparse["indices"], let values = sparse["values"], let iView = indices["bufferView"]?.integer, let iType = indices["componentType"]?.integer, [5121,5123,5125].contains(iType), let vView = values["bufferView"]?.integer else { throw SlideError.corruptedPackage("3D sparse構造") }
            func offset(_ node: ModelJSONValue) throws -> Int { guard let value = node["byteOffset"] else { return 0 }; guard let n = value.integer else { throw SlideError.corruptedPackage("3D sparse offset") }; return n }
            let positions = try read(viewIndex:iView,offset:offset(indices),count:count,component:iType,normalized:false,rows:1,columns:1,sparse:true)
            let replacement = try read(viewIndex:vView,offset:offset(values),count:count,component:accessor.componentType,normalized:accessor.normalized,rows:rows,columns:columns,sparse:true)
            var previous = -1
            for i in 0..<count { let position = positions[i][0]; guard position < Double(accessor.count), Int(position) > previous else { throw SlideError.corruptedPackage("3D sparse index順序/範囲") }; previous = Int(position); result[previous] = replacement[i] }
        }
        return result
    }
}
public enum Model3DReader {
    /// 外部bufferは呼出側から供給する。ネットワークや相対fileを暗黙に開かない。
    public static func read(_ input: Data, limits: PackageLimits = .init(), resourceProvider: (@Sendable (String) throws -> Data?)? = nil) throws -> Model3DDocument {
        let data = input.startIndex == 0 ? input : Data(input)
        guard data.count <= limits.maxPartBytes, limits.maxXMLDepth > 0, limits.maxXMLNodes > 0 else { throw SlideError.limitExceeded("3D資源入力予算") }
        var json = data, binary: Data?
        if data.starts(with: [0x67,0x6c,0x54,0x46]) {
            func u32(_ offset: Int) throws -> Int { guard offset >= 0, offset + 4 <= data.count else { throw SlideError.corruptedPackage("GLB切断") }; return (0..<4).reduce(0) { $0 | Int(data[offset + $1]) << (8 * $1) } }
            guard try u32(4) == 2, try u32(8) == data.count else { throw SlideError.corruptedPackage("GLB版/宣言長") }
            var offset = 12, chunks = 0
            while offset < data.count {
                let size = try u32(offset), type = try u32(offset + 4); offset += 8
                guard size % 4 == 0, size <= data.count - offset else { throw SlideError.corruptedPackage("GLB chunk長") }
                if chunks == 0 { guard type == 0x4e4f534a else { throw SlideError.corruptedPackage("GLB先頭JSON不在") }; json = data.subdata(in:offset..<offset+size) }
                else if type == 0x004e4942 { guard binary == nil, chunks == 1 else { throw SlideError.corruptedPackage("GLB BIN位置/重複") }; binary = data.subdata(in:offset..<offset+size) }
                else if type == 0x4e4f534a { throw SlideError.corruptedPackage("GLB JSON重複") }
                offset += size; chunks += 1
            }
            guard chunks > 0 else { throw SlideError.corruptedPackage("空GLB") }
        }
        let decoded = try JSONSerialization.jsonObject(with: json); var remaining = limits.maxXMLNodes
        func value(_ any: Any, depth: Int) throws -> ModelJSONValue {
            try Task.checkCancellation(); remaining -= 1; guard remaining >= 0, depth < limits.maxXMLDepth else { throw SlideError.limitExceeded("3D JSON予算") }
            if any is NSNull { return .null }
            if let n = any as? NSNumber { if CFGetTypeID(n) == CFBooleanGetTypeID() { return .boolean(n.boolValue) }; guard n.doubleValue.isFinite else { throw SlideError.corruptedPackage("3D JSON非有限数") }; return .number(n.doubleValue) }
            if let s = any as? String { return .string(s) }
            if let a = any as? [Any] { return try .array(a.map { try value($0,depth:depth+1) }) }
            if let o = any as? [String:Any] { return try .object(o.mapValues { try value($0,depth:depth+1) }) }
            throw SlideError.corruptedPackage("3D JSON値")
        }
        let root = try value(decoded,depth:0)
        guard root["asset"]?["version"]?.string == "2.0" else { throw SlideError.unsupportedContainer("glTF 2.0以外の3D資源") }
        func array(_ name: String) throws -> [ModelJSONValue] { guard let v = root[name] else { return [] }; guard let a = v.array else { throw SlideError.corruptedPackage("glTF配列: \(name)") }; return a }
        for name in ["accessors","animations","buffers","bufferViews","cameras","images","materials","meshes","nodes","samplers","scenes","skins","textures"] {
            guard try array(name).allSatisfy({ $0.object != nil && ($0["name"] == nil || $0["name"]?.string != nil) }) else { throw SlideError.corruptedPackage("glTF object/name型: \(name)") }
        }
        func integer(_ v: ModelJSONValue?, _ context: String) throws -> Int { guard let i = v?.integer else { throw SlideError.corruptedPackage("glTF整数: \(context)") }; return i }
        func numbers(_ value: ModelJSONValue?, count: Int? = nil) throws -> [Double]? { guard let value else { return nil }; guard let array = value.array, count == nil || array.count == count else { throw SlideError.corruptedPackage("glTF成分数") }; return try array.map { guard let n = $0.number, n.isFinite else { throw SlideError.corruptedPackage("glTF数値") }; return n } }
        var buffers: [Data?] = [], bufferSizes: [Int] = [], unresolved: [String] = [], total = 0
        for (index, item) in try array("buffers").enumerated() {
            let size = try integer(item["byteLength"],"buffer length"); guard size > 0, size <= limits.maxPartBytes, size <= limits.maxExpandedBytes - total else { throw SlideError.limitExceeded("glTF buffer予算") }; total += size; bufferSizes.append(size)
            guard item["uri"] == nil || item["uri"]?.string != nil else { throw SlideError.corruptedPackage("glTF buffer URI型") }
            let bytes: Data?
            if let uri = item["uri"]?.string {
                if uri.hasPrefix("data:") { guard let comma = uri.firstIndex(of:","), uri[..<comma].hasSuffix(";base64"), let decoded = Data(base64Encoded:String(uri[uri.index(after:comma)...])) else { throw SlideError.corruptedPackage("glTF data URI") }; bytes = decoded }
                else { bytes = try resourceProvider?(uri); if bytes == nil { unresolved.append(uri) } }
            } else { guard index == 0, binary != nil else { throw SlideError.missingPart("glTF buffer URI/BIN") }; bytes = binary }
            if let bytes { guard bytes.count >= size, bytes.count <= limits.maxPartBytes, item["uri"] != nil || bytes.count <= size + 3 else { throw SlideError.corruptedPackage("glTF buffer宣言長") }; buffers.append(Data(bytes.prefix(size))) } else { buffers.append(nil) }
        }
        let views = try array("bufferViews")
        for view in views { let buffer = try integer(view["buffer"],"view buffer"), size = try integer(view["byteLength"],"view length"), offset = try view["byteOffset"].map { try integer($0,"view offset") } ?? 0
            guard buffers.indices.contains(buffer), size > 0, offset <= bufferSizes[buffer], size <= bufferSizes[buffer] - offset else { throw SlideError.corruptedPackage("glTF bufferView") }
            if let bytes = buffers[buffer] { guard offset <= bytes.count, size <= bytes.count - offset else { throw SlideError.corruptedPackage("glTF bufferView範囲") } }
            if let stride = view["byteStride"] { let n = try integer(stride,"stride"); guard (4...252).contains(n), n % 4 == 0 else { throw SlideError.corruptedPackage("glTF stride") } }
        }
        let accessors = try array("accessors").map { item -> Model3DAccessor in
            let component = try integer(item["componentType"],"component"), count = try integer(item["count"],"accessor count")
            guard [5120,5121,5122,5123,5125,5126].contains(component), count > 0, let type = item["type"]?.string, ["SCALAR","VEC2","VEC3","VEC4","MAT2","MAT3","MAT4"].contains(type) else { throw SlideError.corruptedPackage("glTF accessor") }
            if let view = item["bufferView"] { guard views.indices.contains(try integer(view,"accessor view")) else { throw SlideError.corruptedPackage("glTF accessor view") } }
            if let offset = item["byteOffset"] { _ = try integer(offset,"accessor offset") }
            guard item["normalized"] == nil || item["normalized"]?.boolean != nil, item["normalized"]?.boolean != true || [5120,5121,5122,5123].contains(component) else { throw SlideError.corruptedPackage("glTF accessor normalized") }
            return .init(componentType:component,count:count,type:type,normalized:item["normalized"]?.boolean ?? false,source:item)
        }
        let materials = try array("materials")
        let meshes = try array("meshes").map { item -> Model3DMesh in
            guard let rawPrimitives = item["primitives"]?.array, !rawPrimitives.isEmpty else { throw SlideError.corruptedPackage("glTF primitives") }
            let primitives = try rawPrimitives.map { p -> Model3DPrimitive in
                guard let rawAttributes = p["attributes"]?.object else { throw SlideError.corruptedPackage("glTF attributes") }
                let attrs = try rawAttributes.mapValues { v -> Int in let i = try integer(v,"attribute"); guard accessors.indices.contains(i) else { throw SlideError.corruptedPackage("glTF attribute参照") }; return i }
                let indices = try p["indices"].map { try integer($0,"indices") }, material = try p["material"].map { try integer($0,"material") }, mode = try p["mode"].map { try integer($0,"mode") } ?? 4
                guard (0...6).contains(mode), indices.map({ accessors.indices.contains($0) }) ?? true, material.map({ materials.indices.contains($0) }) ?? true else { throw SlideError.corruptedPackage("glTF primitive参照/mode") }
                if let indices { guard accessors[indices].type == "SCALAR", [5121,5123,5125].contains(accessors[indices].componentType) else { throw SlideError.corruptedPackage("glTF indices型") } }
                return .init(attributes:attrs,indices:indices,material:material,mode:mode,source:p)
            }
            return try .init(name:item["name"]?.string,primitives:primitives,weights:numbers(item["weights"]),source:item)
        }
        let rawNodes = try array("nodes"), skins = try array("skins"), cameras = try array("cameras")
        let nodes = try rawNodes.map { item -> Model3DNode in
            guard item["children"] == nil || item["children"]?.array != nil else { throw SlideError.corruptedPackage("glTF children型") }
            let children = try (item["children"]?.array ?? []).map { try integer($0,"child") }, mesh = try item["mesh"].map { try integer($0,"mesh") }, skin = try item["skin"].map { try integer($0,"skin") }, camera = try item["camera"].map { try integer($0,"camera") }
            guard Set(children).count == children.count, children.allSatisfy(rawNodes.indices.contains), mesh.map(meshes.indices.contains) ?? true, skin.map(skins.indices.contains) ?? true, camera.map(cameras.indices.contains) ?? true else { throw SlideError.corruptedPackage("glTF node参照") }
            let matrix: [Double]
            if let explicit = try numbers(item["matrix"],count:16) { guard item["translation"] == nil, item["rotation"] == nil, item["scale"] == nil else { throw SlideError.corruptedPackage("glTF matrix/TRS併記") }; matrix = explicit }
            else {
                let t = try numbers(item["translation"],count:3) ?? [0,0,0], q = try numbers(item["rotation"],count:4) ?? [0,0,0,1], s = try numbers(item["scale"],count:3) ?? [1,1,1]
                guard abs(q.reduce(0) { $0 + $1 * $1 } - 1) < 1e-4 else { throw SlideError.corruptedPackage("glTF quaternion正規化") }
                let x=q[0],y=q[1],z=q[2],w=q[3]
                matrix = [(1-2*y*y-2*z*z)*s[0],(2*x*y+2*z*w)*s[0],(2*x*z-2*y*w)*s[0],0,(2*x*y-2*z*w)*s[1],(1-2*x*x-2*z*z)*s[1],(2*y*z+2*x*w)*s[1],0,(2*x*z+2*y*w)*s[2],(2*y*z-2*x*w)*s[2],(1-2*x*x-2*y*y)*s[2],0,t[0],t[1],t[2],1]
            }
            guard matrix.allSatisfy(\.isFinite) else { throw SlideError.corruptedPackage("glTF transform非有限") }
            return .init(name:item["name"]?.string,children:children,mesh:mesh,skin:skin,camera:camera,matrix:matrix,source:item)
        }
        var visited = Set<Int>(), active = Set<Int>(), parents: [Int:Int] = [:]
        for (i,node) in nodes.enumerated() { for child in node.children { guard parents.updateValue(i,forKey:child) == nil else { throw SlideError.corruptedPackage("glTF node複数parent") } } }
        func walk(_ index: Int, _ depth: Int) throws { guard depth < limits.maxXMLDepth, !active.contains(index) else { throw SlideError.corruptedPackage("glTF node循環/深さ") }; if visited.contains(index) { return }; active.insert(index); for child in nodes[index].children { try walk(child,depth+1) }; active.remove(index); visited.insert(index) }
        for index in nodes.indices { try walk(index,0) }
        let scenes = try array("scenes").map { scene -> [Int] in
            guard scene["nodes"] == nil || scene["nodes"]?.array != nil else { throw SlideError.corruptedPackage("glTF scene nodes型") }
            let roots = try (scene["nodes"]?.array ?? []).map { v -> Int in let i = try integer(v,"scene node"); guard nodes.indices.contains(i), parents[i] == nil else { throw SlideError.corruptedPackage("glTF scene root") }; return i }
            guard Set(roots).count == roots.count else { throw SlideError.corruptedPackage("glTF scene root重複") }; return roots
        }
        let defaultScene = try root["scene"].map { try integer($0,"scene") }; guard defaultScene.map(scenes.indices.contains) ?? true else { throw SlideError.corruptedPackage("glTF default scene") }
        let required = try array("extensionsRequired").map { v -> String in guard let s = v.string else { throw SlideError.corruptedPackage("glTF extension name") }; return s }
        let result = Model3DDocument(nodes:nodes,meshes:meshes,accessors:accessors,scenes:scenes,defaultScene:defaultScene,source:root,originalData:data,buffers:buffers,views:views,unresolvedResources:unresolved,requiredExtensions:required,limits:limits)
        _ = try result.materials; _ = try result.skins; _ = try result.animations
        return result
    }
}
