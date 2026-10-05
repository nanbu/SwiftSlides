#!/usr/bin/env python3
"""ODP架空fixtureを公開consumer、独立XML読取、任意のschema/LibreOfficeで照合する。"""
import argparse,json,subprocess,tempfile,xml.etree.ElementTree as ET,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SOURCE=r'''
import Foundation
import SlideCore
import SlideODP
func check(_ url:URL) throws {
 let set=CodecSet([.odp]);let p=try set.read(contentsOf:url).presentation
 let reader=try SlideReader(contentsOf:url,codecs:set)
 precondition(reader.summary.slideCount==p.slides.count)
 for descriptor in reader.slideDescriptors {
  let s=try reader.slide(id:descriptor.id).slide;precondition(s==p.slides[descriptor.index])
 }
 let info:[String:Any]=["slides":p.slides.count,"width":p.size.width,"height":p.size.height,"title":p.metadata.title ?? "","text":p.plainText,"notes":p.slides.map { $0.notes?.plainText ?? "" },"warnings":p.readWarnings.count]
 print(String(decoding:try JSONSerialization.data(withJSONObject:info,options:[.sortedKeys]),as:UTF8.self))
}
try check(URL(filePath:CommandLine.arguments[1]))
'''

def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--schema-rng',type=Path);parser.add_argument('--manifest-rng',type=Path);parser.add_argument('--libreoffice',action='store_true');args=parser.parse_args()
 schemas={}
 if args.schema_rng:
  from lxml import etree
  schemas['document']=etree.RelaxNG(etree.parse(str(args.schema_rng)))
  if args.manifest_rng:schemas['manifest']=etree.RelaxNG(etree.parse(str(args.manifest_rng)))
 with tempfile.TemporaryDirectory(prefix='swiftslides-odp-consumer-') as folder:
  p=Path(folder);(p/'Sources/Verify').mkdir(parents=True)
  (p/'Package.swift').write_text('// swift-tools-version: 6.4\nimport PackageDescription\nlet package=Package(name:"Verify",platforms:[.macOS(.v14)],dependencies:[.package(path:'+json.dumps(str(ROOT))+')],targets:[.executableTarget(name:"Verify",dependencies:[.product(name:"SlideCore",package:"SwiftSlides"),.product(name:"SlideODP",package:"SwiftSlides")])],swiftLanguageModes:[.v6])')
  (p/'Sources/Verify/main.swift').write_text(SOURCE)
  subprocess.run(['swift','build','--disable-sandbox','--package-path',str(p)],check=True)
  binary=subprocess.check_output(['swift','build','--package-path',str(p),'--show-bin-path'],text=True).strip()+'/Verify'
  fixtures=ROOT/'Tests/SwiftSlidesTests/Fixtures'
  cases=[fixtures/'styles.odp',fixtures/'libreoffice.odp']
  if args.libreoffice:
   import shutil,sys
   soffice='/Applications/LibreOffice.app/Contents/MacOS/soffice' if sys.platform=='darwin' else shutil.which('libreoffice')
   if not soffice or not Path(soffice).exists():raise RuntimeError('requested LibreOffice oracle is unavailable')
   out=p/'roundtrip';out.mkdir()
   subprocess.run([str(soffice),'-env:UserInstallation='+str((p/'profile').as_uri()),'--headless','--convert-to','odp','--outdir',str(out),str(fixtures/'styles.odp')],check=True)
   generated=out/'styles.odp'
   if not generated.exists():raise RuntimeError('LibreOffice did not save the requested ODP')
   cases.append(generated)
  for source in cases:
   result=json.loads(subprocess.check_output([binary,str(source)],text=True))
   with zipfile.ZipFile(source) as z:
    content=ET.fromstring(z.read('content.xml'));office='{urn:oasis:names:tc:opendocument:xmlns:office:1.0}';draw='{urn:oasis:names:tc:opendocument:xmlns:drawing:1.0}'
    pages=content.find(office+'body').find(office+'presentation').findall(draw+'page')
    assert result['slides']==len(pages)==2
    if source.name=='libreoffice.odp':assert '売上成長' in result['text'] and '架空データ' in result['notes'][0]
    else:assert 'Hello  世界\tlink\nEnd' in result['text'] and result['notes'][0]=='Fictional notes'
    if schemas and source==fixtures/'styles.odp':
     for name in ['content.xml','styles.xml','meta.xml','META-INF/manifest.xml']:
      schema=schemas.get('manifest' if name.startswith('META-INF') else 'document')
      if schema is not None:schema.assertValid(etree.fromstring(z.read(name)))
   print(source.name+': independent slide/text/notes and public reader values matched')
 print('ODP verification passed; schema and app checks run only when explicitly selected')
if __name__=='__main__':main()
