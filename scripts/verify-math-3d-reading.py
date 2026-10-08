#!/usr/bin/env python3
"""Compare fictional equation operands and 3D values using the public CLI and an independent XML parser."""
import argparse
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MC = 'http://schemas.openxmlformats.org/markup-compatibility/2006'
A14 = 'http://schemas.microsoft.com/office/drawing/2010/main'

def nodes(root):
    yield root
    for child in root['children']:
        yield from nodes(child)

def verify(path, cli):
    snapshot = json.loads(subprocess.check_output([str(cli), 'read-json', str(path)], text=True))
    with zipfile.ZipFile(path) as archive:
        slide = ET.fromstring(archive.read('ppt/slides/slide1.xml'))
        p = slide.tag.split('}')[0][1:]
        a = 'http://purl.oclc.org/ooxml/drawingml/main' if p.startswith('http://purl.') else 'http://schemas.openxmlformats.org/drawingml/2006/main'
        m = 'http://purl.oclc.org/ooxml/officeDocument/math' if p.startswith('http://purl.') else 'http://schemas.openxmlformats.org/officeDocument/2006/math'
        source = next(n for n in slide.findall(f'.//{{{p}}}sp') if n.find(f'{{{p}}}nvSpPr/{{{p}}}cNvPr').get('id') == '900')
        model = next(n for n in snapshot['slides'][0]['elements'] if n['id'] == '900')
        equation = model['text']['paragraphs'][0]['runs'][1]['equation']
        choice = next(n for n in source.findall(f'.//{{{MC}}}Choice') if n.get('Requires') == 'a14')
        native = choice.find(f'{{{A14}}}m/{{{m}}}oMathPara')
        all_nodes = list(nodes(equation['root']))
        fraction = next(n for n in all_nodes if n['kind'] == 'fraction')
        native_fraction = native.find(f'{{{m}}}oMath/{{{m}}}f')
        operands = [next(n for n in fraction['children'] if n['kind'] == kind) for kind in ['numerator', 'denominator']]
        for operand, tag in zip(operands, ['num', 'den']):
            original = ''.join(n.text or '' for n in native_fraction.find(f'{{{m}}}{tag}').iter(f'{{{m}}}t'))
            actual = ''.join(n.get('text', '') for n in nodes(operand) if n['kind'] == 'text')
            assert original == actual
        native_matrix = native.find(f'{{{m}}}oMath/{{{m}}}m')
        matrix = next(n for n in all_nodes if n['kind'] == 'matrix')
        original_rows = [[''.join(t.text or '' for t in e.iter(f'{{{m}}}t')) for e in row.findall(f'{{{m}}}e')] for row in native_matrix.findall(f'{{{m}}}mr')]
        actual_rows = [[''.join(n.get('text', '') for n in nodes(e) if n['kind'] == 'text') for e in row['children']] for row in matrix['children'] if row['kind'] == 'matrixRow']
        assert actual_rows == original_rows == [['1', '2'], ['3', '4']]
        expected_tokens = ''.join(t.text or '' for t in native.iter(f'{{{m}}}t'))
        assert model['text']['paragraphs'][0]['runs'][1]['text'] == expected_tokens == 'a+bcx21234'
        assert len(equation['source']['content']) == 4  # three Choices and the untouched Fallback
        assert equation['source']['namespaceBindings']['a14'] == A14
        assert equation['source']['namespaceBindings']['u'] == 'urn:fictional:future'
        scene = source.find(f'{{{p}}}spPr/{{{a}}}scene3d')
        camera = scene.find(f'{{{a}}}camera'); light = scene.find(f'{{{a}}}lightRig')
        actual = model['scene3D']
        assert actual['cameraPreset'] == camera.get('prst') and actual['fieldOfView'] == int(camera.get('fov')) / 60000
        assert actual['zoom'] == int(camera.get('zoom')) / 100000
        assert actual['lightRig'] == light.get('rig') and actual['lightDirection'] == light.get('dir')
        for n, key in [(camera, 'cameraRotation'), (light, 'lightRotation')]:
            rotation = n.find(f'{{{a}}}rot')
            for attribute, field in [('lat', 'latitude'), ('lon', 'longitude'), ('rev', 'revolution')]:
                assert actual[key][field] == int(rotation.get(attribute)) / 60000
        native_shape = source.find(f'{{{p}}}spPr/{{{a}}}sp3d'); shape = model['shape3D']
        for attribute, field in [('z', 'depth'), ('extrusionH', 'extrusionHeight'), ('contourW', 'contourWidth')]:
            assert shape[field] == int(native_shape.get(attribute)) / 12700
        assert shape['material'] == native_shape.get('prstMaterial')
        for tag, field in [('bevelT', 'topBevel'), ('bevelB', 'bottomBevel')]:
            bevel = native_shape.find(f'{{{a}}}{tag}')
            assert shape[field]['width'] == int(bevel.get('w')) / 12700 and shape[field]['height'] == int(bevel.get('h')) / 12700
            assert shape[field].get('preset') == bevel.get('prst')
        assert shape['extrusionColor']['rgb']['_0'] == native_shape.find(f'{{{a}}}extrusionClr/{{{a}}}srgbClr').get('val')
        assert shape['contourColor']['theme']['_0'] == native_shape.find(f'{{{a}}}contourClr/{{{a}}}schemeClr').get('val')
    print(json.dumps(dict(file=path.name, fractionOperands=2, matrixCells=4, scene3D=1, shape3D=1), ensure_ascii=False))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli', type=Path, default=ROOT / '.build/release/swiftslides')
    args = parser.parse_args()
    for name in ['math-3d.pptx', 'math-3d-strict.pptx']:
        verify(ROOT / 'Tests/SwiftSlidesTests/Fixtures' / name, args.cli.resolve())

if __name__ == '__main__':
    main()
