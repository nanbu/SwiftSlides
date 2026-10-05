#!/usr/bin/env python3
"""限定IWA試作。公開codecではなく、未知fieldをそのまま保持するwire検査器。"""
import argparse, hashlib, json, os, struct, tempfile, zipfile
from collections import Counter
from pathlib import Path

MAX_PART = 128 << 20
MAX_TOTAL = 512 << 20
REGISTRY = {1:'KN.DocumentArchive',5:'KN.SlideArchive',2001:'TSWP.StorageArchive'}
TEXT_TYPE = 2001
TEXT_FIELD = 3


def varint(data, offset=0):
    value=0
    for shift in range(0,70,7):
        if offset >= len(data): raise ValueError('truncated varint')
        byte=data[offset];offset+=1
        if shift==63 and byte>1: raise ValueError('varint overflow')
        value |= (byte&127)<<shift
        if not byte&128:return value,offset
    raise ValueError('varint overflow')


def encode_varint(value):
    out=bytearray()
    while value>=128:out.append((value&127)|128);value>>=7
    out.append(value);return bytes(out)


def fields(data):
    """Return wire spans without normalizing tags, unknown values or their order."""
    offset=0;out=[]
    while offset<len(data):
        start=offset;key,offset=varint(data,offset);number=key>>3;wire=key&7
        if not 0<number<(1<<29):raise ValueError('invalid protobuf field number')
        value_start=offset
        if wire==0:value,offset=varint(data,offset)
        elif wire in (1,5):
            end=offset+(8 if wire==1 else 4)
            if end>len(data):raise ValueError('truncated fixed field')
            value=data[offset:end];offset=end
        elif wire==2:
            length,offset=varint(data,offset);value_start=offset
            if length>len(data)-offset:raise ValueError('truncated byte field')
            value=data[offset:offset+length];offset+=length
        else:raise ValueError('unsupported wire type (groups included)')
        out.append((number,wire,value,start,offset,value_start))
    return out


def scalar(message,number):
    matches=[x for x in fields(message) if x[0]==number]
    if len(matches)!=1 or matches[0][1]!=0:raise ValueError('missing/duplicate scalar')
    return matches[0][2]


def snappy_unpack(data, budget=MAX_PART):
    expected,offset=varint(data)
    if expected>budget:raise ValueError('snappy expansion budget')
    out=bytearray()
    while offset<len(data):
        tag=data[offset];offset+=1;kind=tag&3
        if kind==0:
            length=(tag>>2)+1
            if length>60:
                size=length-60
                if offset+size>len(data):raise ValueError('truncated snappy literal size')
                length=int.from_bytes(data[offset:offset+size],'little')+1;offset+=size
            if length>len(data)-offset or length>expected-len(out):raise ValueError('snappy literal bounds')
            out.extend(data[offset:offset+length]);offset+=length
        else:
            size={1:1,2:2,3:4}[kind]
            if offset+size>len(data):raise ValueError('truncated snappy copy')
            distance=int.from_bytes(data[offset:offset+size],'little');offset+=size
            length=((tag>>2)&7)+4 if kind==1 else (tag>>2)+1
            if kind==1:distance|=(tag&224)<<3
            if not 0<distance<=len(out) or length>expected-len(out):raise ValueError('snappy copy bounds')
            for _ in range(length):out.append(out[-distance])
    if len(out)!=expected:raise ValueError('snappy length mismatch')
    return bytes(out)


def snappy_pack(data):
    """Valid literal-only Snappy. Compression performance is outside this prototype."""
    out=bytearray(encode_varint(len(data)))
    for start in range(0,len(data),65536):
        chunk=data[start:start+65536];n=len(chunk)-1
        if n<60:out.append(n<<2)
        else:
            out.append(61<<2);out.extend(n.to_bytes(2,'little'))
        out.extend(chunk)
    return bytes(out)


