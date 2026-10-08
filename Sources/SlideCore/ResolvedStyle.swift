import Foundation

public struct StyleOrigin: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable { case presentation, master, layout, direct, theme }
    public let kind: Kind
    public let part: String
    public let elementID: String?
    public init(kind: Kind, part: String, elementID: String? = nil) { self.kind=kind;self.part=part;self.elementID=elementID }
}
/// 限定範囲の継承解決。直接モデルと原本は変更しない。
public struct ElementStyleResolution: Sendable {
    public let theme: ThemePart?
    public let element: Element
    public let background: Fill?
    public let colorMap: [String:String]
    public let origins: [String:StyleOrigin]
    public let diagnostics: [SlideDiagnostic]
    public init(element: Element, background: Fill?, colorMap: [String:String], origins: [String:StyleOrigin], diagnostics: [SlideDiagnostic], theme: ThemePart? = nil) { self.theme=theme;self.element=element;self.background=background;self.colorMap=colorMap;self.origins=origins;self.diagnostics=diagnostics }
}
extension TextStyle {
    public func overlaying(_ direct: TextStyle) -> TextStyle {
        var result=self
        if let appearance = direct.appearance { result.appearance = self.appearance?.overlaying(appearance) ?? appearance }
        if let underline = direct.underline, direct.appearance?.underlineStyle == nil, let inherited = result.appearance {
            result.appearance = inherited.overlaying(.init(underlineStyle:underline ? "sng" : "none"))
        }
        if let color = direct.color, direct.appearance?.fill == nil, let inherited = result.appearance, inherited.fill != nil {
            result.appearance = inherited.overlaying(.init(fill:.solid(color)))
        }
        result.font.family=direct.font.family ?? font.family;result.font.size=direct.font.size ?? font.size
        result.font.eastAsianFamily=direct.font.eastAsianFamily ?? font.eastAsianFamily;result.font.complexScriptFamily=direct.font.complexScriptFamily ?? font.complexScriptFamily
        result.font.supplementalFamilies.merge(direct.font.supplementalFamilies) { _,v in v }
        result.bold=direct.bold ?? bold;result.italic=direct.italic ?? italic;result.underline=direct.underline ?? underline;result.color=direct.color ?? color;result.language=direct.language ?? language
        return result
    }
}
