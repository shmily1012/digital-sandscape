"""Conservative interface GPU fixtures, independent of rendering."""
import json
import math
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.liquid.capillary import circle_fractions
from experiments.liquid.geometric_transport import advect


def main():
    cases=[]
    for name,n,periodic,speed,steps in [('translation',32,True,(0.2,0),50),('diagonal',32,True,(0.12,-0.08),50),('sealed_vortex',32,False,(0,0),50),('circular_returnflow',32,False,(0,0),50),('zero',16,False,(0,0),10)]:
        grid=DarcyGrid(n,circle_mask(n) if name=='circular_returnflow' else None)
        if periodic:
            grid.faces=[]
            for y in range(n):
                for x in range(n):
                    i=y*n+x
                    grid.faces.extend(((i,y*n+(x+1)%n,1,0),(i,((y+1)%n)*n+x,1,1)))
        velocity=[speed[axis] for i,j,m,axis in grid.faces]
        if name=='circular_returnflow':
            velocity=grid.project(grid.prescribed_patch()).mixture
        if name=='sealed_vortex':
            psi=lambda x,y:0.02*math.sin(math.pi*x/n)**2*math.sin(math.pi*y/n)**2
            for f,(i,j,m,axis) in enumerate(grid.faces):
                x,y=i%n,i//n
                velocity[f]=(psi(x+1,y+1)-psi(x+1,y))*n if axis==0 else -(psi(x+1,y+1)-psi(x,y+1))*n
        initial=circle_fractions(n,radius=0.15,center=(0.37,0.46))
        current=initial.copy()
        dt=0.02
        for _ in range(steps):
            current,accepted=advect(grid,current,velocity,dt)
            assert abs(accepted-dt)<1e-12
        neighbors=[[-1]*4 for _ in current]
        adjacency=[[-1]*4 for _ in current]
        for index,(i,j,m,axis) in enumerate(grid.faces):
            neighbors[i][axis*2+1]=j;neighbors[j][axis*2]=i
            adjacency[i][axis*2+1]=index;adjacency[j][axis*2]=index
        cases.append(dict(name=name,size=n,steps=steps,dt=dt,initial=initial,expected=current,active=grid.active,
                          neighbors=sum(neighbors,[]),adjacency=sum(adjacency,[]),
                          faces=[[i,j,v,axis] for (i,j,m,axis),v in zip(grid.faces,velocity)]))
        print(name,steps,'area error',abs(sum(current)-sum(initial))/(n*n),flush=True)
    (ROOT/'reports/geometric-fixtures.json').write_text(json.dumps(cases),encoding='utf-8')


if __name__=='__main__':main()
