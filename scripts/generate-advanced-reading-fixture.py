#!/usr/bin/env python3
"""架空の読取fixtureを再現可能に生成する。アプリ出力の検証とは区別する。"""
import copy
import io
from pathlib import Path
import wave
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'Tests/SwiftSlidesTests/Fixtures'
P = 'http://schemas.openxmlformats.org/presentationml/2006/main'
A = 'http://schemas.openxmlformats.org/drawingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
P14 = 'http://schemas.microsoft.com/office/powerpoint/2010/main'
REL = 'http://schemas.openxmlformats.org/package/2006/relationships'
CT = 'http://schemas.openxmlformats.org/package/2006/content-types'
for prefix, uri in [('p', P), ('a', A), ('r', R), ('p14', P14)]: ET.register_namespace(prefix, uri)

def fragment(xml):
    return ET.fromstring(f'<root xmlns:p="{P}" xmlns:a="{A}" xmlns:r="{R}" xmlns:p14="{P14}">{xml}</root>')[0]

def write(name, parts, strict=False):
    with zipfile.ZipFile(OUT / name, 'w') as archive:
        for path, data in sorted(parts.items()):
            if strict and (path.endswith('.xml') or path.endswith('.rels')):
                for before, after in [(P, 'http://purl.oclc.org/ooxml/presentationml/main'), (A, 'http://purl.oclc.org/ooxml/drawingml/main'), (R, 'http://purl.oclc.org/ooxml/officeDocument/relationships')]:
                    data = data.replace(before.encode(), after.encode())
            info = zipfile.ZipInfo(path, date_time=(2026, 1, 1, 0, 0, 0)); info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, data)

