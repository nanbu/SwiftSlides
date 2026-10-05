#!/usr/bin/env python3
"""macOSの専用一時ディスクイメージで実ENOSPCと保存先保持を検査する。"""
from pathlib import Path
import subprocess,tempfile,os,json,plistlib
root=Path(__file__).resolve().parents[1]
# Use the already-built public consumer without rebuilding against a mounted image.
consumer_context=tempfile.TemporaryDirectory(prefix='swiftslides-capacity-consumer-')
consumer=Path(consumer_context.name)
(consumer/'Sources/Probe').mkdir(parents=True,exist_ok=True)
(consumer/'Package.swift').write_text('// swift-tools-version: 6.4\nimport PackageDescription\nlet package=Package(name:"Probe",platforms:[.macOS(.v14)],dependencies:[.package(path:'+json.dumps(str(root))+')],targets:[.executableTarget(name:"Probe",dependencies:[.product(name:"SlideCore",package:"SwiftSlides")])],swiftLanguageModes:[.v6])')
(consumer/'Sources/Probe/main.swift').write_text('''import Foundation
import SlideCore
func probe() throws {
 let url=URL(filePath:CommandLine.arguments[1])
 do { try FileTarget(url).write(Data(repeating:7,count:2<<20));fatalError("expected ENOSPC") }
 catch let error as POSIXError { guard error.code == .ENOSPC else { throw error };print("ENOSPC") }
}
try probe()
''')
subprocess.run(['swift','build','-c','release','--disable-sandbox','--package-path',str(consumer)],check=True,stdout=subprocess.DEVNULL)
binary=subprocess.check_output(['swift','build','-c','release','--package-path',str(consumer),'--show-bin-path'],text=True).strip()+'/Probe'
with tempfile.TemporaryDirectory(prefix='swiftslides-capacity-') as folder:
 p=Path(folder);image=p/'capacity.dmg';mount=p/'mount';mount.mkdir()
 subprocess.run(['hdiutil','create','-size','16m','-fs','HFS+','-volname','SwiftSlidesCapacity','-ov',str(image)],check=True,stdout=subprocess.DEVNULL)
 attached=False
 try:
  subprocess.run(['hdiutil','attach','-nobrowse','-noautoopen','-mountpoint',str(mount),str(image)],check=True,stdout=subprocess.DEVNULL);attached=True
  output=mount/'target.pptx';original=b'original presentation bytes';output.write_bytes(original)
  # Leave approximately 256 KiB, making a 2 MiB sink fail after a partial write.
  free=os.statvfs(mount).f_bavail*os.statvfs(mount).f_frsize
  fill=mount/'fill'
  with fill.open('wb') as f:
   left=max(0,free-(256<<10))
   while left:
    n=min(left,65536);f.write(bytes(n));left-=n
  actualFree=os.statvfs(mount).f_bavail*os.statvfs(mount).f_frsize
  run=subprocess.run([binary,str(output)],check=True,capture_output=True,text=True)
  assert run.stdout.strip()=='ENOSPC';assert output.read_bytes()==original
  assert sorted(x.name for x in mount.iterdir() if not x.name.startswith('.'))==['fill','target.pptx']
  assert not list(mount.glob('.swiftslides-*'))
  result={'volume':'16 MiB HFS+ disk image','freeBytesBeforeWrite':actualFree,'attemptedWriteBytes':2<<20,'error':'ENOSPC','originalDestinationEqual':True,'temporaryFilesRemoved':True}
  print(json.dumps(result))
 finally:
  if attached:subprocess.run(['hdiutil','detach',str(mount)],check=True,stdout=subprocess.DEVNULL)
