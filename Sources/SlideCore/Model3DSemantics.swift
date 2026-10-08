import Foundation

public struct Model3DMaterial: Sendable, Equatable {
    public let name: String?
    public let baseColor: [Double]
    public let metallic: Double
    public let roughness: Double
    public let emissive: [Double]
    public let alphaMode: String
    public let alphaCutoff: Double
    public let doubleSided: Bool
    public let textures: [String:Int]
    public let source: ModelJSONValue
}
public struct Model3DSkin: Sendable, Equatable {
    public let joints: [Int]
    public let skeleton: Int?
    public let inverseBindMatrices: Int?
    public let source: ModelJSONValue
}
public struct Model3DAnimation: Sendable, Equatable {
    public struct Sampler: Sendable, Equatable { public let input: Int; public let output: Int; public let interpolation: String }
    public struct Channel: Sendable, Equatable { public let sampler: Int; public let node: Int?; public let path: String }
    public let name: String?
    public let samplers: [Sampler]
    public let channels: [Channel]
    public let source: ModelJSONValue
}
extension Model3DDocument {
    /// PBR係数とtexture index。texture transformなどのextensionはsourceに残す。
    public var materials: [Model3DMaterial] { get throws {
        let textures = source["textures"]?.array ?? []
        return try (source["materials"]?.array ?? []).map { item in
            let pbr = item["pbrMetallicRoughness"]
            guard pbr == nil || pbr?.object != nil, item["alphaMode"] == nil || item["alphaMode"]?.string != nil else { throw SlideError.corruptedPackage("glTF material型") }
            func scalar(_ v: ModelJSONValue?, _ fallback: Double, unit: Bool = true) throws -> Double {
                guard let v else { return fallback }; guard let number = v.number, number.isFinite, !unit || (0...1).contains(number) else { throw SlideError.corruptedPackage("glTF material係数") }; return number
            }
            func vector(_ v: ModelJSONValue?, _ fallback: [Double]) throws -> [Double] { guard let v else { return fallback }; guard let values = v.array, values.count == fallback.count else { throw SlideError.corruptedPackage("glTF material成分数") }; return try values.map { try scalar($0,0) } }
            var indices: [String:Int] = [:]
            for (name,value) in [("baseColor",pbr?["baseColorTexture"]),("metallicRoughness",pbr?["metallicRoughnessTexture"]),("normal",item["normalTexture"]),("occlusion",item["occlusionTexture"]),("emissive",item["emissiveTexture"])] {
                if let value { guard let index = value["index"]?.integer, textures.indices.contains(index) else { throw SlideError.corruptedPackage("glTF material texture参照") }; indices[name] = index }
            }
            let mode = item["alphaMode"]?.string ?? "OPAQUE"
            guard ["OPAQUE","MASK","BLEND"].contains(mode), item["doubleSided"] == nil || item["doubleSided"]?.boolean != nil else { throw SlideError.corruptedPackage("glTF material mode") }
            return try .init(name:item["name"]?.string,baseColor:vector(pbr?["baseColorFactor"],[1,1,1,1]),metallic:scalar(pbr?["metallicFactor"],1),roughness:scalar(pbr?["roughnessFactor"],1),emissive:vector(item["emissiveFactor"],[0,0,0]),alphaMode:mode,alphaCutoff:scalar(item["alphaCutoff"],0.5,unit:false),doubleSided:item["doubleSided"]?.boolean ?? false,textures:indices,source:item)
        }
    } }
    public var skins: [Model3DSkin] { get throws {
        try (source["skins"]?.array ?? []).map { item in
            guard let raw = item["joints"]?.array, !raw.isEmpty else { throw SlideError.corruptedPackage("glTF skin joints") }
            let joints = try raw.map { v -> Int in guard let i = v.integer, nodes.indices.contains(i) else { throw SlideError.corruptedPackage("glTF skin joint参照") }; return i }
            guard Set(joints).count == joints.count else { throw SlideError.corruptedPackage("glTF skin joint重複") }
            func optional(_ name: String) throws -> Int? { guard let v = item[name] else { return nil }; guard let i = v.integer else { throw SlideError.corruptedPackage("glTF skin整数") }; return i }
            let skeleton = try optional("skeleton"), matrices = try optional("inverseBindMatrices")
            guard skeleton.map(nodes.indices.contains) ?? true else { throw SlideError.corruptedPackage("glTF skeleton参照") }
            if let matrices { guard accessors.indices.contains(matrices), accessors[matrices].type == "MAT4", accessors[matrices].componentType == 5126, accessors[matrices].count >= joints.count else { throw SlideError.corruptedPackage("glTF skin matrix参照/type") } }
            return .init(joints:joints,skeleton:skeleton,inverseBindMatrices:matrices,source:item)
        }
    } }
    /// 時間値/補間/targetを保持する。実際のアニメーション再生は行わない。
    public var animations: [Model3DAnimation] { get throws {
        try (source["animations"]?.array ?? []).map { item in
            guard let rawSamplers = item["samplers"]?.array, !rawSamplers.isEmpty, let rawChannels = item["channels"]?.array, !rawChannels.isEmpty else { throw SlideError.corruptedPackage("glTF animation構造") }
            let samplers = try rawSamplers.map { s -> Model3DAnimation.Sampler in
                guard let input = s["input"]?.integer, let output = s["output"]?.integer, accessors.indices.contains(input), accessors.indices.contains(output), accessors[input].componentType == 5126, accessors[input].type == "SCALAR" else { throw SlideError.corruptedPackage("glTF animation accessor") }
                let interpolation = s["interpolation"]?.string ?? "LINEAR"
                guard s["interpolation"] == nil || s["interpolation"]?.string != nil else { throw SlideError.corruptedPackage("glTF interpolation型") }
                guard ["LINEAR","STEP","CUBICSPLINE"].contains(interpolation) else { throw SlideError.unsupportedContainer("glTF interpolation") }
                return .init(input:input,output:output,interpolation:interpolation)
            }
            let channels = try rawChannels.map { c -> Model3DAnimation.Channel in
                guard let sampler = c["sampler"]?.integer, samplers.indices.contains(sampler), let target = c["target"], let path = target["path"]?.string else { throw SlideError.corruptedPackage("glTF animation channel") }
                let node: Int?
                if let value = target["node"] { guard let i = value.integer, nodes.indices.contains(i) else { throw SlideError.corruptedPackage("glTF animation node") }; node = i } else { node = nil }
                guard ["translation","rotation","scale","weights","pointer"].contains(path) else { throw SlideError.unsupportedContainer("glTF animation path") }
                let input = accessors[samplers[sampler].input], output = accessors[samplers[sampler].output]
                if path != "weights", path != "pointer" {
                    guard output.type == (path == "rotation" ? "VEC4" : "VEC3"), output.componentType == 5126, input.count <= Int.max / 3, output.count == input.count * (samplers[sampler].interpolation == "CUBICSPLINE" ? 3 : 1) else { throw SlideError.corruptedPackage("glTF animation成分数/type") }
                }
                return .init(sampler:sampler,node:node,path:path)
            }
            return .init(name:item["name"]?.string,samplers:samplers,channels:channels,source:item)
        }
    } }
    public var warnings: [SlideWarning] {
        unresolvedResources.map { .init(code:.unsupportedContent,part:$0,element:"buffer",message:"3D外部資源が未供給です") }
        + requiredExtensions.map { .init(code:.unsupportedContent,part:"model",element:$0,message:"glTF必須extensionの意味は原本に保持します。標準属性の解釈と区別してください") }
    }
}
