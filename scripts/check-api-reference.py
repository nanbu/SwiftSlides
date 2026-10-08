#!/usr/bin/env python3
"""Verify rendered public symbols and guide pages, with isolated negative controls."""
import argparse
import json
from pathlib import Path
import re
import sys


def audit(symbols, rendered, blobs):
    errors = []
    if not symbols: errors.append('empty public symbol evaluation set')
    if not rendered: errors.append('empty rendered symbol evaluation set')
    missing = symbols - rendered
    if missing: errors.append('missing rendered symbols: ' + str(len(missing)))
    for path, blob in blobs:
        if re.search(rb'/(?:Users|home)/[A-Za-z0-9_.-]+/', blob): errors.append('local path in reference: ' + path)
    return errors


def self_test():
    if audit({'symbol'}, {'symbol'}, [('page.json', b'public')]): raise RuntimeError('valid reference refused')
    controls = [
        ({'symbol'}, {'different'}, [], 'missing rendered'),
        (set(), {'symbol'}, [], 'empty public'),
        ({'symbol'}, set(), [], 'empty rendered'),
        ({'symbol'}, {'symbol'}, [('page.json', ('/Us' + 'ers/owner/code').encode())], 'local path'),
    ]
    for symbols, rendered, blobs, expected in controls:
        if not any(expected in e for e in audit(symbols, rendered, blobs)): raise RuntimeError('negative control missed: ' + expected)
    print('API-reference negative controls: 4 passed')


def main():
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('output', nargs='?'); parser.add_argument('--self-test', action='store_true'); args = parser.parse_args()
    self_test()
    if args.self_test: return 0
    if not args.output: parser.error('output directory is required')
    root = Path(__file__).resolve().parents[1]
    main_graphs = list((root / '.build/docc-public-graphs').glob('*.symbols.json'))
    crypto_graphs = list((root / '.build/docc-decrypt-public-graphs').glob('*.symbols.json'))
    graphs = main_graphs + crypto_graphs
    if not any(p.name == 'SwiftSlides.symbols.json' for p in main_graphs) or not any(p.name == 'SlideDecrypt.symbols.json' for p in crypto_graphs):
        print('missing umbrella or optional crypto symbol graph', file=sys.stderr); return 1
    symbols = {s['identifier']['precise'] for graph in graphs for s in json.loads(graph.read_text())['symbols'] if '::SYNTHESIZED::' not in s['identifier']['precise']}
    output = Path(args.output)
    rendered = set(); main_rendered = set(); crypto_rendered = set()
    blobs = []
    for path in output.rglob('*'):
        if not path.is_file(): continue
        data = path.read_bytes(); blobs.append((str(path.relative_to(output)), data))
        if path.suffix == '.json' and 'data' in path.parts:
            metadata = json.loads(data).get('metadata', {})
            if metadata.get('externalID'):
                rendered.add(metadata['externalID'])
                (crypto_rendered if path.is_relative_to(output / 'crypto') else main_rendered).add(metadata['externalID'])
    errors = audit(symbols, rendered, blobs)
    for name, group, pages in [('SwiftSlides', main_graphs, main_rendered), ('SlideDecrypt', crypto_graphs, crypto_rendered)]:
        expected = {s['identifier']['precise'] for graph in group for s in json.loads(graph.read_text())['symbols'] if '::SYNTHESIZED::' not in s['identifier']['precise']}
        errors += [name + ': ' + e for e in audit(expected, pages, [])]
    for guide in ('reading', 'cookbook'):
        if not (output / 'data/documentation/swiftslides' / (guide + '.json')).is_file(): errors.append('missing guide: ' + guide)
    if not (output / 'crypto/data/documentation/slidedecrypt.json').is_file(): errors.append('missing optional crypto module')
    if errors: print('\n'.join(errors), file=sys.stderr); return 1
    print('API reference: %d public symbols rendered; guides and privacy passed' % len(symbols))
    return 0


if __name__ == '__main__': sys.exit(main())