def iwa_unpack(data, budget=MAX_PART):
    offset=0;out=bytearray()
    if not data:raise ValueError('empty IWA')
    while offset<len(data):
        if offset+4>len(data) or data[offset]!=0:raise ValueError('IWA chunk header')
        length=int.from_bytes(data[offset+1:offset+4],'little');offset+=4
        if not length or length>len(data)-offset:raise ValueError('IWA chunk bounds')
        out.extend(snappy_unpack(data[offset:offset+length],min(MAX_PART,budget)-len(out)));offset+=length
    return bytes(out)


def iwa_pack(payload):
    out=bytearray()
    for start in range(0,len(payload),65536):
        chunk=snappy_pack(payload[start:start+65536]);out.append(0);out.extend(len(chunk).to_bytes(3,'little'));out.extend(chunk)
    return bytes(out)


def archives(payload):
    offset=0;out=[]
    while offset<len(payload):
        header_length,offset=varint(payload,offset)
        if header_length>len(payload)-offset:raise ValueError('archive header bounds')
        header=payload[offset:offset+header_length];offset+=header_length
        identifier=scalar(header,1)
        infos=[x[2] for x in fields(header) if x[0]==2 and x[1]==2]
        if not infos:raise ValueError('missing MessageInfo')
        for info in infos:
            type_id=scalar(info,1);length=scalar(info,3)
            if length>len(payload)-offset:raise ValueError('archive object bounds')
            out.append((identifier,type_id,offset,offset+length));offset+=length
    return out


def load(path):
    with zipfile.ZipFile(path) as archive:
        infos=archive.infolist()
        if len(infos)>10000 or sum(x.file_size for x in infos)>MAX_TOTAL:raise ValueError('ZIP budget')
        names=[x.filename for x in infos]
        if len(set(names))!=len(names):raise ValueError('duplicate ZIP part')
        for info in infos:
            p=Path(info.filename)
            if p.is_absolute() or '..' in p.parts or '\\' in info.filename or info.file_size>MAX_PART:raise ValueError('unsafe ZIP part/size')
        data={x.filename:archive.read(x) for x in infos};comment=archive.comment
    if 'Index/Document.iwa' not in data:raise ValueError('unverified Keynote container')
    payloads={};expanded=0
    for name,value in data.items():
        if name.startswith('Index/') and name.endswith('.iwa'):
            payloads[name]=iwa_unpack(value,MAX_TOTAL-expanded);expanded+=len(payloads[name])
    for value in payloads.values():archives(value)
    return infos,data,payloads,comment


def inspect(path):
    _,data,payloads,_=load(path);counts=Counter();objects=0
    for payload in payloads.values():
        for identifier,type_id,start,end in archives(payload):counts[type_id]+=1;objects+=1
    return {'sourceSHA256':hashlib.sha256(Path(path).read_bytes()).hexdigest(),'iwaParts':len(payloads),'objects':objects,'typeCounts':dict(sorted(counts.items())),
            'recognizedTypes':{str(k):v for k,v in REGISTRY.items() if k in counts},'uninterpretedTypes':[k for k in sorted(counts) if k not in REGISTRY],
            'expandedIWABytes':sum(map(len,payloads.values())),'containerParts':len(data)}


