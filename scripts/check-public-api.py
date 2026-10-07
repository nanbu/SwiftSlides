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
catch SlideError.noCodec(.pptx) {}
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
shape.effects = ElementEffects(direct: [.outerShadow(.init(distance: 2))])
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
let layout = try read.presentation.readLayout(at: read.presentation.slides[0].layoutPath!)
let master = try read.presentation.readMaster(at: layout.layout.masterPath!)
precondition(master.master.themePath != nil)
precondition(try read.presentation.slideNumber(for: read.presentation.slides[0].id) == 1)
precondition(try codecs.inspect(result.data, format: .pptx).slideCount == 1)
let reader = try codecs.slideReader(result.data, format: .pptx)
precondition(try reader.slide(id: reader.slideDescriptors[0].id).slide.plainText == "consumer")
let plan = try codecs.planWrite(p)
let output = try codecs.encoded(p, using: plan)
precondition(output.warnings.isEmpty)
let sameChoice = CodecSet([try codecs.codec(for: .pptx)])
precondition(try sameChoice.encoded(p, using: plan).data == output.data)
let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pptx")
defer { try? FileManager.default.removeItem(at: url) }
let saved = try codecs.save(p, to: url, using: plan)
precondition(saved.warnings.isEmpty)
precondition(try codecs.slideReader(contentsOf: url).summary.slideCount == 1)
'''

ODP = '''
let codecs = CodecSet([.odp])
precondition(codecs.formats == [.odp] && codecs.contains(.odp))
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
var p = try codecs.read(data, format: .odp).presentation
let metadata = p.metadata
let reader = try codecs.slideReader(data, format: .odp, options: .init(includeNotes: false))
precondition(reader.summary.format == .odp && !reader.slideDescriptors.isEmpty)
do { _ = try codecs.transaction(&p) { $0.metadata.title = "refuse" }; fatalError("ODP write") }
catch SlideError.unsafeEdit(_) {}
precondition(p.metadata == metadata)
'''

UMBRELLA = '''
var slide = Slide(); slide.addText("umbrella", frame: Rect(x: 10, y: 10, width: 100, height: 30))
var p = Presentation(slides: [slide])
let result = try p.transaction { $0.metadata.title = "committed" }
precondition(result.warnings.isEmpty)
let reopened = try Presentation(data: result.data, format: .pptx)
precondition(try Presentation.read(result.data, format: .pptx).presentation.plainText == "umbrella")
precondition(try Presentation.inspect(result.data, format: .pptx).slideCount == 1)
precondition(try SlideReader(data: result.data, format: .pptx).summary.slideCount == 1)
let plan = try reopened.planWrite()
precondition(try reopened.encoded(using: plan).data == result.data)
func asyncAPIs(_ p: Presentation, _ bytes: Data, _ url: URL) async throws {
    let read = try await Presentation.read(bytes, format: .pptx)
    let summary = try await Presentation.inspect(bytes, format: .pptx)
    let reader = try await CodecSet.all.slideReader(bytes, format: .pptx)
    let plan = try await p.planWrite()
    let result = try await p.encoded(using: plan)
    let saved = try await p.save(to: url, using: plan)
    print(read.warnings, summary.slideCount, reader.summary.slideCount, result.warnings, saved.warnings)
}
'''

CONFIGURATIONS = [
    ('CoreClient', ['SlideCore'], CORE),
    ('PPTXClient', ['SlideCore', 'SlidePPTX'], PPTX),
    ('ODPClient', ['SlideCore', 'SlideODP'], ODP),
    ('FullClient', ['SwiftSlides'], UMBRELLA),
]


def client_source(products, body):
    # A plain Bool parameter lets throwing expressions run before the assertion.
    return ('import Foundation\n' + ''.join('import ' + p + '\n' for p in products)
            + 'func require(_ value: Bool) { precondition(value) }\n'
            + body.replace('precondition(', 'require('))

NEGATIVE = [
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
    'codecs.write(p, to: url)', 'codecs.save(p, to: url, using: plan)',
    'p.write(to: url)', 'p.save(to: url, using: plan)',
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
            run([str(binary / name), str(ROOT / 'Tests/SwiftSlidesTests/Fixtures/styles.odp')])
            print('PASS: independent ' + name, flush=True)

        modules = binary / 'Modules' if (binary / 'Modules').is_dir() else binary
        command = ['swiftc', '-typecheck', '-I', str(modules), '-Xcc', '-fmodule-map-file=' + str(ROOT / 'Sources/CZlib/module.modulemap')]
        probe = directory / 'Probe.swift'
        for name, code in NEGATIVE:
            probe.write_text('import Foundation\nimport SwiftSlides\n' + code + '\n')
            run(command + [str(probe)], success=False, needles=('inaccessible', 'cannot find', 'get-only', "'let' constant"))
            print('PASS: hidden or read-only ' + name, flush=True)

        for asynchronous in (False, True):
            prefix = 'try await ' if asynchronous else 'try '
            setup = 'func probe() %sthrows {\nvar p = Presentation(); p.metadata.title = "baseline"\nlet codecs = CodecSet.all\nlet url = URL(fileURLWithPath: "output.pptx")\nlet plan = %sp.planWrite()\n_ = (codecs, url, plan)\n' % ('async ' if asynchronous else '', prefix)
            for call in RESULT_CALLS[:4] if asynchronous else RESULT_CALLS:
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
