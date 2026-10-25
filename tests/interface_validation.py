"""Quantify known-solution transport error; no physical calibration claim."""
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from test_interface_transport import translated_wave

results=[]
for n in (32,64):
    for square in (False,True):
        for muscl in (False,True):
            initial,state=translated_wave(n,muscl,square)
            result=dict(size=n,shape='step' if square else 'sinusoid',
                        scheme='muscl' if muscl else 'upwind',
                        l1_error=sum(abs(a-b) for a,b in zip(initial,state[0]))/n,
                        mixing=sum(v*(1-v) for v in state[0])/n,
                        inventory_error=abs(sum(initial)-sum(state[0]))/n,
                        minimum=min(state[0]),maximum=max(state[0]))
            results.append(result)
            print(json.dumps(result))
(ROOT/'reports/interface-transport-validation.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
