#!/usr/bin/env python3
"""公開CLIの読取値をPython標準XML parserで照合する。描画・再生の検査ではない。"""
import argparse
import hashlib
import json
from pathlib import Path
import posixpath
import subprocess
from urllib.parse import unquote
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def percentage(raw):
    return float(raw[:-1])/100 if raw.endswith('%') else float(raw)/100000

A = 'http://schemas.openxmlformats.org/drawingml/2006/main'
P = 'http://schemas.openxmlformats.org/presentationml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
P14 = 'http://schemas.microsoft.com/office/powerpoint/2010/main'


def verify(path, cli):
    snapshot = json.loads(subprocess.check_output([str(cli), 'read-json', str(path)], text=True))
    counts = dict(gradient=0, pattern=0, picture=0, crop=0, border=0, transition=0, timing=0, media=0, comments=0)
    with zipfile.ZipFile(path) as archive:
        main = ET.fromstring(archive.read('ppt/presentation.xml'))
        p = main.tag.split('}')[0].lstrip('{')
        assert p in [P,'http://purl.oclc.org/ooxml/presentationml/main']
        a, r = (('http://purl.oclc.org/ooxml/drawingml/main','http://purl.oclc.org/ooxml/officeDocument/relationships') if p != P else (A,R))
        def relationships(part):
            directory, name = posixpath.split(part)
            relpath = posixpath.join(directory, '_rels', name + '.rels')
            if relpath not in archive.namelist(): return {}
            return {rel.attrib['Id']: rel.attrib for rel in ET.fromstring(archive.read(relpath))}

        def reference(part, rid, actual):
            rel = relationships(part)[rid]
            assert actual['relationshipID'] == rid
            if rel.get('TargetMode') == 'External':
                assert actual.get('path') is None and actual['externalTarget'] == rel['Target']
            else:
                target = unquote(rel['Target'])
                target = target.lstrip('/') if target.startswith('/') else posixpath.normpath(posixpath.join(posixpath.dirname(part), target))
                assert actual.get('externalTarget') is None and actual['path'] == target

        def crop(source, actual):
            if source is None: assert actual is None; return
            assert actual is not None
            for key, attr in [('top','t'),('left','l'),('bottom','b'),('right','r')]:
                assert actual.get(key) == (percentage(source.attrib[attr]) if attr in source.attrib else None)
            counts['crop'] += 1

        def fill(source, actual, part):
            if source is None: return
            gradient, pattern, picture = (source.find(f'{{{a}}}{name}') for name in ['gradFill','pattFill','blipFill'])
            if gradient is not None:
                value = actual['gradient']['_0']
                stops = gradient.findall(f'{{{a}}}gsLst/{{{a}}}gs')
                assert [s['position'] for s in value['stops']] == [percentage(s.attrib['pos']) for s in stops]
                linear = gradient.find(f'{{{a}}}lin')
                assert value.get('angle') == (float(linear.attrib['ang'])/60000 if linear is not None and 'ang' in linear.attrib else None)
                for source_stop, stop in zip(stops, value['stops']):
                    direct = source_stop.find(f'{{{a}}}srgbClr')
                    if direct is not None and len(direct) == 0: assert stop['color']['rgb']['_0'] == direct.attrib['val']
                counts['gradient'] += 1
            if pattern is not None:
                assert actual['pattern']['_0'].get('preset') == pattern.get('prst')
                counts['pattern'] += 1
            if picture is not None:
                value = actual['picture']['_0']; assert value['isTiled'] == (picture.find(f'{{{a}}}tile') is not None)
                blip = picture.find(f'{{{a}}}blip')
                rid = None if blip is None else blip.get(f'{{{r}}}embed') or blip.get(f'{{{r}}}link')
                if rid is not None: reference(part,rid,value['image'])
                else: assert value.get('image') is None
                crop(picture.find(f'{{{a}}}srcRect'), value.get('crop')); counts['picture'] += 1

        rels = relationships('ppt/presentation.xml')
        slide_parts = [posixpath.normpath(posixpath.join('ppt', unquote(rels[n.attrib[f'{{{r}}}id']]['Target']))).lstrip('/') for n in main.findall(f'{{{p}}}sldIdLst/{{{p}}}sldId')]
        assert len(slide_parts) == len(snapshot['slides']) and slide_parts
        for part, slide in zip(slide_parts,snapshot['slides']):
            root = ET.fromstring(archive.read(part))
            fill(root.find(f'{{{p}}}cSld/{{{p}}}bg/{{{p}}}bgPr'),slide.get('background'),part)
            xml_elements = root.find(f'{{{p}}}cSld/{{{p}}}spTree')
            by_id = {}
            def index(elements):
                for element in elements:
                    by_id[element['id']] = element; index(element.get('children',[]))
            index(slide['elements'])
            for node in xml_elements.iter():
                if node.tag not in {f'{{{p}}}{name}' for name in ['sp','cxnSp','pic','graphicFrame','grpSp']}: continue
                cnv = node.find(f'.//{{{p}}}cNvPr')
                actual = by_id[cnv.attrib['id']]
                fill(node.find(f'{{{p}}}spPr'),actual.get('fill'),part)
                if node.tag == f'{{{p}}}pic': crop(node.find(f'{{{p}}}blipFill/{{{a}}}srcRect'), actual.get('image',{}).get('crop'))
                nonvisual = node.find(f'{{{p}}}' + dict(sp='nvSpPr',cxnSp='nvCxnSpPr',pic='nvPicPr',graphicFrame='nvGraphicFramePr',grpSp='nvGrpSpPr')[node.tag.split('}')[-1]])
                media_nodes = [n for n in ([] if nonvisual is None else nonvisual.iter()) if n.tag in {f'{{{a}}}audioFile',f'{{{a}}}wavAudioFile',f'{{{a}}}videoFile',f'{{{a}}}quickTimeFile',f'{{{P14}}}media'}]
                assert len(media_nodes) == len(actual.get('media',[]))
                for native, media in zip(media_nodes,actual.get('media',[])):
                    reference(part,native.get(f'{{{r}}}embed') or native.attrib[f'{{{r}}}link'],media['reference']); counts['media'] += 1
                table = node.find(f'{{{a}}}graphic/{{{a}}}graphicData/{{{a}}}tbl')
                if table is not None:
                    edges = dict(lnL='left',lnR='right',lnT='top',lnB='bottom',lnTlToBr='topLeftToBottomRight',lnBlToTr='bottomLeftToTopRight')
                    assert len(table.findall(f'{{{a}}}tr')) == len(actual['table']['rows'])
                    for xml_row, row in zip(table.findall(f'{{{a}}}tr'), actual['table']['rows']):
                        assert len(xml_row.findall(f'{{{a}}}tc')) == len(row)
                        for xml_cell, cell in zip(xml_row.findall(f'{{{a}}}tc'),row):
                            properties = xml_cell.find(f'{{{a}}}tcPr')
                            native = [] if properties is None else [n for n in properties if n.tag.removeprefix('{'+a+'}') in edges]
                            borders = cell.get('borders',[]); assert len(native) == len(borders)
                            border_by_edge = {b['edge']: b for b in borders}
                            for n in native:
                                b = border_by_edge[edges[n.tag.split('}')[-1]]]
                                none = n.find(f'{{{a}}}noFill') is not None
                                assert b['isExplicitlyNone'] == none
                                if none: assert b.get('stroke') is None
                                elif 'w' in n.attrib: assert b['stroke']['width'] == float(n.attrib['w'])/12700
                                counts['border'] += 1
            transition = root.find(f'{{{p}}}transition')
            if transition is not None:
                value = slide['transition']; counts['transition'] += 1
                for key, attr in [('advanceAfterMilliseconds','advTm'),('durationMilliseconds','{'+P14+'}dur')]: assert value.get(key) == (int(transition.attrib[attr]) if attr in transition.attrib else None)
                assert value.get('speed') == transition.get('spd')
                if 'advClick' in transition.attrib: assert value['advancesOnClick'] == (transition.attrib['advClick'] in ['1','true'])
                effects = [n for n in transition if n.tag not in {f'{{{p}}}sndAc',f'{{{p}}}extLst'}]
                assert value.get('effect') == (effects[0].tag.split('}')[-1] if effects else None)
            timing = root.find(f'{{{p}}}timing')
            if timing is not None:
                def compare_timing(native, model):
                    namespace, name = native.tag[1:].split('}')
                    assert model['namespace'] == namespace and model['name'] == name
                    attributes = {(k[1:].replace('}','|',1) if k.startswith('{') else k): v for k,v in native.attrib.items()}
                    assert model['attributes'] == attributes and len(native) == len(model['children'])
                    direct_text = (native.text or '') + ''.join(n.tail or '' for n in native)
                    assert model.get('text') == (direct_text or None)
                    for child, projected in zip(native,model['children']): compare_timing(child,projected)
                compare_timing(timing,slide['timing']['root'])
                assert slide['timing']['targetElementIDs'] == [n.attrib['spid'] for n in timing.iter(f'{{{p}}}spTgt')]; counts['timing'] += 1
            native_comments = []
            for rel in relationships(part).values():
                if rel['Type'] != r + '/comments': continue
                target = posixpath.normpath(posixpath.join(posixpath.dirname(part),rel['Target']))
                native_comments.extend(n.find(f'{{{p}}}text').text or '' for n in ET.fromstring(archive.read(target)).findall(f'{{{p}}}cm'))
            assert [n['text'] for n in slide.get('comments',[])] == native_comments; counts['comments'] += len(native_comments)
    print(json.dumps(dict(file=path.name,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),checked=counts),ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('paths', type=Path, nargs='*')
    parser.add_argument('--cli',type=Path,default=ROOT/'.build/release/swiftslides')
    args = parser.parse_args()
    paths = args.paths or [ROOT/'Tests/SwiftSlidesTests/Fixtures'/n for n in ['advanced-reading.pptx','advanced-reading-strict.pptx','libreoffice-advanced.pptx']]
    for path in paths: verify(path.resolve(),args.cli.resolve())


if __name__ == '__main__': main()