def main():
    with zipfile.ZipFile(OUT / 'python-pptx.pptx') as archive: parts = {n: archive.read(n) for n in archive.namelist()}
    slide = ET.fromstring(parts['ppt/slides/slide1.xml']); tree = slide.find(f'{{{P}}}cSld/{{{P}}}spTree')
    base = next(n for n in tree if n.tag == f'{{{P}}}sp')
    fills = [
        '<a:gradFill flip="x" rotWithShape="0"><a:gsLst><a:gs pos="0"><a:srgbClr val="FF0000"/></a:gs><a:gs pos="75000"><a:schemeClr val="accent2"><a:alpha val="40000"/></a:schemeClr></a:gs><a:gs pos="100000"><a:srgbClr val="0000FF"/></a:gs></a:gsLst><a:lin ang="5400000" scaled="0"/></a:gradFill>',
        '<a:pattFill prst="pct20"><a:fgClr><a:srgbClr val="123456"/></a:fgClr><a:bgClr><a:schemeClr val="bg1"/></a:bgClr></a:pattFill>',
        '<a:blipFill rotWithShape="1"><a:blip r:embed="advancedImage"/><a:srcRect l="10000" t="-5000"/><a:tile tx="12700" ty="25400" sx="50000" sy="50000"/></a:blipFill>'
    ]
    for i, fill in enumerate(fills, 30):
        shape = copy.deepcopy(base); shape.find(f'{{{P}}}nvSpPr/{{{P}}}cNvPr').attrib.update(id=str(i), name=['Gradient', 'Pattern', 'Picture fill'][i-30])
        props = shape.find(f'{{{P}}}spPr')
        for child in list(props):
            if child.tag in {f'{{{A}}}{n}' for n in ['noFill', 'solidFill', 'gradFill', 'pattFill', 'blipFill']}: props.remove(child)
        props.append(fragment(fill))
        order = ['xfrm','prstGeom','custGeom','noFill','solidFill','gradFill','blipFill','pattFill','grpFill','ln','effectLst','effectDag','scene3d','sp3d','extLst']
        props[:] = sorted(props, key=lambda n: order.index(n.tag.split('}')[-1]) if n.tag.split('}')[-1] in order else len(order))
        shape.find(f'{{{P}}}txBody').find(f'.//{{{A}}}t').text = 'Fictional advanced reading'
        tree.append(shape)
    image = next(n for n in tree if n.tag == f'{{{P}}}pic')
    image.find(f'{{{P}}}blipFill').insert(1, fragment('<a:srcRect l="12500" r="25000" t="-1000" b="0"/>'))
    media = copy.deepcopy(image); media.find(f'{{{P}}}nvPicPr/{{{P}}}cNvPr').attrib.update(id='33', name='Audio poster')
    nv = media.find(f'{{{P}}}nvPicPr/{{{P}}}nvPr'); nv.append(fragment('<a:audioFile r:link="advancedAudio"/>'))
    nv.append(fragment('<p:extLst><p:ext uri="{DAA4B4D4-AFB6-43A0-9A19-197AE4BC9838}"><p14:media r:embed="advancedMedia"/></p:ext></p:extLst>')); tree.append(media)
    table = next(n for n in tree if n.tag == f'{{{P}}}graphicFrame').find(f'.//{{{A}}}tbl')
    tcpr = table.find(f'{{{A}}}tr/{{{A}}}tc/{{{A}}}tcPr')
    for child in list(tcpr):
        if child.tag.startswith(f'{{{A}}}ln'): tcpr.remove(child)
    for xml in ['<a:lnL w="12700"><a:solidFill><a:srgbClr val="AA0000"/></a:solidFill></a:lnL>', '<a:lnR w="25400"><a:solidFill><a:srgbClr val="00AA00"/></a:solidFill></a:lnR>', '<a:lnT><a:noFill/></a:lnT>', '<a:lnB w="38100"><a:solidFill><a:srgbClr val="0000AA"/></a:solidFill></a:lnB>', '<a:lnTlToBr w="12700"><a:solidFill><a:srgbClr val="123456"/></a:solidFill></a:lnTlToBr>']:
        tcpr.append(fragment(xml))
    order = ['lnL','lnR','lnT','lnB','lnTlToBr','lnBlToTr','cell3D','noFill','solidFill','gradFill','blipFill','pattFill','grpFill','headers','extLst']
    tcpr[:] = sorted(tcpr, key=lambda n: order.index(n.tag.split('}')[-1]) if n.tag.split('}')[-1] in order else len(order))
    slide.append(fragment('<p:transition spd="slow" advClick="0" advTm="1500" p14:dur="750"><p:push dir="l"/></p:transition>'))
    slide.append(fragment('<p:timing><p:tnLst><p:par><p:cTn id="1" dur="indefinite" restart="never" nodeType="tmRoot"><p:childTnLst><p:par><p:cTn id="2" dur="500" fill="hold"><p:stCondLst><p:cond evt="onClick" delay="0"/></p:stCondLst><p:childTnLst><p:animEffect transition="in" filter="fade"><p:cBhvr><p:cTn id="3" dur="500"/><p:tgtEl><p:spTgt spid="30"><p:txEl><p:pRg st="0" end="0"/></p:txEl></p:spTgt></p:tgtEl></p:cBhvr></p:animEffect></p:childTnLst></p:cTn></p:par></p:childTnLst></p:cTn></p:par></p:tnLst><p:bldLst><p:bldP spid="30" grpId="0" build="p"/></p:bldLst></p:timing>'))
    parts['ppt/slides/slide1.xml'] = ET.tostring(slide)
    ET.register_namespace('', REL)
    rels = ET.fromstring(parts['ppt/slides/_rels/slide1.xml.rels'])
    for id, kind, target in [('advancedImage', R+'/image', '../media/image1.png'), ('advancedAudio', R+'/audio', '../media/fictional.wav'), ('advancedMedia', 'http://schemas.microsoft.com/office/2007/relationships/media', '../media/fictional.wav'), ('advancedComments', R+'/comments', '../comments/advanced.xml')]:
        ET.SubElement(rels, f'{{{REL}}}Relationship', Id=id, Type=kind, Target=target)
    parts['ppt/slides/_rels/slide1.xml.rels'] = ET.tostring(rels)
    main_rels = ET.fromstring(parts['ppt/_rels/presentation.xml.rels'])
    ET.SubElement(main_rels, f'{{{REL}}}Relationship', Id='advancedAuthors', Type=R+'/commentAuthors', Target='commentAuthors.xml')
    parts['ppt/_rels/presentation.xml.rels'] = ET.tostring(main_rels)
    parts['ppt/commentAuthors.xml'] = ET.tostring(fragment('<p:cmAuthorLst><p:cmAuthor id="7" name="Fictional Reviewer" initials="FR" lastIdx="1" clrIdx="0"/></p:cmAuthorLst>'))
    parts['ppt/comments/advanced.xml'] = ET.tostring(fragment('<p:cmLst><p:cm authorId="7" dt="2026-01-01T12:00:00Z" idx="1"><p:pos x="800" y="400"/><p:text>Fictional review comment</p:text></p:cm></p:cmLst>'))
    audio = io.BytesIO()
    with wave.open(audio, 'wb') as out: out.setnchannels(1); out.setsampwidth(2); out.setframerate(8000); out.writeframes(b'\0\0'*800)
    parts['ppt/media/fictional.wav'] = audio.getvalue()
    ET.register_namespace('', CT)
    types = ET.fromstring(parts['[Content_Types].xml'])
    ET.SubElement(types, f'{{{CT}}}Default', Extension='wav', ContentType='audio/wav')
    for path, kind in [('ppt/commentAuthors.xml','commentAuthors'),('ppt/comments/advanced.xml','comments')]:
        ET.SubElement(types, f'{{{CT}}}Override', PartName='/'+path, ContentType=f'application/vnd.openxmlformats-officedocument.presentationml.{kind}+xml')
    parts['[Content_Types].xml'] = ET.tostring(types)
    write('advanced-reading.pptx', parts); write('advanced-reading-strict.pptx', parts, True)
    print('advanced-reading.pptx / advanced-reading-strict.pptx')

if __name__ == '__main__': main()
