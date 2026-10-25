"""Independent dense/operator persistent history trajectories and volume audit."""
from pathlib import Path
from dataclasses import asdict
import sys,json,time
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.liquid.grain_coupling import Grain
from experiments.deposition.contact_particles import Plane,ContactConvergenceError
from experiments.deposition.drainage_resistance import DrainageResistance
from experiments.deposition.history_contacts import advance_history_contacts
from experiments.deposition.operator_history import advance_operator_history
from experiments.deposition.tangential_history import snapshot,restore
from experiments.deposition.disk_volume import occupancy,swept_flux

def main():
    grid=DarcyGrid(24,circle_mask(24));ids=[10,20,30,40]
    grains=[Grain(x,y,.04,.04,2.65-.1*i,1+i%3) for i,(x,y) in enumerate(((.46,.6),(.54,.6),(.46,.52),(.54,.52)))]
    dense_grains=list(grains);history={};dense_history={};rows=[];dt=.01;initial=occupancy(grid,grains)
    integral=[0.]*len(grid.faces);kw=dict(planes=[Plane(0,-1,-.64)],plane_ids=[-1],stiffness=1.)
    refused=False;restored=False
    for tick in range(40):
        gravity=(.3,1) if tick<12 else ((-.3,1) if tick<24 else (0,-1))
        if tick==12:
            packed=json.loads(json.dumps(dict(grains=[asdict(g) for g in grains],history=snapshot(history))))
            grains=[Grain(**g) for g in packed['grains']];history=restore(packed['history']);restored=True
        if tick==24:
            saved=snapshot(history);original=list(grains)
            try:advance_operator_history(grid,grains,ids,history,gravity,dt,max_outer=1,**kw)
            except ContactConvergenceError:refused=snapshot(history)==saved and grains==original
            if not refused:raise RuntimeError('Missing transactional refusal')
        start=time.perf_counter();model=DrainageResistance(grid,dense_grains,geometric=True)
        expected=advance_history_contacts(dense_grains,ids,dense_history,gravity,dt,mobility_matrix=model.mobility,**kw)
        dense_ms=1000*(time.perf_counter()-start)
        start=time.perf_counter();answer=advance_operator_history(grid,grains,ids,history,gravity,dt,**kw)
        operator_ms=1000*(time.perf_counter()-start);actual=answer.candidate
        position_error=max(abs(a-b) for ga,gb in zip(expected.contact.grains,actual.contact.grains) for a,b in ((ga.x,gb.x),(ga.y,gb.y)))
        keys=set(actual.history)|set(expected.history)
        history_error=max((abs((actual.history[k].elastic_slip if k in actual.history else 0)-(expected.history[k].elastic_slip if k in expected.history else 0)) for k in keys),default=0.)
        solid=swept_flux(grid,grains,actual.contact.grains,dt);liquid=grid.project(solid).liquid
        integral=[a+dt*b for a,b in zip(integral,liquid)];phi=occupancy(grid,actual.contact.grains)
        volume_error=max(abs((1-a)-d-(1-b)) for a,b,d in zip(initial,phi,grid.divergence(integral)))
        old_energy=sum(.5*s.stiffness*s.elastic_slip**2 for s in history.values())
        energy_error=abs(actual.work_into_springs-(actual.elastic_energy-old_energy)-actual.dissipated)
        row=dict(tick=tick+1,position_error=position_error,history_error=history_error,
                 history_keys_match=set(actual.history)==set(expected.history),volume_error=volume_error,
                 energy_error=energy_error,dense_ms=dense_ms,operator_ms=operator_ms,
                 iterations=answer.iterations,pressure_solves=answer.pressure_solves)
        rows.append(row)
        if not row["history_keys_match"] or max(position_error,history_error)>1e-8 or volume_error>1e-9 or energy_error>1e-10:raise RuntimeError(f'Cycle mismatch: {row}')
        grains=actual.contact.grains;history=actual.history;dense_grains=expected.contact.grains;dense_history=expected.history
        if (tick+1)%10==0:print(json.dumps(row),flush=True)
    report=dict(scope='CPU four-grain 40-step persistent history comparison; no gas, spin, adaptive substeps or GPU',
                rows=rows,failures=0,restored=restored,budget_rejection_retained=refused,elapsed=40*dt)
    (ROOT/'reports/operator-history-cycle.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
if __name__=='__main__':main()
