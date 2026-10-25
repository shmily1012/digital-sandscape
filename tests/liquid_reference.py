"""CPU specification for the integrated conservative liquid/gas grid approximation."""
from reference_model import *
from pathlib import Path

def liquid_initial(n,seed):
 data=initial_state(n,seed)
 for y in range(n):
  for x in range(n):
   if data[y*n+x]!=0:continue
   for b in range(7):
    h=hash32(seed^(b*1597334677));cx=n*(.18+.105*b+(((h>>8)%17)-8)*.0015);cy=n*(.51+((h>>16)%17)*.002);r=n*(.023+(h%9)*.002)
    if (x-cx)**2+(y-cy)**2<r*r:data[y*n+x]=5
 return data

def liquid_step(cells,n,seed,tick,g):
 for phase in range(2):
  before=cells.copy()
  def neighbors(q,excluded):
   return sum(before[(q[1]+dy)*n+q[0]+dx]==5 for dy in (-1,0,1) for dx in (-1,0,1) if (dx or dy) and 0<=q[0]+dx<n and 0<=q[1]+dy<n and (q[0]+dx,q[1]+dy)!=excluded)
  for bx,by,indices in blocks(n,phase):
   value=[before[i] if i is not None else 4 for i in indices]
   rng=hash32(seed^((tick*747796405)&MASK)^((phase*2891336453)&MASK)^((bx*277803737)&MASK)^((by*1597334677)&MASK))
   total=0;source=target=-1
   for a in range(4):
    if value[a] in (0,4):continue
    qa=(bx*2-phase+OFFSETS[a][0],by*2-phase+OFFSETS[a][1])
    down=((1 if g[0]>0 else -1 if g[0]<0 else 0),0) if abs(g[0])>abs(g[1]) else (0,(1 if g[1]>0 else -1 if g[1]<0 else 0))
    support=(qa[0]+down[0],qa[1]+down[1])
    resting=value[a]!=5 and (not(0<=support[0]<n and 0<=support[1]<n) or before[support[1]*n+support[0]]!=0)
    for b in range(4):
     if value[b]!=0:continue
     dx=OFFSETS[b][0]-OFFSETS[a][0];dy=OFFSETS[b][1]-OFFSETS[a][1]
     projection=dx*g[0]+dy*g[1]
     if value[a]==5:
      qa=(bx*2-phase+OFFSETS[a][0],by*2-phase+OFFSETS[a][1]);qb=(bx*2-phase+OFFSETS[b][0],by*2-phase+OFFSETS[b][1])
      projection=-projection+14000*(neighbors(qb,qa)-neighbors(qa,qb))
     if value[a]!=5 and not resting:
      if abs(dx)+abs(dy)!=1 or projection<=0:continue
     elif projection<=6000*(abs(dx)+abs(dy)):continue
     total+=projection;rng=hash32(rng+0x9e3779b9)
     if rng%total<projection:source,target=a,b
   if source>=0:
    rng=hash32(rng+0x9e3779b9)
    if rng&255<(100 if value[source]==5 else MOBILITY[value[source]]//3):value[target],value[source]=value[source],0
   for i,m in zip(indices,value):
    if i is not None:cells[i]=m
 return cells
if __name__=='__main__':
 cells=liquid_initial(32,709)
 for tick in range(70):liquid_step(cells,32,709,tick,gravity(tick*3.75))
 Path('reports/liquid_gpu_expected.bin').write_bytes(struct.pack('<'+'I'*len(cells),*cells))