def repack(source,destination,find=None,replace=None):
    infos,data,payloads,comment=load(source);original=payloads.copy();changed=[]
    if find is not None:
        a=find.encode();b=replace.encode()
        # UTF-16 text attribute offsets and all object lengths remain invariant.
        if len(a)!=len(b) or len(find.encode('utf-16-le'))!=len(replace.encode('utf-16-le')):raise ValueError('only equal UTF-8/UTF-16 length text replacement is verified')
        for name,payload in payloads.items():
            updated=bytearray(payload)
            for identifier,type_id,start,end in archives(payload):
                if type_id!=TEXT_TYPE:continue
                for field in fields(payload[start:end]):
                    if field[0]==TEXT_FIELD and field[1]==2 and field[2]==a:
                        p=start+field[5];updated[p:p+len(a)]=b;changed.append({'part':name,'objectID':identifier,'type':type_id,'field':TEXT_FIELD})
            payloads[name]=bytes(updated)
        if len(changed)!=1:raise ValueError('expected exactly one recognized text field; found '+str(len(changed)))
    destination=Path(destination)
    if Path(source).resolve()==destination.resolve():raise ValueError('prototype output must differ from source')
    staged=None
    try:
        fd,staged=tempfile.mkstemp(prefix='.keynote-probe-',dir=destination.parent);os.close(fd)
        with zipfile.ZipFile(staged,'w') as archive:
            archive.comment=comment
            for info in infos:
                value=iwa_pack(payloads[info.filename]) if info.filename in payloads else data[info.filename]
                archive.writestr(info,value)
        _,after,roundtrip,_=load(staged)
        if roundtrip!=payloads:raise ValueError('IWA payload preservation failed')
        if any(after[k]!=v for k,v in data.items() if k not in payloads):raise ValueError('non-IWA preservation failed')
        os.replace(staged,destination);staged=None
    finally:
        if staged:os.unlink(staged)
    return {'changedFields':changed,'untouchedIWAPayloadsEqual':all(payloads[k]==v for k,v in original.items() if k not in {x['part'] for x in changed}),
            'allNonIWAPartsEqual':True,'outputSHA256':hashlib.sha256(destination.read_bytes()).hexdigest()}


def self_test():
    import random
    random.seed(7)
    for n in [0,1,59,60,61,65535,65536,65537,200000]:
        data=bytes(random.getrandbits(8) for _ in range(n));assert snappy_unpack(snappy_pack(data))==data
        if n:assert iwa_unpack(iwa_pack(data))==data
    assert snappy_unpack(bytes([5,0,65,1,1]))==b'AAAAA' # overlapping copy
    for bad in [b'',b'\x80',b'\x01',b'\x01\x02\x00\x00',b'\x01\xf0']:
        try:snappy_unpack(bad)
        except (ValueError,IndexError):pass
        else:raise AssertionError('bad Snappy accepted')
    for bad in [b'\x00',b'\x0b',b'\x0a\x05x',b'\x09x',b'\x08'+b'\xff'*10]:
        try:fields(bad)
        except ValueError:pass
        else:raise AssertionError('bad protobuf accepted')
    # Unknown field bytes/order, including noncanonical varint, must survive.
    body=b'\x1a\x03Old\xf8\x07\x81\x00'
    info=b'\x08'+encode_varint(TEXT_TYPE)+b'\x18'+encode_varint(len(body))
    header=b'\x08\x01\x12'+encode_varint(len(info))+info+b'\xa0\x06\x81\x00'
    payload=encode_varint(len(header))+header+body
    assert archives(payload)==[(1,TEXT_TYPE,len(payload)-len(body),len(payload))]
    with tempfile.TemporaryDirectory() as folder:
        a=Path(folder)/'source.key';b=Path(folder)/'out.key'
        with zipfile.ZipFile(a,'w') as z:z.writestr('Index/Document.iwa',iwa_pack(payload));z.writestr('Data/unknown',b'opaque')
        before=a.read_bytes();result=repack(a,b,find='Old',replace='New');assert result['allNonIWAPartsEqual'];assert a.read_bytes()==before
        after=load(b)[2]['Index/Document.iwa'];assert after==payload.replace(b'Old',b'New')
        try:repack(a,b,find='Old',replace='Longer')
        except ValueError:pass
        else:raise AssertionError('unsafe unequal text edit accepted')
    print('Keynote wire prototype: synthetic roundtrip, unknown-field preservation and negative controls passed')


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--self-test',action='store_true')
    parser.add_argument('--source',type=Path);parser.add_argument('--output',type=Path);parser.add_argument('--find');parser.add_argument('--replace')
    args=parser.parse_args()
    if args.self_test:self_test();return
    if not args.source:parser.error('--source is required')
    if (args.find is None)!=(args.replace is None):parser.error('--find and --replace must be paired')
    result=inspect(args.source)
    if args.output:result['repack']=repack(args.source,args.output,args.find,args.replace)
    elif args.find is not None:parser.error('text edits require --output')
    print(json.dumps(result,ensure_ascii=False,indent=2))

if __name__=='__main__':main()
