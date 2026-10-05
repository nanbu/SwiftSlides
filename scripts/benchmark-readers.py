#!/usr/bin/env python3
"""Measure indexed reader and atomic sinks with identical operations and per-process RSS."""
import importlib.util,json,os,platform,re,statistics,subprocess,sys,tempfile,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SOURCE=r'''
import Foundation
import SwiftSlides
func run(_ mode:String,_ input:URL,_ output:URL,_ count:Int) throws {
 let clock=ContinuousClock()
 func ms(_ start:ContinuousClock.Instant)->Double { let c=start.duration(to:clock.now).components;return Double(c.seconds)*1000+Double(c.attoseconds)/1e15 }
 if mode=="create" {
  var p=Presentation()
  for i in 0..<count { var s=Slide(id:"s\(i)");for j in 0..<10 { s.addText("Synthetic \(i)-\(j)",frame:.init(x:Double(j)*20,y:30,width:100,height:50)) };p.slides.append(s) }
  _ = try p.write(to:input);return
 }
 let start=clock.now
 var indexMS:Double?=nil,oneMS:Double?=nil,bytes=0
 switch mode {
 case "readAll":let p=try Presentation(contentsOf:input);precondition(p.slides.count==count);bytes=p.plainText.utf8.count
 case "readOne":
  let reader=try SlideReader(contentsOf:input,codecs:.all);indexMS=ms(start)
  let one=clock.now;let result=try reader.slide(id:reader.slideDescriptors[count/2].id);oneMS=ms(one);precondition(result.slide.elements.count==10);bytes=result.slide.plainText.utf8.count
 case "foundationAtomic","fileTarget":
  let data=try Data(contentsOf:input)
  if mode=="foundationAtomic" { try data.write(to:output,options:.atomic) } else { try FileTarget(output).write(data) }
  let saved=try Data(contentsOf:output);precondition(saved==data);bytes=data.count
 default:fatalError("unknown mode")
 }
 let index=indexMS.map { String($0) } ?? "null",one=oneMS.map { String($0) } ?? "null"
 print("{\"milliseconds\":\(ms(start)),\"indexMilliseconds\":\(index),\"oneSlideMilliseconds\":\(one),\"bytes\":\(bytes)}")
}
try run(CommandLine.arguments[1],URL(filePath:CommandLine.arguments[2]),URL(filePath:CommandLine.arguments[3]),Int(CommandLine.arguments[4])!)
'''

def odp(path,count):
 spec=importlib.util.spec_from_file_location('odp_fixture',ROOT/'scripts/generate-odp-fixture.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 parts=m.fixture_parts()
 page=''.join('<draw:rect svg:x="%spt" svg:y="30pt" svg:width="100pt" svg:height="50pt"><text:p>Synthetic %%s-%s</text:p></draw:rect>'%(j*20,j) for j in range(10))
 pages=''.join('<draw:page draw:name="Slide %s" draw:master-page-name="Master">%s</draw:page>'%(i,page.replace('%s',str(i))) for i in range(count))
 parts['content.xml']=m.document('content','<office:body><office:presentation>'+pages+'</office:presentation></office:body>')
 with zipfile.ZipFile(path,'w',compression=zipfile.ZIP_DEFLATED) as z:
  for name,data in parts.items():z.writestr(name,data,compress_type=zipfile.ZIP_STORED if name=='mimetype' else zipfile.ZIP_DEFLATED)


def main():
 result={'platform':platform.platform(),'cpu':subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip() if sys.platform=='darwin' else platform.processor(),
         'swift':subprocess.check_output(['swift','--version'],text=True).splitlines(),'runs':3,'cache':'warm filesystem; fresh process for every sample','shapesPerSlide':10,'images':0,'datasets':[]}
 with tempfile.TemporaryDirectory(prefix='swiftslides-reader-measure-') as folder:
  p=Path(folder);(p/'Sources/Measure').mkdir(parents=True)
  (p/'Package.swift').write_text('// swift-tools-version: 6.4\nimport PackageDescription\nlet package=Package(name:"Measure",platforms:[.macOS(.v14)],dependencies:[.package(path:'+json.dumps(str(ROOT))+')],targets:[.executableTarget(name:"Measure",dependencies:[.product(name:"SwiftSlides",package:"SwiftSlides")])],swiftLanguageModes:[.v6])')
  (p/'Sources/Measure/main.swift').write_text(SOURCE)
  subprocess.run(['swift','build','-c','release','--disable-sandbox','--package-path',str(p)],check=True,stdout=sys.stderr)
  binary=subprocess.check_output(['swift','build','-c','release','--package-path',str(p),'--show-bin-path'],text=True).strip()+'/Measure'
  for count in [10,100,1000]:
   for ext in ['pptx','odp']:
    deck=p/('input.'+ext);output=p/'output.pptx'
    if ext=='odp':odp(deck,count)
    else:subprocess.run([binary,'create',str(deck),str(output),str(count)],check=True,stdout=subprocess.DEVNULL)
    with zipfile.ZipFile(deck) as z:expanded=sum(x.file_size for x in z.infolist())
    dataset={'format':ext,'slides':count,'fileBytes':deck.stat().st_size,'declaredExpandedBytes':expanded,'operations':{}}
    modes=['readAll','readOne']+(['foundationAtomic','fileTarget'] if ext=='pptx' else [])
    samples={mode:[] for mode in modes}
    # Alternate competing operations in every round, not all-old then all-new.
    for _ in range(result['runs']):
     for mode in modes:
      timer=['/usr/bin/time','-l'] if sys.platform=='darwin' else ['/usr/bin/time','-f','%M peakRSSKiB']
      run=subprocess.run(timer+[binary,mode,str(deck),str(output),str(count)],check=True,capture_output=True,text=True)
      sample=json.loads(run.stdout)
      sample['peakRSSBytes']=int(re.search(r'(\d+)\s+maximum resident set size',run.stderr)[1]) if sys.platform=='darwin' else int(re.search(r'(\d+) peakRSSKiB',run.stderr)[1])*1024
      samples[mode].append(sample)
    for mode,values in samples.items():
     dataset['operations'][mode]={'medianMilliseconds':statistics.median(x['milliseconds'] for x in values),'maxMilliseconds':max(x['milliseconds'] for x in values),'medianPeakRSSBytes':statistics.median(x['peakRSSBytes'] for x in values),'maxPeakRSSBytes':max(x['peakRSSBytes'] for x in values),'samples':values}
    result['datasets'].append(dataset)
 print(json.dumps(result,indent=2))
if __name__=='__main__':main()
