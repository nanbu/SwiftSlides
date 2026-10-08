#!/usr/bin/env python3
"""架空fixtureを独立実装で生成。暗号fixture生成にはcryptographyを使う。"""
from pathlib import Path
from io import BytesIO
import base64
import hashlib
import hmac
import struct
import zipfile
import zlib
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

DEST = Path(__file__).resolve().parents[1] / 'Tests/SwiftSlidesTests/Fixtures'
PASSWORD = 'fictional-鍵'
FREE, END, FAT = 0xffffffff, 0xfffffffe, 0xfffffffd


def zip_bytes(parts):
    out = BytesIO()
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_STORED) as z:
        for name, data in parts.items():
            entry = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
            z.writestr(entry, data)
    return out.getvalue()


def encrypt(key, iv, data, ecb=False):
    worker = Cipher(algorithms.AES(key), modes.ECB() if ecb else modes.CBC(iv)).encryptor()
    return worker.update(data) + worker.finalize()


def rounded(data):
    return data + bytes((-len(data)) % 16)


def compound(info, package, major=3):
    sector = 512 if major == 3 else 4096
    sectors = []
    chains = []
    def allocate(data):
        first = len(sectors)
        chunks = [data[i:i+sector].ljust(sector, b'\0') for i in range(0, len(data), sector)]
        sectors.extend(chunks)
        ids = list(range(first, first + len(chunks)))
        chains.append(ids)
        return first if ids else END
    mini = info.ljust((len(info)+63)//64*64, b'\0')
    mini_first = allocate(mini)
    package_first = allocate(package)
    mini_ids = list(range(len(mini)//64))
    mini_fat = [i+1 for i in mini_ids]
    mini_fat[-1] = END
    mini_fat_first = allocate(struct.pack('<'+'I'*len(mini_fat), *mini_fat).ljust(sector, b'\xff'))
    def entry(name, kind, start=END, size=0, child=FREE, right=FREE):
        row = bytearray(128)
        raw = (name+'\0').encode('utf-16le')
        row[:len(raw)] = raw
        struct.pack_into('<HBBIII', row, 64, len(raw), kind, 1, FREE, right, child)
        struct.pack_into('<IQ', row, 116, start, size)
        return row
    directory = entry('Root Entry', 5, mini_first, len(mini), child=1)
    directory += entry('EncryptionInfo', 2, 0, len(info), right=2)
    directory += entry('EncryptedPackage', 2, package_first, len(package))
    directory_first = allocate(directory)
    fat_count = 1
    while fat_count*sector//4 < len(sectors)+fat_count:
        fat_count += 1
    fat_ids = list(range(len(sectors), len(sectors)+fat_count))
    assert len(fat_ids) <= 109
    table = [FREE]*(fat_count*sector//4)
    for chain in chains:
        for a,b in zip(chain, chain[1:]+[END]):
            table[a] = b
    for i in fat_ids:
        table[i] = FAT
    fat_data = struct.pack('<'+'I'*len(table), *table)
    sectors.extend(fat_data[i:i+sector] for i in range(0,len(fat_data),sector))
    header = bytearray(sector)
    header[:8] = bytes.fromhex('d0cf11e0a1b11ae1')
    struct.pack_into('<HHHHH', header, 24, 0x3e, major, 0xfffe, 9 if major==3 else 12, 6)
    struct.pack_into('<IIIIIIIII', header, 40, 0 if major==3 else 1, fat_count, directory_first, 0, 4096, mini_fat_first, 1, END, 0)
    struct.pack_into('<'+'I'*109, header, 76, *(fat_ids+[FREE]*(109-len(fat_ids))))
    return bytes(header)+b''.join(sectors)


def agile(data, bits, hash_name, major=3):
    digest = lambda x: hashlib.new(hash_name, x).digest()
    salt = bytes(range(16))
    data_salt = bytes(range(16,32))
    key = bytes(range(bits//8))
    spins = 1000
    h = digest(salt + PASSWORD.encode('utf-16le'))
    for i in range(spins):
        h = digest(struct.pack('<I',i)+h)
    def block_key(block):
        return digest(h+bytes.fromhex(block)).ljust(bits//8,b'\x36')[:bits//8]
    verifier = bytes(range(32,48))
    crypt_package = struct.pack('<Q',len(data))
    for i,start in enumerate(range(0,len(data),4096)):
        iv = digest(data_salt+struct.pack('<I',i)).ljust(16,b'\x36')[:16]
        crypt_package += encrypt(key,iv,rounded(data[start:start+4096]))
    hk = digest(b'Fictional integrity key')
    hv = hmac.new(hk, crypt_package, hash_name).digest()
    b64 = lambda x: base64.b64encode(x).decode()
    def integrity(block, value):
        return b64(encrypt(key,digest(data_salt+bytes.fromhex(block))[:16],rounded(value)))
    def params(s):
        return f'saltSize="16" blockSize="16" keyBits="{bits}" hashSize="{len(h)}" cipherAlgorithm="AES" cipherChaining="ChainingModeCBC" hashAlgorithm="{hash_name.upper()}" saltValue="{b64(s)}"'
    xml = f'''<encryption xmlns="http://schemas.microsoft.com/office/2006/encryption" xmlns:p="http://schemas.microsoft.com/office/2006/keyEncryptor/password"><keyData {params(data_salt)}/><dataIntegrity encryptedHmacKey="{integrity('5fb2ad010cb9e1f6',hk)}" encryptedHmacValue="{integrity('a0677f02b22c8433',hv)}"/><keyEncryptors><keyEncryptor uri="http://schemas.microsoft.com/office/2006/keyEncryptor/password"><p:encryptedKey {params(salt)} spinCount="{spins}" encryptedVerifierHashInput="{b64(encrypt(block_key('fea7d2763b4b9e79'),salt,verifier))}" encryptedVerifierHashValue="{b64(encrypt(block_key('d7aa0f6d3061344e'),salt,rounded(digest(verifier))))}" encryptedKeyValue="{b64(encrypt(block_key('146e0be7abacd0d6'),salt,rounded(key)))}"/></keyEncryptor></keyEncryptors></encryption>'''.encode()
    return compound(struct.pack('<HHI',4,4,0x40)+xml,crypt_package,major)


def standard(data,bits):
    salt = bytes(range(16))
    h = hashlib.sha1(salt+PASSWORD.encode('utf-16le')).digest()
    for i in range(50000):
        h = hashlib.sha1(struct.pack('<I',i)+h).digest()
    final = hashlib.sha1(h+bytes(4)).digest()
    def derive(byte):
        buf = bytearray([byte]*64)
        for i,b in enumerate(final):
            buf[i] ^= b
        return hashlib.sha1(buf).digest()
    key = (derive(0x36)+derive(0x5c))[:bits//8]
    verifier = bytes(range(16,32))
    header = struct.pack('<IIIIIIII',0x24,0,0x660e+((bits-128)//64),0x8004,bits,24,0,0)+('Fictional AES Provider\0').encode('utf-16le')
    info = struct.pack('<HHII',4,2,0x24,len(header))+header
    info += struct.pack('<I',16)+salt+encrypt(key,None,verifier,True)+struct.pack('<I',20)+encrypt(key,None,rounded(hashlib.sha1(verifier).digest()),True)
    package = struct.pack('<Q',len(data))+encrypt(key,None,rounded(data),True)
    return compound(info,package)

def encrypted_odp(bits, start_name):
    with zipfile.ZipFile(DEST/'styles.odp') as z:
        parts = {n:z.read(n) for n in z.namelist()}
    name = 'content.xml'
    plain = parts[name]
    compressor = zlib.compressobj(wbits=-15)
    compressed = compressor.compress(plain)+compressor.flush()
    start = hashlib.new(start_name, PASSWORD.encode()).digest()
    salt, iv = bytes(range(16)), bytes(range(16,32))
    key = hashlib.pbkdf2_hmac('sha1',start,salt,1000,bits//8)
    padding = 16-len(compressed)%16
    parts[name] = encrypt(key,iv,compressed+bytes(padding-1)+bytes([padding]))
    b64 = lambda x: base64.b64encode(x).decode()
    xml = f'''<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.3"><manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.presentation"/><manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml" manifest:size="{len(plain)}"><manifest:encryption-data manifest:checksum-type="SHA1/1K" manifest:checksum="{b64(hashlib.sha1(compressed[:1024]).digest())}"><manifest:algorithm manifest:algorithm-name="http://www.w3.org/2001/04/xmlenc#aes{bits}-cbc" manifest:initialisation-vector="{b64(iv)}"/><manifest:key-derivation manifest:key-derivation-name="PBKDF2" manifest:iteration-count="1000" manifest:key-size="{bits//8}" manifest:salt="{b64(salt)}"/><manifest:start-key-generation manifest:start-key-generation-name="http://www.w3.org/2000/09/xmldsig#{start_name}" manifest:key-size="{len(start)}"/></manifest:encryption-data></manifest:file-entry></manifest:manifest>'''
    extras = ''.join(f'<manifest:file-entry manifest:full-path="{n}" manifest:media-type="{"image/png" if n.endswith(".png") else "text/xml"}"/>' for n in parts if n not in ('content.xml','META-INF/manifest.xml','mimetype'))
    xml = xml.replace('</manifest:manifest>',extras+'</manifest:manifest>')
    parts['META-INF/manifest.xml'] = xml.encode()
    return zip_bytes(parts)


def varint(n):
    out = bytearray()
    while n > 127:
        out.append((n&127)|128)
        n >>= 7
    out.append(n)
    return bytes(out)


def field(n,value):
    if isinstance(value,int):
        return varint(n<<3)+varint(value)
    if isinstance(value,float):
        return varint(n<<3|5)+struct.pack('<f',value)
    if isinstance(value,str):
        value = value.encode()
    return varint(n<<3|2)+varint(len(value))+value


def ref(n,i):
    return field(n,field(1,i))


def iwa(objects):
    payload = b''
    for i,t,b,refs in objects:
        info = field(1,t)+field(2,varint(1)+varint(0))+field(3,len(b))+field(5,b''.join(varint(r) for r in refs))
        header = field(1,i)+field(2,info)
        payload += varint(len(header))+header+b
    length = len(payload)
    # Snappy literalのみ。readerのcopyは別の負例/独立vectorで検査する。
    if length <= 60:
        snappy = varint(length)+bytes([(length-1)<<2])+payload
    else:
        count = ((length-1).bit_length()+7)//8
        snappy = varint(length)+bytes([(59+count)<<2])+(length-1).to_bytes(count,'little')+payload
    return b'\0'+len(snappy).to_bytes(3,'little')+snappy


def keynote():
    geometry = field(1,field(1,12.0)+field(2,24.0))+field(2,field(1,200.0)+field(2,80.0))+field(4,0.5)
    drawable = field(1,geometry)+field(8,'Fictional alt')
    shape = field(1,field(1,drawable))+ref(4,50)+field(6,1)
    objects = [
        (1,1,ref(2,2)+field(3,b''),[2]),
        (2,2,field(3,ref(2,10)+ref(2,11))+field(4,field(1,960.0)+field(2,540.0)),[10,11]),
        (10,4,ref(2,20),[20]),(11,4,ref(2,21)+field(4,1),[21]),
        (20,5,ref(7,30)+ref(7,31)+ref(7,32)+field(10,'Fictional slide')+ref(27,60),[30,31,32,60]),
        (21,5,field(10,'Hidden fictional slide'),[]),
        (30,2011,shape,[50]),(31,3005,field(1,drawable)+ref(11,100),[]),
        (32,9999,field(99,b'\x00\xffFictional unknown'),[]),
        (50,2001,field(3,'Fictional title\nSecond line'),[]),
        (60,15,ref(1,61),[61]),(61,2001,field(3,'Fictional notes'),[]),
        (70,11006,field(4,field(1,100)+field(3,'fixture.png')+field(4,'fixture.png')),[]),
    ]
    return zip_bytes({'Index/Document.iwa':iwa(objects),'Data/fixture.png':(DEST/'fixture.png').read_bytes()})


def double_field(n,value):
    return varint(n<<3|1)+struct.pack('<d',value)


def keynote_advanced(cell_version=5):
    geometry = field(1,field(1,12.0)+field(2,24.0))+field(2,field(1,200.0)+field(2,80.0))
    drawable = field(1,geometry)
    color = field(1,1)+field(3,1.0)+field(4,0.0)+field(5,0.0)
    # 2列、疎な第2行、型付き数値と文字。値・run・参照は独立した期待値。
    string_cell = bytes([cell_version,3])+bytes(6)+struct.pack('<II',8,7)
    numeric_cell = bytes([5,2])+bytes(6)+struct.pack('<I',2)+struct.pack('<d',42.5)
    row = field(1,0)+field(2,2)+field(6,string_cell+numeric_cell)+field(7,struct.pack('<hh',0,len(string_cell)))
    store = field(3,field(1,field(1,0)+ref(2,83))+field(2,256))+ref(4,82)
    table = field(4,store)+field(6,2)+field(7,2)+field(8,'Fictional table')+double_field(16,25)+double_field(17,100)
    style = field(1,field(1,field(1,'Fictional shape style'))+field(11,field(1,field(1,color))))
    text = 'A😀B\n次の行'
    para = field(1,field(1,0)+ref(2,75))
    chars = field(1,field(1,0)+ref(2,76))+field(1,field(1,3))
    grid = field(1,'Fictional series')+field(2,'A')+field(2,'B')+field(3,field(1,double_field(1,12.5))+field(1,b''))
    objects = [
        (1,1,ref(2,2)+field(3,b''),[2]),
        (2,2,field(3,ref(2,10))+field(4,field(1,960.0)+field(2,540.0)),[10]),
        (10,4,ref(2,20),[20]),
        (20,5,ref(7,30)+ref(7,80)+ref(7,90)+ref(2,95)+ref(43,96)+field(4,field(2,field(8,field(2,'Dissolve')+double_field(3,1.5)+double_field(5,2.0)+field(6,1)))),[30,80,90,95,96]),
        (30,2011,field(1,field(1,drawable)+ref(2,74))+ref(4,50),[50,74]),
        (50,2001,field(3,text)+field(5,para)+field(8,chars),[75,76]),
        (74,2025,style,[]),
        (75,2022,field(1,field(1,'Fictional paragraph'))+field(11,field(3,24.0))+field(12,field(1,2)),[]),
        (76,2021,field(1,field(1,'Fictional characters'))+field(11,field(1,1)+field(5,'Helvetica')),[]),
        (80,6000,field(1,drawable)+ref(2,81),[81]),(81,6001,table,[82,83]),
        (82,6005,field(1,1)+field(2,8)+field(3,field(1,7)+field(3,'Fictional cell')),[]),
        (83,6002,field(5,row)+field(7,1),[]),
        (90,5021,field(1,drawable)+field(10000,field(1,1)+field(5,1)+field(7,grid)),[]),
        (95,8,ref(1,30)+field(2,'byObject')+field(4,field(4,1)+field(18,field(1,'buildIn')+field(2,'Dissolve')+double_field(3,0.75))),[30]),
        (96,153,ref(1,95)+double_field(3,0.25)+double_field(4,0.75)+field(5,0),[95]),
    ]
    return zip_bytes({'Index/Document.iwa':iwa(objects)})


def encrypted_keynote():
    with zipfile.ZipFile(BytesIO(keynote())) as z:
        parts = {n:z.read(n) for n in z.namelist()}
    salt,iv = bytes(range(16)),bytes(range(16,32))
    rounds = 1000
    key = hashlib.pbkdf2_hmac('sha1',PASSWORD.encode(),salt,rounds,16)
    verifier = bytes(range(32))
    parts['.iwpv2'] = struct.pack('<HHI',2,1,rounds)+salt+iv+encrypt(key,iv,verifier+hashlib.sha256(verifier).digest())
    for n in list(parts):
        if n.startswith(('Index/','Data/')):
            raw = bytes(range(16))+parts[n]
            pad = 16-len(raw)%16
            parts[n] = iv+encrypt(key,iv,raw+bytes([pad])*pad)+bytes(20)
    return zip_bytes(parts)


def keynote_paths(line_kind=2, line_points=1):
    point = lambda x,y: field(1,float(x))+field(2,float(y))
    command = lambda kind,points: field(1,field(1,kind)+b''.join(field(2,point(*p)) for p in points))
    path = command(1,[(0,0)])+command(line_kind,[(20,10)]*line_points)
    path += command(3,[(25,15),(30,20)])+command(4,[(35,25),(40,30),(45,35)])+command(5,[])
    bezier = field(2,field(1,200.0)+field(2,80.0))+field(3,path)
    geometry = field(1,point(12,24))+field(2,field(1,200.0)+field(2,80.0))
    drawable = field(1,geometry)
    shape = field(1,drawable)+field(3,field(1,1)+field(5,bezier))
    connector_shape = field(1,drawable)+field(3,field(7,field(1,bezier)+field(2,1)))
    objects = [
        (1,1,ref(2,2)+field(3,b''),[2]),
        (2,2,field(3,ref(2,10))+field(4,field(1,960.0)+field(2,540.0)),[10]),
        (10,4,ref(2,20),[20]),(20,5,ref(7,30)+ref(7,31),[30,31]),
        (30,3004,shape,[]),(31,3009,field(1,connector_shape)+ref(2,30),[30]),
    ]
    return zip_bytes({'Index/Document.iwa':iwa(objects)})

def main():
    plain = (DEST/'stored.pptx').read_bytes()
    for bits,h,major in [(128,'sha1',3),(192,'sha256',4),(256,'sha512',3)]:
        (DEST/f'encrypted-agile-{bits}.pptx').write_bytes(agile(plain,bits,h,major))
    for bits in (128,192,256):
        (DEST/f'encrypted-standard-{bits}.pptx').write_bytes(standard(plain,bits))
    for bits,h in [(128,'sha1'),(256,'sha256')]:
        (DEST/f'encrypted-aes-{bits}.odp').write_bytes(encrypted_odp(bits,h))
    (DEST/'native-synthetic.keynote.zip').write_bytes(keynote())
    (DEST/'native-advanced.keynote.zip').write_bytes(keynote_advanced())
    (DEST/'native-unsupported-cell.keynote.zip').write_bytes(keynote_advanced(cell_version=6))
    (DEST/'native-paths.keynote.zip').write_bytes(keynote_paths())
    (DEST/'native-invalid-path.keynote.zip').write_bytes(keynote_paths(line_points=2))
    (DEST/'native-unknown-path.keynote.zip').write_bytes(keynote_paths(line_kind=99))
    (DEST/'encrypted-native.keynote.zip').write_bytes(encrypted_keynote())
    print('架空Keynote 6件、暗号Keynote 1件、暗号PPTX 6件、暗号ODP 2件を生成')

if __name__ == '__main__':
    main()
