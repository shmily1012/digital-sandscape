"""Summarize captured real GPU material fields without inferring aesthetic success."""
import array
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]
results=[]
for name in ('phase-cycle','phase-barrier-cycle','phase-barrier-dense-cycle'):
    data=json.loads((ROOT/'reports'/f'{name}.json').read_text(encoding='utf-8'))
    samples=[]
    for sample in data['samples']:
        cells=array.array('I')
        cells.frombytes((ROOT/'reports'/f'{name}-{sample["tick"]}.materials').read_bytes())
        if sys.byteorder!='little':cells.byteswap()
        n=256
        if len(cells)!=n*n:raise ValueError('Unexpected grid size')
        lower=sum(m>=2 and i//n>=int(n*.55) for i,m in enumerate(cells))
        upper=sum(m>=2 and i//n<int(n*.45) for i,m in enumerate(cells))
        samples.append(dict(tick=sample['tick'],angle=sample['angle'],
                            grains_below_row_140=lower,grains_above_row_115=upper,
                            sand_mean_row=sample['sand_height']))
    results.append(dict(case=name,integrity_failures=data['failures'],
                        initial_gas_inventory=data['initial']['mass'],samples=samples))
(ROOT/'reports/phase-cycle-comparison.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
for case in results:
    print(case['case'], 'initial gas',round(case['initial_gas_inventory'],3),
          'tick8000',case['samples'][1])
