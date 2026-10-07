#!/usr/bin/env python3
"""Create fictional DrawingML projection fixtures, including a Strict namespace variant."""
from pathlib import Path
import xml.etree.ElementTree as ET
import zipfile
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'Tests/SwiftSlidesTests/Fixtures'
P = 'http://schemas.openxmlformats.org/presentationml/2006/main'
A = 'http://schemas.openxmlformats.org/drawingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
C = 'http://schemas.openxmlformats.org/drawingml/2006/chart'
D = 'http://schemas.openxmlformats.org/drawingml/2006/diagram'
DSP = 'http://schemas.microsoft.com/office/drawing/2008/diagram'
REL = 'http://schemas.openxmlformats.org/package/2006/relationships'
CT = 'http://schemas.openxmlformats.org/package/2006/content-types'
def document(tag, body, extra=''):
    return f'<{tag} xmlns:p="{P}" xmlns:a="{A}" xmlns:r="{R}" xmlns:c="{C}" xmlns:d="{D}" xmlns:dsp="{DSP}" {extra}>{body}</{tag}>'.encode()
def relationships(items):
    return ('<Relationships xmlns="'+REL+'">'+''.join(f'<Relationship Id="{i}" Type="{t if t.startswith("http") else R+"/"+t}" Target="{v}"/>' for i,t,v in items)+'</Relationships>').encode()
def header(prefix='p'):
    return f'<{prefix}:nvGrpSpPr><{prefix}:cNvPr id="1" name=""/><{prefix}:cNvGrpSpPr/><{prefix}:nvPr/></{prefix}:nvGrpSpPr><{prefix}:grpSpPr><a:xfrm><a:off x="12700" y="25400"/><a:ext cx="1270000" cy="1270000"/><a:chOff x="0" y="0"/><a:chExt cx="2540000" cy="2540000"/></a:xfrm></{prefix}:grpSpPr>'
def shape(prefix='p'):
    return f'''<{prefix}:sp><{prefix}:nvSpPr><{prefix}:cNvPr id="2" name="Values"/><{prefix}:cNvSpPr/><{prefix}:nvPr><p:ph type="body" idx="1"/></{prefix}:nvPr></{prefix}:nvSpPr><{prefix}:spPr><a:xfrm rot="5400000" flipH="1"><a:off x="127000" y="254000"/><a:ext cx="1270000" cy="635000"/></a:xfrm><a:custGeom><a:avLst/><a:gdLst/><a:pathLst><a:path w="100" h="50" fill="none" stroke="0"><a:moveTo><a:pt x="0" y="0"/></a:moveTo><a:lnTo><a:pt x="100" y="0"/></a:lnTo><a:quadBezTo><a:pt x="50" y="25"/><a:pt x="100" y="50"/></a:quadBezTo><a:cubicBezTo><a:pt x="10" y="20"/><a:pt x="30" y="40"/><a:pt x="0" y="50"/></a:cubicBezTo><a:close/></a:path></a:pathLst></a:custGeom><a:solidFill><a:schemeClr val="accent1"><a:alpha val="50000"/><a:alphaOff val="20000"/><a:alphaMod val="50000"/></a:schemeClr></a:solidFill><a:ln w="12700"><a:solidFill><a:srgbClr val="FF0000"><a:alpha val="0"/></a:srgbClr></a:solidFill></a:ln><a:effectLst><a:outerShdw dist="25400" dir="5400000" blurRad="12700" sx="100000" sy="50000" kx="0" ky="0" algn="ctr" rotWithShape="0"><a:srgbClr val="000000"><a:alpha val="50000"/></a:srgbClr></a:outerShdw></a:effectLst></{prefix}:spPr><{prefix}:style><a:effectRef idx="1"><a:schemeClr val="accent1"/></a:effectRef></{prefix}:style><{prefix}:txBody><a:bodyPr/><a:lstStyle><a:lvl1pPr><a:lnSpc><a:spcPct val="100000"/></a:lnSpc><a:spcBef><a:spcPct val="0"/></a:spcBef></a:lvl1pPr></a:lstStyle><a:p><a:pPr><a:lnSpc><a:spcPts val="1800"/></a:lnSpc><a:spcBef><a:spcPct val="50000"/></a:spcBef><a:spcAft><a:spcPts val="0"/></a:spcAft></a:pPr><a:r><a:rPr sz="1200"/><a:t>Before</a:t></a:r><a:fld id="{{11111111-1111-1111-1111-111111111111}}" type="slidenum"><a:rPr sz="2400" b="0"/><a:pPr><a:lnSpc><a:spcPts val="2000"/></a:lnSpc></a:pPr><a:t>7</a:t></a:fld><a:r><a:rPr/><a:t>After</a:t></a:r></a:p></{prefix}:txBody></{prefix}:sp>'''
