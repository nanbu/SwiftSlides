import Foundation
import SlideCore

extension KeynoteSource {
    func nativeAxes(_ f: [KeynoteField]) throws -> [ChartAxis] {
        let styleNames: [UInt32: String] = [1: "category3dgridlineopacity", 2: "value3dgridlineopacity", 3: "category3dgridlinestroke", 4: "value3dgridlinestroke", 5: "categoryhorizontalspacing", 46: "defaultlabelanglebaselinedirection", 6: "categorylabelparagraphstyleindex", 7: "defaultlabelparagraphstyleindex", 8: "valuelabelparagraphstyleindex", 9: "categorylabelsorientation", 10: "defaultlabelsorientation", 11: "valuelabelsorientation", 12: "categorymajorgridlineopacity", 13: "valuemajorgridlineopacity", 14: "categorymajorgridlineshadow", 15: "valuemajorgridlineshadow", 16: "categorymajorgridlinestroke", 17: "valuemajorgridlinestroke", 18: "categoryminorgridlineopacity", 19: "valueminorgridlineopacity", 20: "categoryminorgridlineshadow", 21: "valueminorgridlineshadow", 22: "categoryminorgridlinestroke", 23: "valueminorgridlinestroke", 24: "categoryshowaxis", 25: "valueshowaxis", 47: "defaultshowextensionlines", 42: "categoryshowgridlinetickmarks", 43: "valueshowgridlinetickmarks", 26: "categoryshowlastlabel", 27: "categoryshowmajorgridlines", 44: "polarcategoryshowmajorgridlines", 28: "valueshowmajorgridlines", 29: "categoryshowmajortickmarks", 30: "valueshowmajortickmarks", 31: "valueshowminimumlabel", 32: "categoryshowminorgridlines", 33: "valueshowminorgridlines", 34: "categoryshowminortickmarks", 35: "valueshowminortickmarks", 36: "categorytickmarklocation", 37: "valuetickmarklocation", 38: "categorytitleparagraphstyleindex", 39: "defaulttitleparagraphstyleindex", 40: "valuetitleparagraphstyleindex", 41: "categoryverticalspacing"]
        let nonStyleNames: [UInt32: String] = [20: "default1_0dateformat", 2: "default1_0numberformat", 1: "default3dlabelposition", 22: "defaultdateformat", 21: "defaultdurationformat", 23: "defaultlabelexplosion", 42: "defaultnumberformat", 3: "defaultnumberformattype", 4: "valuenumberofdecades", 5: "valuenumberofmajorgridlines", 6: "valuenumberofminorgridlines", 7: "categoryplottoedges", 8: "valuescale", 9: "categoryshowlabels", 10: "defaultshowlabels", 11: "valueshowlabels", 12: "categoryshowserieslabels", 19: "multidatashowserieslabels", 13: "categoryshowtitle", 14: "valueshowtitle", 15: "categorytitle", 16: "valuetitle", 17: "defaultusermax", 18: "defaultusermin"]
        func refs(_ number: UInt32) throws -> [UInt64] { try f.filter { $0.number == number }.map { try Wire.scalar($0.message(maxFields: options.limits.maxXMLNodes), 1) } }
        let legacyStyleNames: [UInt32: String] = [10: "valueshowmajorgridlines", 11: "valueshowminorgridlines", 12: "valuemajorgridlinestroke", 13: "valueminorgridlinestroke", 14: "valuetickmarklocation", 15: "valueshowmajortickmarks", 16: "valueshowminortickmarks", 17: "valuelabelsorientation", 18: "valueshowminimumlabel", 21: "valuemajorgridlineshadow", 22: "valueminorgridlineshadow", 23: "valuemajorgridlineopacity", 24: "valueminorgridlineopacity", 25: "valueshowaxis", 50: "categoryshowmajorgridlines", 51: "categoryshowminorgridlines", 52: "categorymajorgridlinestroke", 53: "categoryminorgridlinestroke", 54: "categorytickmarklocation", 55: "categoryshowmajortickmarks", 56: "categoryshowminortickmarks", 57: "categorylabelsorientation", 58: "categoryhorizontalspacing", 59: "categoryverticalspacing", 60: "categoryshowlastlabel", 63: "categorymajorgridlineshadow", 64: "categoryminorgridlineshadow", 65: "categorymajorgridlineopacity", 66: "categoryminorgridlineopacity", 67: "categoryshowaxis", 102: "defaultlabelsorientation", 110: "defaulttitleparagraphstyleindex", 111: "defaultlabelparagraphstyleindex", 112: "valuetitleparagraphstyleindex", 113: "valuelabelparagraphstyleindex", 114: "categorytitleparagraphstyleindex", 115: "categorylabelparagraphstyleindex", 331: "value3dgridlinestroke", 332: "category3dgridlinestroke", 333: "value3dgridlineopacity", 334: "category3dgridlineopacity"]
        let legacyNonStyleNames: [UInt32: String] = [11: "defaultusermin", 12: "defaultusermax", 13: "defaultnumberformat", 14: "defaultshowlabels", 50: "valuenumberofminorgridlines", 51: "valuescale", 52: "valuenumberofdecades", 53: "valueshowlabels", 54: "valueshowtitle", 55: "valuenumberofmajorgridlines", 56: "valuetitle", 100: "categoryshowlabels", 101: "categoryshowserieslabels", 102: "categoryshowtitle", 103: "categorytitle", 120: "defaultnumberformattype", 336: "default3dlabelposition", 116: "categoryplottoedges"]
        func properties(_ id: UInt64, names: [UInt32: String], typed: inout [String:NativeValue], depth: Int = 0, seen: Set<UInt64> = []) throws -> [String: String] {
            guard depth < options.limits.maxXMLDepth, !seen.contains(id) else { throw SlideError.corruptedPackage("Keynote axis style循環") }
            let object = try self.object(id)
            guard [5012, 5016, 5026, 5027].contains(object.type) else { throw SlideError.corruptedPackage("Keynote axis style型") }
            var values: [String: String] = [:], seen = seen; seen.insert(id)
            if let base = try child(object.fields, 1), base.contains(where: { $0.number == 3 }) {
                values = try properties(ref(base, 3), names: names, typed: &typed, depth: depth + 1, seen: seen)
            }
            let legacy = object.type == 5012 || object.type == 5016
            let fields = legacy ? object.fields.filter { $0.number != 1 } : try child(object.fields, 10000) ?? []
            let mapping = legacy ? (object.type == 5012 ? legacyStyleNames : legacyNonStyleNames) : names
            for field in fields {
                let name = mapping[field.number] ?? "native:\(field.number)"
                if let integer = field.integer { values[name] = String(integer); typed[name] = .unsigned(integer) }
                else if field.wireType == 1 || field.wireType == 5 { let n = try number(fields,field.number); values[name] = n.map(String.init(describing:)); typed[name] = n.map(NativeValue.number) }
                else if ["defaultusermax", "defaultusermin"].contains(name) { let n = try number(field.message(maxFields: options.limits.maxXMLNodes),1); values[name] = n.map(String.init(describing:)); typed[name] = n.map(NativeValue.number) }
                else if ["categorytitle", "valuetitle"].contains(name) { values[name] = field.utf8; typed[name] = field.utf8.map(NativeValue.string) }
                else if let bytes = field.bytes {
                    values["wire:" + name] = bytes.base64EncodedString(); typed[name] = .bytes(bytes)
                    if name.hasSuffix("stroke"), let stroke = try nativeStroke(field.message(maxFields:options.limits.maxXMLNodes)) {
                        var properties: [String:NativeValue] = ["width":.number(stroke.width),"source":.bytes(bytes)]
                        if case .rgb(let hex) = stroke.color { properties["sRGB"] = .string(hex) }
                        typed[name] = .object(properties)
                    }
                }
            }
            return values
        }
        var result: [ChartAxis] = []
        for (kind, styleField, nonStyleField) in [("valAx", UInt32(13), UInt32(14)), ("catAx", UInt32(15), UInt32(16))] {
            let styles = try refs(styleField), nonstyles = try refs(nonStyleField)
            for index in 0..<max(styles.count, nonstyles.count) {
                var values: [String: String] = [:], typed: [String:NativeValue] = [:]
                if styles.indices.contains(index) { values = try properties(styles[index], names: styleNames, typed: &typed) }
                if nonstyles.indices.contains(index) { values.merge(try properties(nonstyles[index], names: nonStyleNames, typed: &typed)) { _, direct in direct } }
                let min = values["defaultusermin"].flatMap(Double.init), max = values["defaultusermax"].flatMap(Double.init)
                if let min, let max, min > max { throw SlideError.corruptedPackage("Keynote軸のmin/max逆転") }
                var axis = ChartAxis(kind: kind, id: "\(kind)-\(index)", crossAxisID: nil, position: nil, minimum: min, maximum: max, logarithmicBase: nil, numberFormat: nil, isDeleted: values[kind == "valAx" ? "valueshowaxis" : "categoryshowaxis"].map { $0 == "0" }, rawXML: "")
                axis.nativeValues = typed; axis.nativeProperties = values; axis.title = values[kind == "valAx" ? "valuetitle" : "categorytitle"]
                axis.scaleType = values["valuescale"].map { "keynote:\($0)" }
                result.append(axis)
            }
        }
        return result
    }
}
