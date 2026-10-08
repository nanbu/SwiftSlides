#!/usr/bin/env python3
"""Generate fictional OMML and direct DrawingML 3D fixtures without Office APIs."""
from pathlib import Path
import xml.etree.ElementTree as ET
import zipfile
import posixpath

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'Tests/SwiftSlidesTests/Fixtures'
P = 'http://schemas.openxmlformats.org/presentationml/2006/main'
A = 'http://schemas.openxmlformats.org/drawingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
M = 'http://schemas.openxmlformats.org/officeDocument/2006/math'
A14 = 'http://schemas.microsoft.com/office/drawing/2010/main'
MC = 'http://schemas.openxmlformats.org/markup-compatibility/2006'

def run(text):
    return '<m:r><m:t>' + text + '</m:t></m:r>'

expression = ('<m:oMathPara><m:oMathParaPr><m:jc m:val="center"/></m:oMathParaPr><m:oMath>'
    '<m:f><m:fPr><m:type m:val="bar"/></m:fPr><m:num>' + run('a+b') + '</m:num><m:den>' + run('c') + '</m:den></m:f>'
    '<m:sSup><m:e>' + run('x') + '</m:e><m:sup>' + run('2') + '</m:sup></m:sSup>'
    '<m:m><m:mPr><m:baseJc m:val="center"/></m:mPr><m:mr><m:e>' + run('1') + '</m:e><m:e>' + run('2') + '</m:e></m:mr>'
    '<m:mr><m:e>' + run('3') + '</m:e><m:e>' + run('4') + '</m:e></m:mr></m:m><u:future flag="keep"/></m:oMath></m:oMathPara>')
body = ('<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>Before</a:t></a:r>'
    '<mc:AlternateContent><mc:Choice Requires="u"><a14:m><m:oMath>' + run('Rejected') + '</m:oMath></a14:m></mc:Choice>'
    '<mc:Choice Requires="a14"><a14:m>' + expression + '</a14:m></mc:Choice>'
    '<mc:Choice Requires="a14"><a14:m><m:oMath>' + run('Later') + '</m:oMath></a14:m></mc:Choice>'
    '<mc:Fallback><a:r><a:t>Fallback</a:t></a:r></mc:Fallback></mc:AlternateContent>'
    '<a:r><a:t>After</a:t></a:r></a:p><a:p><a14:m><m:oMath><m:rad><m:deg>' + run('3') + '</m:deg><m:e>' + run('y') + '</m:e></m:rad>'
    '<m:nary><m:naryPr><m:chr m:val="∑"/></m:naryPr><m:sub>' + run('i=1') + '</m:sub><m:sup>' + run('n') + '</m:sup><m:e>' + run('i') + '</m:e></m:nary>'
    '</m:oMath></a14:m></a:p></p:txBody>')
shape = ('<p:sp><p:nvSpPr><p:cNvPr id="900" name="Fictional equation and 3D"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr>'
    '<a:xfrm><a:off x="127000" y="254000"/><a:ext cx="2540000" cy="1270000"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom>'
    '<a:scene3d><a:camera prst="perspectiveFront" fov="5400000" zoom="150000"><a:rot lat="600000" lon="1200000" rev="0"/></a:camera>'
    '<a:lightRig rig="threePt" dir="t"><a:rot lat="0" lon="0" rev="1800000"/></a:lightRig>'
    '<a:backdrop><a:anchor x="0" y="0" z="12700"/><a:norm dx="0" dy="0" dz="1"/><a:up dx="0" dy="1" dz="0"/></a:backdrop>'
    '<a:extLst><a:ext uri="urn:fictional:scene"><u:future flag="scene"/></a:ext></a:extLst></a:scene3d>'
    '<a:sp3d z="-12700" extrusionH="25400" contourW="6350" prstMaterial="plastic"><a:bevelT w="12700" h="25400" prst="circle"/>'
    '<a:bevelB w="0" h="0"/><a:extrusionClr><a:srgbClr val="123456"/></a:extrusionClr><a:contourClr><a:schemeClr val="accent2"/></a:contourClr></a:sp3d>'
    '</p:spPr>' + body + '</p:sp>')

def parse(xml):
    return ET.fromstring(f'<wrapper xmlns:p="{P}" xmlns:a="{A}" xmlns:m="{M}" xmlns:a14="{A14}" xmlns:mc="{MC}" xmlns:u="urn:fictional:future">{xml}</wrapper>')[0]

with zipfile.ZipFile(OUT / 'python-pptx.pptx') as package:
    parts = {n: package.read(n) for n in package.namelist()}
slide = ET.fromstring(parts['ppt/slides/slide1.xml'])
tree = slide.find(f'{{{P}}}cSld/{{{P}}}spTree')
tree.append(parse(shape))
cell = slide.find(f'.//{{{A}}}tc')
cell_body = cell.find(f'{{{A}}}txBody')
cell.remove(cell_body)
cell.insert(0, parse(body.replace('p:txBody', 'a:txBody')))

# Keep Requires prefix bindings intact; ElementTree does not track QName attribute values.
for prefix, uri in [('p', P), ('a', A), ('r', R), ('m', M), ('a14', A14), ('mc', MC), ('u', 'urn:fictional:future')]:
    ET.register_namespace(prefix, uri)
parts['ppt/slides/slide1.xml'] = ET.tostring(slide)
notes_path = 'ppt/notesSlides/notesSlide1.xml'
notes = ET.fromstring(parts[notes_path])
for note_shape in notes.findall(f'.//{{{P}}}sp'):
    ph = note_shape.find(f'{{{P}}}nvSpPr/{{{P}}}nvPr/{{{P}}}ph')
    if ph is not None and ph.get('type') == 'body':
        old_body = note_shape.find(f'{{{P}}}txBody')
        note_shape.remove(old_body)
        note_shape.append(parse(body))
parts[notes_path] = ET.tostring(notes)
relationships = ET.fromstring(parts['ppt/slides/_rels/slide1.xml.rels'])
layout_target = next(n.get('Target') for n in relationships if n.get('Type') == R + '/slideLayout')
layout_path = posixpath.normpath(posixpath.join('ppt/slides', layout_target))
layout = ET.fromstring(parts[layout_path])
layout.find(f'{{{P}}}cSld/{{{P}}}spTree').append(parse(shape))
parts[layout_path] = ET.tostring(layout)

for name, strict in [('math-3d.pptx', False), ('math-3d-strict.pptx', True)]:
    with zipfile.ZipFile(OUT / name, 'w') as package:
        for path, data in sorted(parts.items()):
            if strict and (path.endswith('.xml') or path.endswith('.rels')):
                for old, new in [(P, 'http://purl.oclc.org/ooxml/presentationml/main'), (A, 'http://purl.oclc.org/ooxml/drawingml/main'),
                                 (R, 'http://purl.oclc.org/ooxml/officeDocument/relationships'), (M, 'http://purl.oclc.org/ooxml/officeDocument/math')]:
                    data = data.replace(old.encode(), new.encode())
            info = zipfile.ZipInfo(path, date_time=(2026, 1, 1, 0, 0, 0)); info.compress_type = zipfile.ZIP_DEFLATED
            package.writestr(info, data)
    print(name)
