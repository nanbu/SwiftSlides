#!/usr/bin/env python3
"""Build independent consumers, then check visibility and non-discardable save results."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

CORE = '''
let empty = CodecSet([])
precondition(empty.formats.isEmpty && !empty.contains(.pptx))
do { _ = try empty.codec(for: .pptx); fatalError("empty set") }
catch SlideError.noCodec(for: .pptx) {}
var slide = Slide(id: "slide")
let id = slide.addText("before", frame: Rect(x: 10, y: 10, width: 100, height: 30))
var p = Presentation(slides: [slide])
let count = try p.editSlide(id: "slide") { slide in
    try slide.editElement(id: id) { element in
        try element.editText { body in
            body.paragraphs[0].runs[0].text = "after"
            return body.paragraphs.count
        }
    }
}
precondition(count == 1 && p.plainText == "after")
let spacing = ParagraphStyle(lineSpacingValue: .points(18)).overlaying(.init(lineSpacingValue: .percentage(0)))
precondition(spacing.effectiveLineSpacing == .percentage(0))
let field = TextField(id: "{11111111-1111-1111-1111-111111111111}", type: "slidenum", cachedText: "1")
let context = TextFieldContext(slideNumber: 2, date: Date(timeIntervalSince1970: 0), localeIdentifier: "en_US_POSIX", timeZoneIdentifier: "UTC")
precondition(TextFieldEvaluator.evaluate(field, context: context).text == "2")
let alpha = Color.value(.init(base: .sRGB("FFFFFF"), transforms: [.init(name: "alpha", value: "50000")]))
precondition(ColorResolver.resolve(alpha).color?.alpha == 0.5)
var shape = Element(); shape.customGeometry = CustomGeometry(paths: [.init(commands: [.move(.init(x: "0", y: "0")), .close])])
shape.spatialGeometry = nil
shape.model3D = nil
let appearance = TextAppearance(spacing: 2, script: "super", baselinePoints: 3)
precondition(appearance.overlaying(.init(spacing: 0)).spacing == 0)
cellAppearanceTypeCheck(appearance)
shape.effects = ElementEffects(direct: [.outerShadow(.init(distance: 2))])
let gradient = GradientFill(stops: [GradientStop(position: 0, color: .rgb("FF0000"))])
shape.fill = .gradient(gradient)
shape.image = Image(path: "fictional.png"); shape.image?.crop = ImageCrop(left: 0.2)
shape.media = [MediaReference(kind: .audio, reference: PartReference(relationshipID: "audio"))]
shape.nativeFeatures = [NativeFeatureDescriptor(part: "fictional.xml", name: "extra", namespace: "urn:fictional", xml: "<extra/>")]
var cell = TableCell("display"); cell.value = TableCellValue(type: "float", lexicalValue: "12.50")
cell.borders = [TableCellBorder(edge: .right, isExplicitlyNone: true)]; cell.formula = "of:=1+1"
precondition(cell.value?.number == 12.5)
var described = Slide(); described.transition = SlideTransition(advanceAfterMilliseconds: 0)
described.timing = SlideTiming(root: TimingNode(name: "timing", namespace: "urn:fictional"))
described.comments = [SlideComment(text: "Fictional comment", part: "comment.xml")]
precondition(described.transition?.advanceAfterMilliseconds == 0)
func cellAppearanceTypeCheck(_ a: TextAppearance) { var style = TextStyle(); style.appearance = a }
func workbookAPI(_ data: Data) throws -> WorkbookRangeResolution { try WorkbookDataReader.readXLSX(data).resolve("Sheet1!A1:A2") }
let guide = try GeometryEvaluator.evaluate(CustomGeometry(guides:[.init(name:"half",formula:"val wd2")]),width:100,height:50)
precondition(guide.guides["half"] == 50)
let names = WorkbookData(sheets:[.init(name:"Sheet1",cells:["A1":.init(address:"A1",type:"n",value:"3")])],definedNames:[.init(name:"Value",formula:"Sheet1!A1")])
precondition(try names.resolve("Value").points.first?.number == 3)
precondition(try WorkbookFormulaResolver.translate("A1",from:"A1",to:"B2") == "B2")
let model = try Model3DReader.read(Data(#"{"asset":{"version":"2.0"},"nodes":[{}],"scenes":[{"nodes":[0]}]}"#.utf8))
precondition(model.scenes == [[0]] && model.nodes[0].matrix.count == 16)
precondition(try model.materials.isEmpty && model.skins.isEmpty && model.animations.isEmpty)
precondition(try VectorPath.readSVG("M0 0L1 2").commands.count == 2)
func parallelReadingAPI(_ reader: SlideReader) async throws -> [SlideReadResult] {
    _ = reader.cacheStatistics
    return try await reader.readSlides(selection:.all,maxConcurrentReads:2)
}
func cacheBudgetAPI(_ url: URL, _ codecs: CodecSet) async throws -> SlideReader {
    try await codecs.fileSlideReader(contentsOf:url,format:.pptx,cacheBudget:.init(totalBytes:8 << 20))
}
func originalXMLNames(_ node: SourceXMLNode) -> (String, [String: String], [String: String]) {
    (node.qualifiedName, node.namespaceBindings, node.attributeNames)
}
'''

PPTX = '''
let codecs = CodecSet([.pptx, .pptm, .pptx])
precondition(codecs.formats == [.pptx, .pptm] && codecs.contains(.pptx))
precondition(try codecs.codec(for: .pptm).format == .pptm)
var slide = Slide(); slide.addText("consumer", frame: Rect(x: 10, y: 10, width: 100, height: 30))
var p = Presentation(slides: [slide])
let result = try codecs.transaction(&p) { $0.metadata.title = "committed" }
precondition(result.warnings.isEmpty)
let read = try codecs.read(result.data, format: .pptx)
precondition(read.presentation.metadata.title == "committed")
let xml = try read.presentation.readSourceXML(at: "ppt/slides/slide1.xml")
let prefix = xml.root.qualifiedName.contains(":") ? String(xml.root.qualifiedName.split(separator: ":")[0]) : ""
precondition(xml.root.namespaceBindings[prefix] == xml.root.namespace)
let layout = try read.presentation.readLayout(at: read.presentation.slides[0].layoutPath!)
let master = try read.presentation.readMaster(at: layout.layout.masterPath!)
precondition(master.master.themePath != nil)
precondition(try read.presentation.slideNumber(for: read.presentation.slides[0].id) == 1)
precondition(try codecs.inspect(result.data, format: .pptx).slideCount == 1)
let reader = try codecs.slideReader(result.data, format: .pptx)
precondition(try reader.slide(id: reader.slideDescriptors[0].id).slide.plainText == "consumer")
let plan = try codecs.planWrite(p)
let output = try codecs.write(p, using: plan)
precondition(output.warnings.isEmpty)
let sameChoice = CodecSet([try codecs.codec(for: .pptx)])
precondition(try sameChoice.write(p, using: plan).data == output.data)
let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pptx")
defer { try? FileManager.default.removeItem(at: url) }
let saved = try codecs.write(p, to: url, using: plan)
precondition(saved.warnings.isEmpty)
precondition(try codecs.slideReader(contentsOf: url, format: .pptx).summary.slideCount == 1)
precondition(try codecs.read(contentsOf: url, format: .pptx).presentation.plainText == "consumer")
precondition(try codecs.inspect(contentsOf: url, format: .pptx).slideCount == 1)
precondition(try codecs.fileSlideReader(contentsOf: url, cacheBytes: 65536).slide(id: reader.slideDescriptors[0].id).slide.plainText == "consumer")
'''

ODP = '''
precondition(try ODPTransformReader.read("translate(2pt 3pt)").matrix.tx == 2)
let styleIndex = try ODPStyleIndex(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
_ = styleIndex
let codecs = CodecSet([.odp])
precondition(codecs.formats == [.odp] && codecs.contains(.odp))
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
var p = try codecs.read(data, format: .odp).presentation
let metadata = p.metadata
let reader = try codecs.slideReader(data, format: .odp, options: .init(includesNotes: false))
precondition(reader.summary.format == .odp && !reader.slideDescriptors.isEmpty)
do { _ = try codecs.transaction(&p) { $0.metadata.title = "refuse" }; fatalError("ODP write") }
catch SlideError.unsafeEdit(_) {}
precondition(p.metadata == metadata)
let semantic = try codecs.read(contentsOf: URL(fileURLWithPath: CommandLine.arguments[5])).presentation
let geometry = semantic.slides[0].elements.first { $0.id == "enhanced" }!.enhancedGeometry!
precondition(geometry.path!.count == 16 && geometry.path![1].arguments == [GeometryOperand.modifier(0), .formula("edge")])
precondition(geometry.mirrorHorizontal == false && geometry.viewBox!.x == -10)
let rebuilt = EnhancedGeometry(shapeType: geometry.shapeType, viewBox: geometry.viewBox, modifiers: geometry.modifiers,
    equations: geometry.equations, path: geometry.path, textAreas: geometry.textAreas,
    mirrorHorizontal: geometry.mirrorHorizontal, mirrorVertical: geometry.mirrorVertical, handles: geometry.handles, source: geometry.source)
precondition(rebuilt == geometry)
let evaluated = try GeometryEvaluator.evaluate(geometry)
precondition(evaluated.guides["edge"] == 50 && evaluated.handles[0].values["handle-position-x"] == 25)
let math = semantic.slides[0].elements.first { $0.id == "package-math" }!.equation!
precondition(math.dialect == Equation.Dialect.mathML && math.root.kind == EquationNode.Kind.math)
precondition(!math.lexicalText.contains("NOT DISPLAYED"))
let snapshot = try JSONDecoder().decode(Equation.self, from: JSONEncoder().encode(math))
precondition(snapshot == math)
let selected = try codecs.slideReader(contentsOf: URL(fileURLWithPath: CommandLine.arguments[5]))
precondition(try selected.slide(id: "semantic-page").slide == semantic.slides[0])
'''

UMBRELLA = '''
var slide = Slide(); slide.addText("umbrella", frame: Rect(x: 10, y: 10, width: 100, height: 30))
var p = Presentation(slides: [slide])
let result = try p.transaction { $0.metadata.title = "committed" }
let written = try p.write()
precondition(written.warnings.isEmpty)
let explicitPlan = try p.planWrite()
precondition(try p.write(using: explicitPlan).data == CodecSet.all.write(p, using: explicitPlan).data)
precondition(result.warnings.isEmpty)
let reopened = try Presentation(data: result.data, format: .pptx)
precondition(try Presentation.read(result.data, format: .pptx).presentation.plainText == "umbrella")
precondition(try Presentation.inspect(result.data, format: .pptx).slideCount == 1)
precondition(try SlideReader(data: result.data, format: .pptx).summary.slideCount == 1)
let plan = try reopened.planWrite()
precondition(try reopened.write(using: plan).data == result.data)
func asyncAPIs(_ p: Presentation, _ bytes: Data, _ url: URL) async throws {
    let read = try await Presentation.read(bytes, format: .pptx)
    let summary = try await Presentation.inspect(bytes, format: .pptx)
    let reader = try await CodecSet.all.slideReader(bytes, format: .pptx)
    let plan = try await p.planWrite()
    let result = try await p.write(using: plan)
    let saved = try await p.write(to: url, using: plan)
    print(read.warnings, summary.slideCount, reader.summary.slideCount, result.warnings, saved.warnings)
}
'''

KEYNOTE = '''
let bytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
let set = CodecSet([.keynote])
let read = try set.read(bytes)
precondition(read.presentation.sourceFormat == .keynote && !read.presentation.slides.isEmpty)
let inventory = try read.presentation.readKeynoteObjects()
precondition(!inventory.objects.isEmpty)
precondition(read.presentation.plainText.contains("Fictional"))
if inventory.objects.contains(where: { $0.type == 6000 }) {
    let tables=read.presentation.slides.flatMap { $0.elements }.compactMap { $0.table }
    precondition(!tables.isEmpty && tables[0].plainText.contains("Fictional cell"))
    precondition(tables[0].rows[0][1].value?.number == 42.5)
}
if inventory.objects.contains(where: { $0.type == 5021 }) {
    let charts=read.presentation.slides.flatMap { $0.elements }.compactMap { $0.chart }
    precondition(!charts.isEmpty && charts[0].groups[0].series[0].values?.points[0].number == 12.5)
}
precondition(try set.slideReader(bytes).slideDescriptors.count == read.presentation.slides.count)
'''
DECRYPT = '''
let bytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
let unlocked = try Presentation(data: bytes, password: "fictional-鍵")
precondition(unlocked.sourceFormat == .keynote && !unlocked.slides.isEmpty)
precondition(unlocked.plainText.contains("Fictional"))
precondition(unlocked.readWarnings.contains { $0.feature == "SEC-001" })
func asyncPasswordAPIs(_ bytes:Data,_ url:URL) async throws {
    _ = try await decrypt(bytes,password:"fictional-鍵")
    _ = try await Presentation.read(contentsOf:url,password:"fictional-鍵")
    _ = try await Presentation.inspect(bytes,password:"fictional-鍵")
    _ = try await CodecSet.all.slideReader(contentsOf:url,password:"fictional-鍵")
}
'''

MATH3D = '''
let mathBytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[4]))
let mathDeck = try CodecSet([.pptx]).read(mathBytes).presentation
let mathShape = mathDeck.slides[0].elements.first { $0.name == "Fictional equation and 3D" }!
let equation: Equation = mathShape.text!.paragraphs[0].runs[1].equation!
precondition(equation.root.kind == EquationNode.Kind.paragraph && equation.lexicalText == "a+bcx21234")
let scene: Scene3D = mathShape.scene3D!
let shape: Shape3D = mathShape.shape3D!
precondition(scene.cameraRotation == Rotation3D(latitude:10,longitude:20,revolution:0))
precondition(shape.topBevel == Bevel3D(width:1,height:2,preset:"circle"))
precondition(try CodecSet([.pptx]).write(mathDeck).data == mathBytes)
'''

LEGACY = '\n'.join([
 'let set = CodecSet([.ppt, .keynoteLegacy, .sxi])',
 'require(set.formats.count == 3)',
 'for index in 6...8 {',
 ' let bytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[index]))',
 ' let result = try set.read(bytes)',
 ' require(!result.presentation.slides.isEmpty)',
 ' require(try set.slideReader(bytes).summary.format == result.presentation.sourceFormat)',
 '}',
 'require(try set.capabilities(for: .ppt).capability(for: "PKG-013", operation: .read, profile: .pptBinary).status == .partial)',
])

CONFIGURATIONS = [
    ('KeynoteClient', ['SlideCore', 'SlideKeynote'], CORE + KEYNOTE),
    ('DecryptClient', ['SlideDecrypt'], CORE + DECRYPT),
    ('LegacyClient', ['SlideCore', 'SlideLegacy'], CORE + LEGACY),
    ('CoreClient', ['SlideCore'], CORE),
    ('PPTXClient', ['SlideCore', 'SlidePPTX'], PPTX + MATH3D),
    ('ODPClient', ['SlideCore', 'SlideODP'], ODP),
    ('FullClient', ['SwiftSlides'], UMBRELLA + MATH3D),
]


def client_source(products, body):
    # A plain Bool parameter lets throwing expressions run before the assertion.
    return ('import Foundation\n' + ''.join('import ' + p + '\n' for p in products)
            + 'func require(_ value: Bool) { precondition(value) }\n'
            + body.replace('precondition(', 'require('))

NEGATIVE = [
    ('removed data alias', '_ = try Presentation().data()'),
    ('removed encoded alias', '_ = try Presentation().encoded()'),
    ('removed save alias', 'let p = Presentation(); _ = try p.save(to: URL(fileURLWithPath: "x.pptx"), using: p.planWrite())'),
    ('WriteResult.data setter', 'var r = WriteResult(data: Data()); r.data = Data()'),
    ('WriteResult.warnings setter', 'var r = WriteResult(data: Data()); r.warnings = []'),
    ('PPTXCodec', '_ = PPTXCodec.self'),
    ('ODPCodec', '_ = ODPCodec.self'),
    ('KeynoteCodec', '_ = KeynoteCodec.self'),
    ('PPTLegacyCodec', '_ = PPTLegacyCodec.self'),
    ('LegacyXMLCodec', '_ = LegacyXMLCodec.self'),
    ('Codec.implementation', '_ = try CodecSet.all.codec(for: .pptx).implementation'),
    ('Codec.identity', '_ = try CodecSet.all.codec(for: .pptx).identity'),
    ('SavePlan.codecIdentity', '_ = try Presentation().planWrite().codecIdentity'),
    ('Presentation.storage', '_ = Presentation().storage'),
    ('Presentation.slideClones', '_ = Presentation().slideClones'),
    ('Element.rawXML setter', 'var e = Element(); e.rawXML = "injected"'),
    ('SavePlan.canSave setter', 'var plan = try Presentation().planWrite(); plan.canSave = true'),
    ('PackageArchive', '_ = PackageArchive.self'),
    ('MarkupNode', '_ = MarkupNode.self'),
    ('ZIPWriter', '_ = ZIPWriter.self'),
]

RESULT_CALLS = [
    'p.write()', 'p.write(using: plan)',
    'codecs.write(p, using: plan)', 'codecs.write(p, to: url, using: plan)',
    'p.write(to: url, using: plan)',
    'codecs.write(p, to: url)',
    'p.write(to: url)',
    'codecs.transaction(&p) { $0.metadata.title = "x" }',
    'p.transaction { $0.metadata.title = "x" }',
]


def run(command, *, success=True, needles=()):
    result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    diagnostics = result.stdout + result.stderr
    if success and result.returncode:
        raise SystemExit(diagnostics)
    if not success and (not result.returncode or not any(n in diagnostics for n in needles)):
        raise SystemExit('Negative probe missed its intended failure:\n' + diagnostics)
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--disable-sandbox', action='store_true', help='Use SwiftPM without its nested manifest sandbox.')
    parser.add_argument('--keynote-fixture',type=Path,default=ROOT/'Tests/SwiftSlidesTests/Fixtures/native-synthetic.keynote.zip')
    parser.add_argument('--encrypted-keynote-fixture',type=Path,default=ROOT/'Tests/SwiftSlidesTests/Fixtures/encrypted-native.keynote.zip')
    args = parser.parse_args()
    flags = ['--disable-sandbox'] if args.disable_sandbox else []
    with tempfile.TemporaryDirectory(prefix='swiftslides-public-api-') as tmp:
        directory = Path(tmp)
        targets = ',\n'.join('.executableTarget(name: %s, dependencies: [%s])' % (
            json.dumps(name), ', '.join('.product(name: %s, package: "SwiftSlides")' % json.dumps(p) for p in products))
            for name, products, _ in CONFIGURATIONS)
        (directory / 'Package.swift').write_text('''// swift-tools-version: 6.4
import PackageDescription
let package = Package(name: "APIClient", platforms: [.macOS(.v14)],
    dependencies: [.package(path: %s)], targets: [%s])
''' % (json.dumps(str(ROOT)), targets))
        for name, products, body in CONFIGURATIONS:
            source = directory / 'Sources' / name / 'main.swift'
            source.parent.mkdir(parents=True)
            source.write_text(client_source(products, body))
        run(['swift', 'build', '--package-path', str(directory), *flags, '-Xswiftc', '-warnings-as-errors'])
        binary = Path(run(['swift', 'build', '--package-path', str(directory), *flags, '--show-bin-path']).strip())
        for name, _, _ in CONFIGURATIONS:
            run([str(binary / name), str(ROOT / 'Tests/SwiftSlidesTests/Fixtures/styles.odp'),str(args.keynote_fixture),str(args.encrypted_keynote_fixture),str(ROOT / 'Tests/SwiftSlidesTests/Fixtures/math-3d.pptx'),str(ROOT / 'Tests/SwiftSlidesTests/Fixtures/semantic-reading.odp'), str(ROOT / 'Tests/SwiftSlidesTests/Fixtures/libreoffice-legacy.ppt'), str(ROOT / 'Tests/SwiftSlidesTests/Fixtures/legacy-xml.key.zip'), str(ROOT / 'Tests/SwiftSlidesTests/Fixtures/legacy-impress.sxi')])
            print('PASS: independent ' + name, flush=True)

        modules = binary / 'Modules' if (binary / 'Modules').is_dir() else binary
        command = ['swiftc', '-typecheck', '-I', str(modules), '-Xcc', '-fmodule-map-file=' + str(ROOT / 'Sources/CZlib/module.modulemap')]
        probe = directory / 'Probe.swift'
        for name, code in NEGATIVE:
            probe.write_text('import Foundation\nimport SwiftSlides\n' + code + '\n')
            run(command + [str(probe)], success=False, needles=('inaccessible', 'cannot find', 'get-only', "'let' constant", 'has no member'))
            print('PASS: hidden or read-only ' + name, flush=True)

        for asynchronous in (False, True):
            prefix = 'try await ' if asynchronous else 'try '
            setup = 'func probe() %sthrows {\nvar p = Presentation(); p.metadata.title = "baseline"\nlet codecs = CodecSet.all\nlet url = URL(fileURLWithPath: "output.pptx")\nlet plan = %sp.planWrite()\n_ = (codecs, url, plan)\n' % ('async ' if asynchronous else '', prefix)
            for call in [c for c in RESULT_CALLS if 'transaction' not in c] if asynchronous else RESULT_CALLS:
                probe.write_text('import Foundation\nimport SwiftSlides\n' + setup + prefix + call + '\n}\n')
                run(command + ['-warnings-as-errors', str(probe)], success=False, needles=('result of call to',))
                probe.write_text('import Foundation\nimport SwiftSlides\n' + setup + '_ = ' + prefix + call + '\n}\n')
                run(command + ['-warnings-as-errors', str(probe)])
                print('PASS: explicit result use required: ' + ('async ' if asynchronous else '') + call.split('(')[0], flush=True)

        # Positive control after every negative probe: a broken module cannot count as successful refusal.
        probe.write_text(client_source(['SwiftSlides'], UMBRELLA))
        run(command + ['-warnings-as-errors', str(probe)])
        print('PASS: positive consumer compiles after negative probes', flush=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
