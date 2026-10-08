import Foundation
import SlideCore

extension Presentation {
    /// placeholderの位置・塗り・段落/文字既定の継承を、出典つきで読む。
    public func resolveElement(slideID: String, elementID: String) throws -> ElementStyleResolution {
        try Task.checkCancellation()
        let slides=slides.filter { $0.id == slideID }
        guard slides.count == 1 else { throw SlideError.slideNotFound(id:slideID) }
        let slide=slides[0]
        func all(_ elements:[Element]) -> [Element] { elements.flatMap { [$0]+all($0.children) } }
        let matches=all(slide.elements).filter { $0.id == elementID }
        guard matches.count == 1 else { throw SlideError.elementNotFound(id:elementID) }
        let direct=matches[0],reader=try sourcePartReader()
        let layout=try slide.layoutPath.map { try reader.layout(at:$0) },master=try layout?.masterPath.map { try reader.master(at:$0) }
        var issues:[SlideDiagnostic]=[],origins:[String:StyleOrigin]=[:]
        let slidePart=storage?.slidePaths[slideID] ?? ""
        func issue(_ message:String) { issues.append(.init(code:"styleUnresolved",feature:"STY-003",stage:.read,action:.unresolved,location:.init(part:slidePart,sourceElement:"ph",slideID:slideID,elementID:elementID),message:message)) }
        func unique(_ values:[Element],stage:String) -> Element? { if values.count > 1 { issue("\(stage)のplaceholder照合があいまいです");return nil };return values.first }
        let lp:Element?
        if let ph=direct.placeholder { lp=unique(all(layout?.elements ?? []).filter { $0.placeholder != nil && ($0.placeholder?.index ?? 0) == (ph.index ?? 0) },stage:"layout") }
        else { lp=nil }
        func normalized(_ kind:String?) -> String { kind == "ctrTitle" ? "title" : kind ?? "obj" }
        let mp:Element?
        if let ph=lp?.placeholder ?? direct.placeholder { mp=unique(all(master?.elements ?? []).filter { normalized($0.placeholder?.kind) == normalized(ph.kind) && $0.placeholder != nil },stage:"master") }
        else { mp=nil }
        if direct.placeholder != nil && lp == nil { issue("layoutのplaceholderが未解決です") }
        var theme:ThemePart?,themeElements:MarkupNode?
        if let path=master?.themePath {
            let root=try reader.tree(path);themeElements=root.child("themeElements")
            theme=try reader.themes().first { $0.path == path }
        }
        for path in [layout?.themeOverridePath,slide.themeOverridePath].compactMap({ $0 }) {
            let root=try reader.tree(path)
            if let override=try reader.themes().first(where:{ $0.path == path }), var merged=theme {
                merged.colors.merge(override.colors) { _,v in v }
                if root.child("fontScheme") != nil { merged.titleFont=override.titleFont;merged.bodyFont=override.bodyFont }
                if root.child("fmtScheme") != nil { merged.effectStyles=override.effectStyles }
                theme=merged
            }
            if let base=themeElements {
                for child in root.children { if let i=base.content.firstIndex(where:{ if case .node(let n) = $0 { n.name == child.name && n.isA } else { false } }) { base.content[i] = .node(child) } else { base.content.append(.node(child)) } }
            }
        }
        func recolor(_ color:Color,_ placeholder:Color?) -> Color {
            guard let placeholder else { return color }
            let value:ColorValue
            switch color { case .theme("phClr"): return placeholder;case .value(let v): value=v;default:return color }
            guard case .scheme("phClr") = value.base else { return color }
            switch placeholder {
            case .rgb(let rgb): return .value(.init(base:.sRGB(rgb),transforms:value.transforms))
            case .theme(let name): return .value(.init(base:.scheme(name),transforms:value.transforms))
            case .value(var v): v.transforms += value.transforms;return .value(v)
            }
        }
        func recolor(_ fill:Fill,_ placeholder:Color?) -> Fill {
            switch fill {
            case .solid(let c): return .solid(recolor(c,placeholder))
            case .gradient(var g): for i in g.stops.indices { g.stops[i].color=recolor(g.stops[i].color,placeholder) };return .gradient(g)
            case .pattern(var p): p.foreground=p.foreground.map { recolor($0,placeholder) };p.background=p.background.map { recolor($0,placeholder) };return .pattern(p)
            default:return fill
            }
        }
        func recolor(_ effect: DrawingEffect, _ placeholder: Color?) -> DrawingEffect {
            .init(kind: effect.kind, values: effect.values, attributes: effect.attributes, colors: effect.colors.map { recolor($0, placeholder) }, fill: effect.fill.map { recolor($0, placeholder) }, children: effect.children.map { recolor($0, placeholder) }, source: effect.source)
        }
        func matrix(_ kind:String,_ index:Int?) -> MarkupNode? {
            guard let index else { issue("theme styleのindexがありません");return nil }
            if index == 0 { return nil }
            let list=themeElements?.child("fmtScheme")?.child(index >= 1001 && kind == "fillStyleLst" ? "bgFillStyleLst" : kind)
            let offset=index >= 1001 && kind == "fillStyleLst" ? index-1001 : index-1
            guard let list,list.children.indices.contains(offset) else { issue("theme styleのindexが範囲外です: \(index)");return nil }
            return list.children[offset]
        }
        func style(_ e:Element) throws -> MarkupNode? {
            func node(_ source:SourceXMLNode) throws -> MarkupNode {
                try Task.checkCancellation()
                let result=MarkupNode(name:source.name,namespace:source.namespace,qualifiedName:source.qualifiedName,attributes:source.attributes,attributeNames:source.attributeNames,namespaces:source.namespaceBindings)
                result.content=try source.content.map { switch $0 { case .text(let s): .text(s);case .element(let n): .node(try node(n)) } };return result
            }
            guard let source=e.sourceProperties?.children.first(where:{ $0.name == "style" && [NS.p,NS.strictP].contains($0.namespace) }) else { return nil }
            return try node(source)
        }
        func styleFill(_ ref:StyleReference) throws -> Fill? {
            if ref.index == 0 { return Fill.none }
            guard let node=matrix("fillStyleLst",ref.index) else { return nil }
            let parent=MarkupNode(name:"spPr",namespace:NS.a,qualifiedName:"a:spPr");parent.content=[.node(node)]
            return try reader.fill(parent,part:theme?.path ?? "").map { recolor($0,ref.color) }
        }
        var result=direct
        var inheritedScene: Scene3D?, inheritedShape: Shape3D?
        let layers:[(Element?,StyleOrigin)]=[(mp,.init(kind:.master,part:master?.path ?? "",elementID:mp?.id)),(lp,.init(kind:.layout,part:layout?.path ?? "",elementID:lp?.id)),(direct,.init(kind:.direct,part:slidePart,elementID:direct.id))]
        var frame:Rect?,fill:Fill?,stroke:Stroke?,geometry:ShapeGeometry?,custom:CustomGeometry?
        var rotation=0.0,flipH=false,flipV=false,childFrame:Rect?,resolvedEffects:ElementEffects?
        for (element,origin) in layers {
            guard let element else { continue }
            let effectStyleNode = element.effects?.reference.flatMap { matrix("effectStyleLst", $0.index) }
            if let node = effectStyleNode {
                inheritedScene = try reader.scene3D(node.child("scene3d"), part: theme?.path ?? "") ?? inheritedScene
                inheritedShape = try reader.shape3D(node.child("sp3d"), part: theme?.path ?? "") ?? inheritedShape
                if inheritedScene != nil { origins["scene3D"] = .init(kind: .theme, part: theme?.path ?? "") }; if inheritedShape != nil { origins["shape3D"] = .init(kind: .theme, part: theme?.path ?? "") }
            }
            if let scene = element.scene3D { inheritedScene = scene; origins["scene3D"] = origin }; if let shape = element.shape3D { inheritedShape = shape; origins["shape3D"] = origin }
            if let value=element.frame { frame=value;origins["frame"]=origin }
            if element.sourceProperties?.children.contains(where:{ ["spPr","grpSpPr","xfrm"].contains($0.name) && ($0.name == "xfrm" || $0.children.contains { $0.name == "xfrm" }) }) == true {
                rotation=element.rotation;flipH=element.isFlippedHorizontally;flipV=element.isFlippedVertically;childFrame=element.childFrame
                origins["transform"]=origin
            }
            if let reference=reader.styleReference(try style(element)?.child("fillRef"),part:origin.part) {
                fill=try styleFill(reference)
                origins["fill"] = fill == nil ? nil : .init(kind:.theme,part:theme?.path ?? "")
            }
            if let reference=reader.styleReference(try style(element)?.child("lnRef"),part:origin.part) {
                stroke=nil;origins["stroke"]=nil
                if reference.index == 0 { stroke=nil;origins["stroke"] = .init(kind:.theme,part:theme?.path ?? "") }
                else if let node=matrix("lnStyleLst",reference.index) {
                    if var value=reader.stroke(node,part:theme?.path ?? "") { value.color=recolor(value.color,reference.color);stroke=value }
                    origins["stroke"] = .init(kind:.theme,part:theme?.path ?? "")
                }
            }
            if let value=element.fill { fill=value;origins["fill"]=origin }
            if let value=element.stroke { stroke=value;origins["stroke"]=origin }
            if element.sourceProperties?.children.first(where:{ $0.name == "spPr" })?.children.first(where:{ $0.name == "ln" })?.children.contains(where:{ $0.name == "noFill" }) == true { stroke=nil;origins["stroke"]=origin }
            if let value=element.geometry { geometry=value;custom=nil;origins["geometry"]=origin }
            if let value=element.customGeometry { custom=value;geometry=nil;origins["customGeometry"]=origin }
            if let effects=element.effects {
                if let reference=effects.reference {
                    resolvedEffects=nil;origins["effects"]=nil
                    if reference.index == 0 { resolvedEffects = .init(direct:[],reference:reference);origins["effects"] = .init(kind:.theme,part:theme?.path ?? "") }
                    else if let node=effectStyleNode,var value=reader.effects(node,style:nil,part:theme?.path ?? "") {
                        if var direct=value.direct {
                            for i in direct.indices { if case .outerShadow(var shadow)=direct[i] { shadow.color=shadow.color.map { recolor($0,reference.color) };direct[i] = .outerShadow(shadow) } else if case .drawing(let effect) = direct[i] { direct[i] = .drawing(recolor(effect, reference.color)) } };value.direct=direct
                        }
                        value.reference=reference;resolvedEffects=value;origins["effects"] = .init(kind:.theme,part:theme?.path ?? "")
                    }
                }
                if effects.direct != nil { resolvedEffects=effects;origins["effects"]=origin }
            }
        }
        result.frame=frame;result.fill=fill;result.stroke=stroke;result.geometry=geometry;result.customGeometry=custom
        result.rotation=rotation;result.isFlippedHorizontally=flipH;result.isFlippedVertically=flipV;result.childFrame=childFrame
        result.effects=resolvedEffects
        result.scene3D=inheritedScene; result.shape3D=inheritedShape
        if let body=direct.text {
            var resolved=body
            let kind=direct.placeholder?.kind ?? "",styleKey=["title","ctrTitle"].contains(kind) ? "titleStyle" : kind == "body" ? "bodyStyle" : "otherStyle"
            func placeholderStyles(_ body:TextBody?) -> TextListStyle? {
                guard let body else { return nil };var levels:[Int:TextStyleLevel]=[:]
                for paragraph in body.paragraphs where levels[paragraph.style.level ?? 0] == nil { levels[paragraph.style.level ?? 0] = .init(paragraph:paragraph.style,text:paragraph.defaultTextStyle) }
                return .init(levels:levels)
            }
            let styleLayers:[(TextListStyle?,StyleOrigin)]=[(defaultTextStyle,.init(kind:.presentation,part:storage?.mainPart ?? "")),(master?.textStyles[styleKey],.init(kind:.master,part:master?.path ?? "")),(mp?.text?.listStyle,.init(kind:.master,part:master?.path ?? "",elementID:mp?.id)),(placeholderStyles(mp?.text),.init(kind:.master,part:master?.path ?? "",elementID:mp?.id)),(lp?.text?.listStyle,.init(kind:.layout,part:layout?.path ?? "",elementID:lp?.id)),(placeholderStyles(lp?.text),.init(kind:.layout,part:layout?.path ?? "",elementID:lp?.id)),(body.listStyle,.init(kind:.direct,part:slidePart,elementID:direct.id))]
            func stamp(_ text:TextStyle,_ prefix:String,_ origin:StyleOrigin) {
                for (name,exists) in [("font.family",text.font.family != nil),("font.size",text.font.size != nil),("font.eastAsianFamily",text.font.eastAsianFamily != nil),("font.complexScriptFamily",text.font.complexScriptFamily != nil),("bold",text.bold != nil),("italic",text.italic != nil),("underline",text.underline != nil),("color",text.color != nil),("language",text.language != nil)] where exists { origins[prefix+"."+name]=origin }
                if let a = text.appearance {
                    for (name, exists) in [("spacing",a.spacing != nil),("baseline",a.baseline != nil),("capitalization",a.capitalization != nil),("strike",a.strike != nil),("underlineStyle",a.underlineStyle != nil),("kerning",a.kerning != nil),("fill",a.fill != nil),("outline",a.outline != nil),("effects",a.effects != nil),("scene3D",a.scene3D != nil),("shape3D",a.shape3D != nil)] where exists { origins[prefix+".appearance."+name] = origin }
                }
            }
            func stampParagraph(_ value:ParagraphStyle,_ prefix:String,_ origin:StyleOrigin) {
                for (name,exists) in [("alignment",value.alignment != nil),("level",value.level != nil),("leftMargin",value.leftMargin != nil),("indent",value.indent != nil),("lineSpacing",value.effectiveLineSpacing != nil),("spaceBefore",value.effectiveSpaceBefore != nil),("spaceAfter",value.effectiveSpaceAfter != nil),("bullet",value.bullet != nil)] where exists { origins[prefix+"."+name]=origin }
            }
            for i in resolved.paragraphs.indices {
                let p=body.paragraphs[i],level=p.style.level ?? 0,prefix="paragraph[\(i)]"
                var paragraph=ParagraphStyle(),text=TextStyle()
                for (e,origin) in layers {
                    if let e,let reference=try style(e)?.child("fontRef"),let idx=reference.attr("idx"),["major","minor"].contains(idx),let theme {
                        text.font=idx == "major" ? theme.titleFont : theme.bodyFont
                        text.color=reader.color(reference,part:origin.part)
                        stamp(text,prefix+".text",.init(kind:.theme,part:theme.path))
                    }
                }
                for (list,origin) in styleLayers {
                    for value in [list?.defaultStyle,list?.levels[level]].compactMap({ $0 }) {
                        paragraph=paragraph.overlaying(value.paragraph);text=text.overlaying(value.text);stamp(value.text,prefix+".text",origin);stampParagraph(value.paragraph,prefix,origin)
                    }
                }
                let origin=layers[2].1
                paragraph=paragraph.overlaying(p.style);stampParagraph(p.style,prefix,origin)
                text=text.overlaying(p.defaultTextStyle);stamp(p.defaultTextStyle,prefix+".text",origin)
                resolved.paragraphs[i].style=paragraph;resolved.paragraphs[i].defaultTextStyle=text
                for j in p.runs.indices { resolved.paragraphs[i].runs[j].style=text.overlaying(p.runs[j].style);stamp(p.runs[j].style,prefix+".run[\(j)]",origin) }
                resolved.paragraphs[i].endTextStyle=text.overlaying(p.endTextStyle)
                func font(_ f:Font) -> Font {
                    guard let theme else { return f };var value=f
                    for (key,name) in [("latin",f.family),("ea",f.eastAsianFamily),("cs",f.complexScriptFamily)] {
                        guard let name,name.hasPrefix("+mj-") || name.hasPrefix("+mn-") else { continue }
                        let base=name.hasPrefix("+mj-") ? theme.titleFont : theme.bodyFont
                        let target=name.hasSuffix("lt") ? base.family : name.hasSuffix("ea") ? base.eastAsianFamily : name.hasSuffix("cs") ? base.complexScriptFamily : nil
                        guard let target,!target.isEmpty else { issue("themeフォントが未解決です: \(name)");continue }
                        if key == "latin" { value.family=target } else if key == "ea" { value.eastAsianFamily=target } else { value.complexScriptFamily=target }
                        origins[prefix+".font."+key] = .init(kind:.theme,part:theme.path)
                    }
                    return value
                }
                resolved.paragraphs[i].defaultTextStyle.font=font(resolved.paragraphs[i].defaultTextStyle.font)
                resolved.paragraphs[i].endTextStyle.font=font(resolved.paragraphs[i].endTextStyle.font)
                for j in p.runs.indices { resolved.paragraphs[i].runs[j].style.font=font(resolved.paragraphs[i].runs[j].style.font) }
            }
            var appearance: TextAppearance?
            for (element,origin) in layers {
                if let value = element?.text?.appearance { appearance = appearance?.overlaying(value) ?? value; origins["text.appearance"] = origin }
                if let value=element?.text?.insets { resolved.insets=value;origins["text.insets"]=origin }
                if let value=element?.text?.verticalAlignment { resolved.verticalAlignment=value;origins["text.verticalAlignment"]=origin }
                if let value=element?.text?.wrapsText { resolved.wrapsText=value;origins["text.wrapsText"]=origin }
            }
            resolved.appearance = appearance
            result.text=resolved
        }
        var background:Fill?
        for (value,reference,origin) in [(master?.background,master?.backgroundReference,StyleOrigin(kind:.master,part:master?.path ?? "")),(layout?.background,layout?.backgroundReference,.init(kind:.layout,part:layout?.path ?? "")),(slide.background,slide.backgroundReference,.init(kind:.direct,part:slidePart))] {
            if let reference { background=try styleFill(reference);origins["background"] = .init(kind:.theme,part:theme?.path ?? "") }
            if let value { background=value;origins["background"]=origin }
        }
        let map=slide.colorMapOverride ?? (slide.usesMasterColorMapping == true ? master?.colorMap : layout?.colorMapOverride ?? master?.colorMap) ?? [:]
        issues += reader.warnings.result.map { $0.diagnostic(stage:.read) }
        return .init(element:result,background:background,colorMap:map,origins:origins,diagnostics:issues,theme:theme)
    }
    @concurrent public func resolveElement(slideID: String, elementID: String) async throws -> ElementStyleResolution { try resolveElementSync(slideID:slideID,elementID:elementID) }
    private func resolveElementSync(slideID: String, elementID: String) throws -> ElementStyleResolution { try resolveElement(slideID:slideID,elementID:elementID) }
}