def graphic(i, data):
    return f'<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="{i}" name="Graphic {i}"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr><p:xfrm><a:off x="0" y="0"/><a:ext cx="1270000" cy="1270000"/></p:xfrm><a:graphic><a:graphicData>{data}</a:graphicData></a:graphic></p:graphicFrame>'
with zipfile.ZipFile(OUT/'python-pptx.pptx') as z:
    parts = {n:z.read(n) for n in z.namelist()}
baseline_parts = parts.copy()
chart_graphic = graphic(3, '<c:chart r:id="chart"/>')
diagram_graphic = graphic(4, '<d:relIds r:dm="data" r:lo="layout" r:qs="style" r:cs="colors"/>')
parts['ppt/slides/slide1.xml'] = document('p:sld',f'<p:cSld name="Synthetic projection"><p:bg><p:bgPr><a:solidFill><a:srgbClr val="FFFFFF"><a:alpha val="50000"/></a:srgbClr></a:solidFill></p:bgPr></p:bg><p:spTree>{header()}{shape()}{chart_graphic}{diagram_graphic}</p:spTree></p:cSld><p:clrMapOvr><a:overrideClrMapping accent1="accent2"/></p:clrMapOvr>', 'showMasterSp="0"')
parts['ppt/slides/_rels/slide1.xml.rels'] = relationships([('masterLayout','slideLayout','../slideLayouts/slideLayout1.xml'),('chart','chart','../charts/readingChart.xml'),('data','diagramData','../diagrams/data.xml'),('layout','diagramLayout','../diagrams/layout.xml'),('style','diagramQuickStyle','../diagrams/style.xml'),('colors','diagramColors','../diagrams/colors.xml')])
chart = '<c:chart><c:title><c:tx><c:rich><a:p><a:r><a:t>Fictional chart</a:t></a:r></a:p></c:rich></c:tx></c:title><c:plotArea><c:barChart><c:barDir val="col"/><c:grouping val="clustered"/><c:ser><c:idx val="2"/><c:order val="0"/><c:tx><c:v>Series</c:v></c:tx><c:cat><c:strRef><c:f>Sheet1!A1:A3</c:f><c:strCache><c:ptCount val="3"/><c:pt idx="0"><c:v>A</c:v></c:pt><c:pt idx="2"><c:v>C</c:v></c:pt></c:strCache></c:strRef></c:cat><c:val><c:numLit><c:formatCode>0.0</c:formatCode><c:ptCount val="3"/><c:pt idx="0"><c:v>10</c:v></c:pt><c:pt idx="2"><c:v>30</c:v></c:pt></c:numLit></c:val></c:ser><c:axId val="100"/><c:axId val="200"/></c:barChart><c:catAx><c:axId val="100"/><c:crossAx val="200"/><c:axPos val="b"/></c:catAx><c:valAx><c:axId val="200"/><c:scaling><c:min val="0"/><c:max val="40"/></c:scaling><c:crossAx val="100"/><c:axPos val="l"/><c:numFmt formatCode="0.0"/></c:valAx></c:plotArea><c:legend><c:legendPos val="r"/></c:legend></c:chart>'
parts['ppt/charts/readingChart.xml'] = document('c:chartSpace',chart)
parts['ppt/diagrams/data.xml'] = document('d:dataModel','<d:ptLst><d:pt modelId="node"><d:t><a:p><a:r><a:t>Data text</a:t></a:r></a:p></d:t></d:pt></d:ptLst><d:extLst><a:ext uri="synthetic"><dsp:dataModelExt relId="drawing"/></a:ext></d:extLst>')
parts['ppt/diagrams/_rels/data.xml.rels'] = relationships([('drawing','http://schemas.microsoft.com/office/2007/relationships/diagramDrawing','drawing.xml')])
parts['ppt/diagrams/drawing.xml'] = document('dsp:drawing',f'<dsp:spTree>{header("dsp")}{shape("dsp")}</dsp:spTree>')
for name,tag in [('layout','layoutDef'),('style','styleDef'),('colors','colorsDef')]:
    parts[f'ppt/diagrams/{name}.xml'] = document('d:'+tag,'')
