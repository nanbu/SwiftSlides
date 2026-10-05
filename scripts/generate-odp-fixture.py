#!/usr/bin/env python3
"""Generate a fictional ODF 1.3 fixture with independent expected values."""
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_STORED, ZIP_DEFLATED
import json

ROOT = Path(__file__).resolve().parents[1]
NAMESPACES = {
 'office':'office', 'draw':'drawing', 'style':'style', 'text':'text', 'presentation':'presentation',
 'table':'table', 'svg':'svg-compatible', 'fo':'xsl-fo-compatible', 'manifest':'manifest',
}
NS = ' '.join('xmlns:%s="urn:oasis:names:tc:opendocument:xmlns:%s:1.0"' % x for x in NAMESPACES.items()) + ' xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:dc="http://purl.org/dc/elements/1.1/"'
MIME = 'application/vnd.oasis.opendocument.presentation'

def document(kind, body):
 return ('<?xml version="1.0" encoding="UTF-8"?><office:document-%s %s office:version="1.3">%s</office:document-%s>' % (kind,NS,body,kind)).encode()

def fixture_parts():
 styles = '''<office:styles>
 <style:default-style style:family="graphic"><style:graphic-properties draw:fill="solid" draw:fill-color="#FFFFFF"/></style:default-style>
 <style:style style:name="Base" style:family="graphic"><style:graphic-properties draw:fill-color="#123456"/><style:text-properties fo:font-size="18pt"/></style:style>
 <style:style style:name="Named" style:family="graphic" style:parent-style-name="Base"><style:graphic-properties draw:stroke="none"/></style:style>
 <style:style style:name="Para" style:family="paragraph"><style:text-properties fo:font-size="18pt"/></style:style>
 </office:styles><office:automatic-styles>
 <style:page-layout style:name="Layout"><style:page-layout-properties fo:page-width="33.86666666666667cm" fo:page-height="19.05cm" style:print-orientation="landscape"/></style:page-layout>
 <style:style style:name="MasterPage" style:family="drawing-page"><style:drawing-page-properties draw:fill="solid" draw:fill-color="#102030"/></style:style>
 <style:style style:name="Scoped" style:family="graphic"><style:graphic-properties draw:fill-color="#ABCDEF"/></style:style>
 </office:automatic-styles><office:master-styles><style:master-page style:name="Master" style:page-layout-name="Layout" draw:style-name="MasterPage"/></office:master-styles>'''
 automatic = '''<office:automatic-styles>
 <style:style style:name="Direct" style:family="graphic" style:parent-style-name="Named"><style:graphic-properties draw:fill="none"/></style:style>
 <style:style style:name="Scoped" style:family="graphic"><style:graphic-properties draw:fill-color="#FEDCBA"/></style:style>
 <style:style style:name="P1" style:family="paragraph" style:parent-style-name="Para"><style:paragraph-properties fo:text-align="center"/><style:text-properties fo:font-weight="bold"/></style:style>
 <style:style style:name="T1" style:family="text"><style:text-properties fo:font-size="24pt" fo:color="#AA0000"/></style:style>
 <style:style style:name="Col" style:family="table-column"><style:table-column-properties style:column-width="2cm"/></style:style>
 <style:style style:name="Row" style:family="table-row"><style:table-row-properties style:row-height="1cm"/></style:style>
 </office:automatic-styles>'''
 pages = '''<office:body><office:presentation>
 <draw:page draw:name="First" xml:id="page-one" draw:id="page-one" draw:master-page-name="Master">
 <draw:rect xml:id="rect-one" draw:id="rect-one" draw:style-name="Direct" svg:x="1cm" svg:y="2cm" svg:width="4cm" svg:height="3cm"><text:p text:style-name="P1">Hello<text:s text:c="2"/><text:span text:style-name="T1">世界</text:span><text:tab/><text:a xlink:type="simple" xlink:href="https://example.com/fictional">link</text:a><text:line-break/>End</text:p></draw:rect>
 <draw:g xml:id="group-one" draw:id="group-one"><draw:ellipse xml:id="ellipse-one" draw:id="ellipse-one" svg:x="10pt" svg:y="20pt" svg:width="50pt" svg:height="40pt"/></draw:g>
 <draw:frame xml:id="image-one" draw:id="image-one" svg:x="200pt" svg:y="100pt" svg:width="40pt" svg:height="30pt"><draw:image xlink:href="Pictures/fixture.png" xlink:type="simple" xlink:show="embed" xlink:actuate="onLoad"/><svg:desc>Fictional image</svg:desc></draw:frame>
 <draw:frame xml:id="table-one" draw:id="table-one" svg:x="300pt" svg:y="100pt" svg:width="120pt" svg:height="60pt"><table:table table:name="Fictional table"><table:table-column table:style-name="Col" table:number-columns-repeated="2"/><table:table-row table:style-name="Row"><table:table-cell><text:p>A</text:p></table:table-cell><table:table-cell><text:p>B</text:p></table:table-cell></table:table-row></table:table></draw:frame>
 <presentation:notes><draw:frame svg:x="0pt" svg:y="0pt" svg:width="100pt" svg:height="50pt"><draw:text-box><text:p>Fictional notes</text:p></draw:text-box></draw:frame></presentation:notes>
 </draw:page><draw:page draw:name="Second" xml:id="page-two" draw:id="page-two" draw:master-page-name="Master"><draw:frame xml:id="text-two" draw:id="text-two" svg:x="10pt" svg:y="10pt" svg:width="100pt" svg:height="50pt"><draw:text-box><text:p>Second page</text:p></draw:text-box></draw:frame></draw:page>
 </office:presentation></office:body>'''
 result = {'mimetype':MIME.encode(),'content.xml':document('content',automatic+pages),'styles.xml':document('styles',styles),'meta.xml':document('meta','<office:meta><dc:title>Fictional ODP</dc:title></office:meta>'),'Pictures/fixture.png':(ROOT/'Tests/SwiftSlidesTests/Fixtures/fixture.png').read_bytes()}
 manifest = '<manifest:manifest '+NS+' manifest:version="1.3"><manifest:file-entry manifest:full-path="/" manifest:media-type="'+MIME+'"/>'
 for name in result:
  if name == 'mimetype': continue
  manifest += '<manifest:file-entry manifest:full-path="'+name+'" manifest:media-type="'+('image/png' if name.endswith('.png') else 'text/xml')+'"/>'
 result['META-INF/manifest.xml']=(manifest+'</manifest:manifest>').encode()
 return result

def write_fixture(path):
 with ZipFile(path,'w') as z:
  for name,data in fixture_parts().items():
   info=ZipInfo(name,date_time=(2026,1,1,0,0,0));info.compress_type=ZIP_STORED if name=='mimetype' else ZIP_DEFLATED
   z.writestr(info,data)

if __name__=='__main__':
 destination=ROOT/'Tests/SwiftSlidesTests/Fixtures/styles.odp';write_fixture(destination)
 oracle={'format':'ODF 1.3','producer':'deterministic fictional fixture','slides':2,'size':[960,540],'title':'Fictional ODP','text':'Hello  世界\tlink\nEnd','notes':'Fictional notes','table':[['A','B']],'namedFill':'#123456','automaticFill':'none','masterFill':'#102030','directFontSize':24,'inheritedFontSize':18}
 destination.with_name('odp-oracle.json').write_text(json.dumps(oracle,ensure_ascii=False,indent=2)+'\n')
 print(destination.name)
