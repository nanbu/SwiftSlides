#!/usr/bin/env python3
"""Measure release library I/O and per-process peak RSS on a synthetic deck (macOS/Linux)."""
import json, platform, re, subprocess, tempfile, statistics, sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
source=r'''
import Foundation
import SwiftSlides
let mode = CommandLine.arguments[1], url = URL(filePath:CommandLine.arguments[2])
let clock = ContinuousClock(), start = clock.now
var bytes = 0
switch mode {
case "create":
    var p = Presentation()
    for i in 0..<100 {
        var s = Slide(name:"Slide \(i)")
        for j in 0..<10 { s.addShape(.roundedRectangle,frame:.init(x:Double(j%5)*180+20,y:Double(j/5)*220+60,width:160,height:180),fill:.solid(.theme("lt2")),stroke:.init(color:.blue,width:1),text:.init("Synthetic initiative \(i)-\(j)",style:.init(font:.init(size:18),bold:true))) }
        p.slides.append(s)
    }
    let result = try p.write(to:url); bytes = result.data.count
case "read":
    let p = try Presentation(contentsOf:url); precondition(p.slides.count == 100 && p.slides[0].elements.count == 10); bytes = p.plainText.utf8.count
case "noop":
    let p = try Presentation(contentsOf:url), d = try p.data(); let original = try Data(contentsOf:url); precondition(d == original); bytes = d.count
case "edit":
    var p = try Presentation(contentsOf:url); p.slides[0].elements[0].frame?.x += 1
    let d = try p.data(options:.init(strict:true)); bytes = d.count
    let reread = try Presentation(data:d); precondition(reread.slides[0].elements[0].frame?.x == 21)
default: fatalError("unknown operation")
}
let duration=start.duration(to:clock.now).components
let ms=Double(duration.seconds)*1000+Double(duration.attoseconds)/1e15
print("{\"milliseconds\":\(ms),\"bytes\":\(bytes)}")
'''
with tempfile.TemporaryDirectory(prefix='swiftslides-benchmark-') as folder:
 p=Path(folder);(p/'Sources/Measure').mkdir(parents=True)
 (p/'Package.swift').write_text('// swift-tools-version: 6.2\nimport PackageDescription\nlet package = Package(name:"Measure",platforms:[.macOS(.v14)],dependencies:[.package(path:'+json.dumps(str(root))+')],targets:[.executableTarget(name:"Measure",dependencies:[.product(name:"SwiftSlides",package:"SwiftSlides")])])')
 (p/'Sources/Measure/main.swift').write_text(source)
 subprocess.run(['swift','build','-c','release','--package-path',str(p)],check=True,stdout=sys.stderr)
 binary=subprocess.check_output(['swift','build','-c','release','--package-path',str(p),'--show-bin-path'],text=True).strip()+'/Measure'
 result={'platform':platform.platform(),'python':platform.python_version(),'swift':subprocess.check_output(['swift','--version'],text=True).splitlines()[0],'dataset':{'slides':100,'shapesPerSlide':10,'images':0},'runs':5,'operations':{}}
 deck=p/'input.pptx'
 subprocess.run([binary,'create',str(deck)],check=True,stdout=subprocess.DEVNULL)
 result['dataset']['fileBytes']=deck.stat().st_size
 for mode in ['create','read','noop','edit']:
  samples=[]
  for _ in range(5):
   cmd=['/usr/bin/time','-l'] if sys.platform=='darwin' else ['/usr/bin/time','-f','%M peakRSSKiB']
   r=subprocess.run(cmd+[binary,mode,str(deck)],check=True,capture_output=True,text=True)
   sample=json.loads(r.stdout)
   if sys.platform=='darwin': rss=int(re.search(r'(\d+)\s+maximum resident set size',r.stderr)[1])
   else: rss=int(re.search(r'(\d+) peakRSSKiB',r.stderr)[1])*1024
   sample['peakRSSBytes']=rss;samples.append(sample)
  result['operations'][mode]={'medianMilliseconds':statistics.median(s['milliseconds'] for s in samples),'medianPeakRSSBytes':statistics.median(s['peakRSSBytes'] for s in samples),'samples':samples}
 print(json.dumps(result,indent=2))