# Reuse a fictional table and image in the inherited source part, with their part-relative relationships.
old_slide = ET.fromstring(baseline_parts['ppt/slides/slide1.xml'])
old_tree = old_slide.find(f'{{{P}}}cSld/{{{P}}}spTree')
table = next(e for e in old_tree if e.tag == f'{{{P}}}graphicFrame')
image = next(e for e in old_tree if e.tag == f'{{{P}}}pic')
parts['ppt/slideLayouts/slideLayout1.xml'] = document('p:sldLayout',f'<p:cSld name="Synthetic layout"><p:spTree>{header()}{shape()}{ET.tostring(table,encoding="unicode")}{ET.tostring(image,encoding="unicode")}</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>', 'showMasterSp="0" type="body"')
image_id = next(e for e in image.iter() if e.tag == f'{{{A}}}blip').attrib[f'{{{R}}}embed']
old_rels = ET.fromstring(baseline_parts['ppt/slides/_rels/slide1.xml.rels'])
image_target = next(e.attrib['Target'] for e in old_rels if e.attrib['Id'] == image_id)
parts['ppt/slideLayouts/_rels/slideLayout1.xml.rels'] = relationships([('master','slideMaster','../slideMasters/slideMaster1.xml'),(image_id,'image',image_target)])
master = ET.fromstring(parts['ppt/slideMasters/slideMaster1.xml'])
master.find(f'{{{P}}}cSld/{{{P}}}spTree').clear()
for e in ET.fromstring(document('p:spTree',header()+shape())): master.find(f'{{{P}}}cSld/{{{P}}}spTree').append(e)
master.find(f'{{{P}}}txStyles').clear()
for name in ['titleStyle','bodyStyle','otherStyle']:
    master.find(f'{{{P}}}txStyles').append(ET.fromstring(document('p:'+name,'<a:lvl1pPr><a:lnSpc><a:spcPts val="2200"/></a:lnSpc><a:spcAft><a:spcPct val="100000"/></a:spcAft></a:lvl1pPr>')))
parts['ppt/slideMasters/slideMaster1.xml'] = ET.tostring(master)
main = ET.fromstring(parts['ppt/presentation.xml']); main.set('firstSlideNum','7')
style = main.find(f'{{{P}}}defaultTextStyle'); style.clear()
style.append(ET.fromstring(document('a:lvl1pPr','<a:lnSpc><a:spcPct val="120000"/></a:lnSpc>')))
parts['ppt/presentation.xml'] = ET.tostring(main)
content_types = ET.fromstring(parts['[Content_Types].xml'])
for path,kind in [('ppt/charts/readingChart.xml','chart'),('ppt/diagrams/data.xml','diagramData'),('ppt/diagrams/layout.xml','diagramLayout'),('ppt/diagrams/style.xml','diagramStyle'),('ppt/diagrams/colors.xml','diagramColors'),('ppt/diagrams/drawing.xml','diagramDrawing')]:
    ET.SubElement(content_types,'{'+CT+'}Override',PartName='/'+path,ContentType='application/vnd.openxmlformats-officedocument.drawingml.'+kind+'+xml')
parts['[Content_Types].xml'] = ET.tostring(content_types)
for name,strict in [('reading-models.pptx',False),('reading-models-strict.pptx',True)]:
    with zipfile.ZipFile(OUT/name,'w',compression=zipfile.ZIP_DEFLATED) as z:
        for path,bytes_ in sorted(parts.items()):
            if strict and (path.endswith('.xml') or path.endswith('.rels')):
                for before,after in [(P,'http://purl.oclc.org/ooxml/presentationml/main'),(A,'http://purl.oclc.org/ooxml/drawingml/main'),(R,'http://purl.oclc.org/ooxml/officeDocument/relationships'),(C,'http://purl.oclc.org/ooxml/drawingml/chart'),(D,'http://purl.oclc.org/ooxml/drawingml/diagram')]: bytes_=bytes_.replace(before.encode(),after.encode())
            info=zipfile.ZipInfo(path,date_time=(2026,1,1,0,0,0)); info.compress_type=zipfile.ZIP_DEFLATED; z.writestr(info,bytes_)
    print(name)
