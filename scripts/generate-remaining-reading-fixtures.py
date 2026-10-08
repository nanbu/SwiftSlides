#!/usr/bin/env python3
"""架空の残読取fixture。ZIP/XML/IWAはSwiftのreaderと独立して構成する。"""
from pathlib import Path
from io import BytesIO
import struct
import gzip
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'Tests/SwiftSlidesTests/Fixtures'
def zip_bytes(parts):
    out = BytesIO()
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        for name, data in sorted(parts.items()):
            entry = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0)); entry.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(entry, data)
    return out.getvalue()
def varint(n):
    b = bytearray()
    while n >= 128: b.append((n & 127) | 128); n >>= 7
    b.append(n); return bytes(b)
def field(n, value):
    if isinstance(value, int): return varint(n << 3) + varint(value)
    if isinstance(value, float): return varint(n << 3 | 5) + struct.pack('<f', value)
    if isinstance(value, str): value = value.encode()
    return varint(n << 3 | 2) + varint(len(value)) + value
def double(n, value): return varint(n << 3 | 1) + struct.pack('<d', value)
def fixed(n, value): return varint(n << 3 | 5) + struct.pack('<I', value)
def ref(n, value): return field(n, field(1, value))
def iwa(objects):
    payload = b''
    for i, t, data in objects:
        info = field(1, t) + field(2, b'\x01\x00') + field(3, len(data))
        header = field(1, i) + field(2, info)
        payload += varint(len(header)) + header + data
    n = len(payload); count = ((n - 1).bit_length() + 7) // 8
    snappy = varint(n) + bytes([(59 + count) << 2]) + (n - 1).to_bytes(count, 'little') + payload
    return b'\0' + len(snappy).to_bytes(3, 'little') + snappy
formula = field(1, field(1, field(1,17) + double(4,2)) + field(1, field(1,17) + double(4,3)) + field(1,field(1,1)))
cell = bytes([5,2]) + bytes(6) + struct.pack('<I', 0x202) + struct.pack('<dI',5,1)
row = field(1,1) + field(2,1) + field(6,cell) + field(7,struct.pack('<hh',0,-1))
store = field(3, field(1,field(1,0)+ref(2,83)) + field(2,256)) + ref(6,84) + ref(13,85)
geometry = field(1,field(1,12.0)+field(2,24.0))+field(2,field(1,200.0)+field(2,80.0))
grid = field(1,'Fictional series') + field(2,'A') + field(3, field(1,double(1,5)))
objects = [(1,1,ref(2,2)+field(3,b'')), (2,2,field(3,ref(2,10))+field(4,field(1,960.0)+field(2,540.0))), (10,4,ref(2,20)),
 (20,5,ref(7,80)+ref(7,90)), (80,6000,field(1,field(1,geometry))+ref(2,81)),
 (81,6001,field(4,store)+field(6,2)+field(7,2)+double(16,25)+double(17,100)), (83,6002,field(5,row)+field(7,1)),
 (84,6005,field(1,3)+field(2,2)+field(3,field(1,1)+field(5,formula))),
 (85,6144,field(1,field(1,fixed(1,0))+field(2,fixed(1,(2<<16)|1)))),
 (90,5021,field(1,field(1,geometry))+field(10000,field(1,1)+field(5,1)+field(7,grid)+ref(14,91)+ref(13,92))),
 (91,5027,field(10000,field(16,'Fictional axis')+field(17,double(1,100))+field(18,double(1,-5))+field(8,1))),
 (92,5026,field(10000,field(25,1)+field(28,1)))]
(OUT/'remaining-native.keynote.zip').write_bytes(zip_bytes({'Index/Document.iwa':iwa(objects)}))
legacy_objects = [(i,t,d) for i,t,d in objects if i not in [91,92]] + [
 (91,5016,field(11,double(1,-5))+field(12,double(1,100))+field(56,'Fictional axis')+field(51,1)),
 (92,5012,field(1,ref(3,93))+field(10,1)), (93,5012,field(25,1))]
(OUT/'remaining-preuff.keynote.zip').write_bytes(zip_bytes({'Index/Document.iwa':iwa(legacy_objects)}))
key = 'http://developer.apple.com/namespaces/keynote2'; sf = 'http://developer.apple.com/namespaces/sf'
xml = f'<key:presentation xmlns:key="{key}" xmlns:sf="{sf}"><key:size sf:w="960" sf:h="540"/><key:slide-list><key:slide><sf:text-storage><sf:p>Fictional legacy Keynote</sf:p></sf:text-storage></key:slide></key:slide-list></key:presentation>'
(OUT/'legacy-xml.key.zip').write_bytes(zip_bytes({'index.apxl':xml}))
(OUT/'legacy-gzip.key.zip').write_bytes(zip_bytes({'index.apxl.gz':gzip.compress(xml.encode(),mtime=0)}))
oldoffice='http://openoffice.org/2000/office'; olddraw='http://openoffice.org/2000/drawing'; oldtext='http://openoffice.org/2000/text'; oldstyle='http://openoffice.org/2000/style'; oldfo='http://www.w3.org/1999/XSL/Format'
(OUT/'legacy-impress.sxi').write_bytes(zip_bytes({'content.xml':f'<office:document-content xmlns:office="{oldoffice}" xmlns:draw="{olddraw}" xmlns:text="{oldtext}" office:class="presentation"><office:body><draw:page><draw:text-box><text:p>Fictional legacy Impress</text:p></draw:text-box></draw:page></office:body></office:document-content>', 'styles.xml':f'<office:document-styles xmlns:office="{oldoffice}" xmlns:style="{oldstyle}" xmlns:fo="{oldfo}"><style:page-master><style:properties fo:page-width="10in" fo:page-height="7.5in"/></style:page-master></office:document-styles>'}))
print('残読取の架空fixture: 5 files')
