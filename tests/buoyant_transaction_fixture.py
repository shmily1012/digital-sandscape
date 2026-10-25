"""Exact CPU packet oracle for the GPU transaction on a real stalled field."""
import json
import struct
from pathlib import Path
from buoyant_loop_probe import probe
from grain_collective_reference import apply, work

root=Path(__file__).resolve().parents[1]
prefix=root/'reports/sandscape-long-cycle-90000-paired-interface-energy-exchange-wetting-0.5'
r=probe(prefix);path=r['candidates'][0]['path'];n=256;cells=n*n
c=list(struct.unpack('<%df'%cells,Path(str(prefix)+'.f32').read_bytes()))
m=list(struct.unpack('<%dI'%cells,Path(str(prefix)+'.materials.u32').read_bytes()))
f=list(struct.unpack('<%df'%(cells*9),Path(str(prefix)+'.populations.f32').read_bytes()))
residual=[0.]*cells;stamps=[-1]*cells
packf=lambda a:struct.pack('<%df'%len(a),*a)
packi=lambda a:struct.pack('<%di'%len(a),*a)
def payload():return packf(c)+packf(f)+packi(m)+bytes(cells*8)+packf(residual)+packi(stamps)
(root/'reports/buoyant-transaction-input.bin').write_bytes(payload())
cases=[dict(name='valid',path=path,accepted=True,work=work(c,m,n,path,(0.,.00002),.01,.5))]
reverse=list(reversed(path));reverse_work=work(c,m,n,reverse,(0.,.00002),.01,.5)
assert reverse_work>0
cases.append(dict(name='automatic',path=[],accepted=True,automatic=True,work=cases[0]['work']))
cases.append(dict(name='uphill',path=reverse,accepted=False,reason=8))
for name,indices,reason in [('duplicate',[path[1]]+path[1:],4),('wall',[0]+path[1:],2),('outside',[cells]+path[1:],2)]:
 cases.append(dict(name=name,path=indices,accepted=False,reason=reason))
apply(c,m,f,residual,stamps,path,90000)
(root/'reports/buoyant-transaction-expected.bin').write_bytes(payload())
def rotate_payload(data):
 out=b'';offset=0
 for stride in (4,36,4,8,4,4):
  block=data[offset:offset+cells*stride];offset+=cells*stride
  out+=b''.join(block[i*stride:(i+1)*stride] for i in reversed(range(cells)))
 return out
for kind in ('input','expected'):
 raw=(root/('reports/buoyant-transaction-'+kind+'.bin')).read_bytes()
 (root/('reports/buoyant-transaction-'+kind+'-rotated.bin')).write_bytes(rotate_payload(raw))
cases.append(dict(name='automatic_rotated',path=[],accepted=True,automatic=True,seed=213,gravity=[0.,-.00002],work=cases[0]['work'],input_file='buoyant-transaction-input-rotated.bin',expected_file='buoyant-transaction-expected-rotated.bin'))
(root/'reports/buoyant-transaction-fixture.json').write_text(json.dumps(dict(cases=cases,input_sha256=r['input_sha256'],scope='Real phase/material/populations; zero residual and fresh movement stamps are explicit test initial conditions, not exact historical checkpoint restoration.')),encoding='utf-8')
