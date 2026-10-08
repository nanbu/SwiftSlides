#!/usr/bin/env python3
"""公開CLIで実producerの旧PPT・Keynote式/結合を照合し、任意のODF世代RNGを検査する。"""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DRAW = 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0'

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli', type=Path, default=ROOT / '.build/release/swiftslides')
    parser.add_argument('--odf-schema-dir', type=Path, help='odf12.rng / odf13.rng / odf14.rngを置いたdirectory')
    args = parser.parse_args()
    def read(path):
        return json.loads(subprocess.check_output([str(args.cli.resolve()), 'read-json', str(path)], text=True))
    fixtures = ROOT / 'Tests/SwiftSlidesTests/Fixtures'
    ppt = read(fixtures / 'libreoffice-legacy.ppt')
    assert ppt['format'] == 'ppt' and ppt['size'] == {'width': 960, 'height': 540}
    assert [s['id'] for s in ppt['slides']] == ['256', '257']
    def plain(element):
        return '\n'.join(''.join(r['text'] for r in p['runs']) for p in element.get('text', {}).get('paragraphs', []))
    assert [plain(e) for e in ppt['slides'][0]['elements'][:3]] == ['売上成長 — 90 days', '顧客集中', '実行']
    assert [plain(e) for e in ppt['slides'][1]['elements']] == ['Metrics']
    keynote = read(fixtures / 'keynote-formula-15.4.key.zip')
    table = next(e['table'] for e in keynote['slides'][0]['elements'] if 'table' in e)
    assert table['rows'][0][0]['columnSpan'] == 2 and table['rows'][0][1]['isMergeContinuation']
    cell = table['rows'][1][2]
    assert float(cell['value']['lexicalValue']) == 5
    assert [t['kind'] for t in cell['nativeFormula']['tokens']] == ['CELL_REFERENCE_NODE', 'CELL_REFERENCE_NODE', 'ADDITION_NODE']
    assert [(t['row'], t['column']) for t in cell['nativeFormula']['tokens'][:2]] == [(1, 0), (1, 1)]
    print('Producer期待値: LibreOffice旧PPT 2 slides、Keynote 15.4 式cache=5・参照token・2セル結合 passed')
    if args.odf_schema_dir:
        from lxml import etree
        with zipfile.ZipFile(fixtures / 'semantic-reading.odp') as z:
            original = {n: z.read(n) for n in z.namelist()}
        for version in ['1.2', '1.3', '1.4']:
            parts = dict(original)
            for part in ['content.xml', 'styles.xml', 'META-INF/manifest.xml']:
                parts[part] = parts[part].replace(b'version="1.3"', ('version="' + version + '"').encode())
            if version == '1.4':
                parts['content.xml'] = parts['content.xml'].replace(b'draw:handle-position="$0 ?edge"', b'draw:handle-position-x="$0" draw:handle-position-y="?edge"')
            schema = etree.RelaxNG(etree.parse(str(args.odf_schema_dir / ('odf' + version.replace('.', '') + '.rng'))))
            for part in ['content.xml', 'styles.xml']:
                tree = etree.fromstring(parts[part])
                for extension in tree.xpath('//*[namespace-uri()="urn:fictional:future" and not(ancestor::*[namespace-uri()="http://www.w3.org/1998/Math/MathML"])]'):
                    extension.getparent().remove(extension)
                schema.assertValid(tree)
            with tempfile.TemporaryDirectory(prefix='fictional-odf-version-') as directory:
                path = Path(directory) / 'semantic.odp'
                with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
                    for n, data in parts.items(): z.writestr(n, data)
                model = read(path)
                geometry = next(e['enhancedGeometry'] for e in model['slides'][0]['elements'] if e.get('id') == 'enhanced')
                assert len(geometry['path']) == 16
                assert any(e.get('equation', {}).get('dialect') == 'mathML' for e in model['slides'][0]['elements'])
            print('ODF ' + version + ': content/styles RNG + CLI path/MathML passed; intentional foreign node excluded')

if __name__ == '__main__':
    main()
