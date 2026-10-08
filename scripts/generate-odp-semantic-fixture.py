#!/usr/bin/env python3
"""架空のMathML/高度図形ODPを標準ライブラリだけで決定論的に生成する。"""
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "Tests/SwiftSlidesTests/Fixtures"
OFFICE = "urn:oasis:names:tc:opendocument:xmlns:office:1.0"
DRAW = "urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"
STYLE = "urn:oasis:names:tc:opendocument:xmlns:style:1.0"
TEXT = "urn:oasis:names:tc:opendocument:xmlns:text:1.0"
SVG = "urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0"
MATH = "http://www.w3.org/1998/Math/MathML"
XLINK = "http://www.w3.org/1999/xlink"
MANIFEST = "urn:oasis:names:tc:opendocument:xmlns:manifest:1.0"
MIME = "application/vnd.oasis.opendocument.presentation"
bindings = f'xmlns:office="{OFFICE}" xmlns:draw="{DRAW}" xmlns:style="{STYLE}" xmlns:text="{TEXT}" xmlns:svg="{SVG}" xmlns:math="{MATH}" xmlns:xlink="{XLINK}" xmlns:u="urn:fictional:future"'
formula = '''<math:math><math:semantics><math:mrow>
<math:mfrac><math:mi>a</math:mi><math:mn>2</math:mn></math:mfrac><math:mo>+</math:mo>
<math:mroot><math:mi>x</math:mi><math:mn>3</math:mn></math:mroot>
<math:msubsup><math:mi>y</math:mi><math:mn>1</math:mn><math:mn>2</math:mn></math:msubsup>
<math:munderover><math:mo>∑</math:mo><math:mn>0</math:mn><math:mi>n</math:mi></math:munderover>
<math:mtable><math:mtr><math:mtd><math:mn>1</math:mn></math:mtd><math:mtd><math:mn>2</math:mn></math:mtd></math:mtr></math:mtable>
<math:mmultiscripts><math:mi>z</math:mi><math:none/><math:mn>2</math:mn><math:mprescripts/><math:mn>0</math:mn><math:none/></math:mmultiscripts>
<u:future flag="keep"/></math:mrow>
<math:annotation encoding="StarMath 5.0">NOT DISPLAYED</math:annotation>
<math:annotation-xml encoding="MathML-Content"><math:apply><math:divide/><math:ci>a</math:ci><math:cn>2</math:cn></math:apply></math:annotation-xml>
</math:semantics></math:math>'''
simple = '<math:math><math:mfrac><math:mi>b</math:mi><math:mn>4</math:mn></math:mfrac></math:math>'
position = 'svg:x="1cm" svg:y="2cm" svg:width="3cm" svg:height="2cm"'
path = 'M0,0 50,50 L$0 ?edge C0 1 2 3 4 5 Q6 7 8 9 A0 0 100 100 0 50 100 50 B0 0 100 100 0 50 100 50 T50 50 10 20 0 90 U50 50 10 20 0 90 V0 0 100 100 0 50 100 50 W0 0 100 100 0 50 100 50 X100 0 Y0 100 ZNFS'
content = f'''<office:document-content {bindings} office:version="1.3"><office:body><office:presentation>
<draw:page draw:name="Fictional semantic reading" draw:master-page-name="Master" xml:id="semantic-page">
<draw:custom-shape xml:id="enhanced" {position}><text:p>Fictional shape</text:p>
<draw:enhanced-geometry draw:type="fictional" svg:viewBox="-10 0 200 100" draw:modifiers="25 1e2" draw:mirror-horizontal="false" draw:mirror-vertical="true"
 draw:enhanced-path="{path}" draw:text-areas="0 0 $0 ?edge" draw:extrusion="true">
<draw:equation draw:name="edge" draw:formula="$1 / 2"/><draw:handle draw:handle-position="$0 ?edge"/><u:future flag="geometry"/>
</draw:enhanced-geometry></draw:custom-shape>
<draw:custom-shape xml:id="unknown-path" {position}><draw:enhanced-geometry draw:enhanced-path="M0 0 R1 2"/></draw:custom-shape>
<draw:custom-shape xml:id="empty-path" {position}><draw:enhanced-geometry draw:enhanced-path="" draw:modifiers=""/></draw:custom-shape>
<draw:frame xml:id="package-math" {position}><draw:object xlink:type="simple" xlink:href="./Formula"/><draw:image xlink:type="simple" xlink:href="Pictures/preview.png"/><svg:desc>Fictional preview</svg:desc></draw:frame>
<draw:g xml:id="formula-group"><draw:frame xml:id="inline-math" {position}><draw:object>{simple}</draw:object></draw:frame></draw:g>
<draw:frame xml:id="second-inline-math" {position}><draw:object>{simple}</draw:object></draw:frame>
<draw:frame xml:id="text-math" {position}><draw:text-box><text:p>Before<draw:frame {position}><draw:object>{simple}</draw:object></draw:frame>After</text:p></draw:text-box></draw:frame>
<draw:frame xml:id="external-math" {position}><draw:object xlink:type="simple" xlink:href="https://example.invalid/formula"/></draw:frame>
</draw:page></office:presentation></office:body></office:document-content>'''
styles = f'''<office:document-styles {bindings} office:version="1.3"><office:automatic-styles><style:page-layout style:name="Page"><style:page-layout-properties xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" fo:page-width="28cm" fo:page-height="21cm"/></style:page-layout></office:automatic-styles><office:master-styles><style:master-page style:name="Master" style:page-layout-name="Page"/></office:master-styles></office:document-styles>'''
embedded = formula.replace("<math:math>", f"<math:math {bindings}>", 1)
parts = {"mimetype": MIME.encode(), "content.xml": content.encode(), "styles.xml": styles.encode(), "Formula/content.xml": embedded.encode(), "Pictures/preview.png": (DEST / "fixture.png").read_bytes()}
entries = {"/": MIME, "content.xml": "text/xml", "styles.xml": "text/xml", "Formula/": "application/vnd.oasis.opendocument.formula", "Formula/content.xml": "text/xml", "Pictures/preview.png": "image/png"}
parts["META-INF/manifest.xml"] = (f'<manifest:manifest xmlns:manifest="{MANIFEST}" manifest:version="1.3">' + ''.join(f'<manifest:file-entry manifest:full-path="{path}" manifest:media-type="{mime}"/>' for path, mime in entries.items()) + '</manifest:manifest>').encode()
with zipfile.ZipFile(DEST / "semantic-reading.odp", "w") as package:
    for path, data in parts.items():
        info = zipfile.ZipInfo(path, (2026, 1, 1, 0, 0, 0)); info.compress_type = zipfile.ZIP_STORED if path == "mimetype" else zipfile.ZIP_DEFLATED
        package.writestr(info, data)
print("semantic-reading.odp")
