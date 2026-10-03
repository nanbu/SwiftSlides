#!/usr/bin/env python3
"""Cross-check public support rows, named regression tests and module structure; includes negative controls."""
import argparse, json, re, sys
from pathlib import Path

def rendered(rows):
 return '| 機能 | 読み取り | 保存/生成 | 境界 |\n|---|---|---|---|\n'+'\n'.join('| '+' | '.join(row[k] for k in ['feature','read','write','boundary'])+' |' for row in rows)
def audit(rows,readme,tests,manifest):
 errors=[]
 if not rows: errors.append('empty support evaluation set')
 if len({r['feature'] for r in rows})!=len(rows): errors.append('duplicate feature')
 match=re.search(r'<!-- contract:start -->\n(.*?)\n<!-- contract:end -->',readme,re.S)
 if not match or match.group(1)!=rendered(rows): errors.append('support table differs from canonical ledger')
 for row in rows:
  if not re.search(r'func\s+'+re.escape(row['test'])+r'\s*\(',tests): errors.append('missing regression test: '+row['test'])
 for module in ['SlideCore','SlidePPTX','SwiftSlides']:
  if '.library(name: "'+module+'"' not in manifest: errors.append('missing public product: '+module)
 return errors

def self_test():
 row={'feature':'Feature','read':'対応','write':'対応','boundary':'API','test':'testOne'}
 table='<!-- contract:start -->\n'+rendered([row])+'\n<!-- contract:end -->'
 manifest=' '.join('.library(name: "'+m+'"' for m in ['SlideCore','SlidePPTX','SwiftSlides'])
 if audit([row],table,'func testOne()',manifest): raise RuntimeError('valid contract rejected')
 for arguments,expected in [(([],table,'func testOne()',manifest),'empty'),(([row],table.replace('API','changed'),'func testOne()',manifest),'table'),(([row],table,'',manifest),'test'),(([row],table,'func testOne()',''),'product'),(([row,row],table,'func testOne()',manifest),'duplicate')]:
  if not any(expected in e for e in audit(*arguments)): raise RuntimeError('negative control missed: '+expected)
 print('Contract negative controls: 5 passed')
def main():
 p=argparse.ArgumentParser();p.add_argument('--self-test',action='store_true');args=p.parse_args();self_test()
 if args.self_test:return 0
 root=Path(__file__).resolve().parents[1]; rows=json.loads((root/'docs/support.json').read_text(encoding='utf-8-sig'))
 tests='\n'.join(p.read_text() for p in (root/'Tests').rglob('*.swift'))
 errors=audit(rows,(root/'README.md').read_text(encoding='utf-8-sig'),tests,(root/'Package.swift').read_text())
 if (root/'docs/cookbook.md').read_bytes()!=(root/'Sources/SwiftSlides/SwiftSlides.docc/Cookbook.md').read_bytes(): errors.append('cookbook source and DocC differ')
 if errors:print('\n'.join(errors),file=sys.stderr);return 1
 print('Support ledger: %d rows and regression tests passed'%len(rows));return 0
if __name__=='__main__':sys.exit(main())
