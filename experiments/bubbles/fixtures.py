"""Fixed small-step E2 GPU fixtures; adaptive time selection remains host-side."""
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from experiments.bubbles.model import Bubble, BubbleCell, Grain
from experiments.bubbles.run_experiment import make_case


def packed(cell):
    values=[]
    for grain in cell.grains:
        values += [grain.x,grain.y,grain.radius,0,0,grain.material,grain.density,0]
    for bubble in cell.bubbles:
        values += [bubble.x,bubble.y,bubble.radius,bubble.log_aspect,1,0,0,0]
    return values


def main():
    cells = [('rise',BubbleCell(bubbles=[Bubble(0.5,0.6,0.12)],contact_stiffness=10)),
             ('relax',BubbleCell(bubbles=[Bubble(0.5,0.5,0.12,0.3)],gravity=(0,0),shape_mobility=30,contact_stiffness=10)),
             ('contact',BubbleCell(grains=[Grain(0.5,0.375,0.02,1)],bubbles=[Bubble(0.5,0.5,0.12)],contact_stiffness=10)),
             ('pair',BubbleCell(bubbles=[Bubble(0.4,0.5,0.1),Bubble(0.595,0.5,0.1)],contact_stiffness=10)),
             ('layer',make_case('two'))]
    cases=[]
    for name,cell in cells:
        initial=packed(cell)
        dt,steps=0.0002,1000
        for _ in range(steps):
            before=cell.substeps
            cell.step(dt)
            assert cell.substeps-before==1, 'Fixture requires a smaller fixed dt'
        cases.append(dict(name=name,initial=initial,expected=packed(cell),dt=dt,steps=steps,
                          gravity=cell.gravity,extent=[cell.width,cell.height],tension=cell.tension,
                          stiffness=cell.contact_stiffness,grain_drag=cell.grain_drag,
                          bubble_drag=cell.bubble_drag,shape_mobility=cell.shape_mobility))
    (ROOT/'reports/bubble-gpu-fixtures.json').write_text(json.dumps(cases,indent=2),encoding='utf-8')
    print(f'Generated {len(cases)} E2 GPU fixtures')


if __name__=='__main__':
    main()
