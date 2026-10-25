"""Scientific diagnostics of computed state, never a product rendering."""
import json
import os
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'.tools/plot-libs'))
sys.path.insert(0,str(ROOT))
os.environ['MPLCONFIGDIR']=str(ROOT/'.tools/matplotlib')
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
from experiments.liquid.model import DarcyGrid,circle_mask

grid=DarcyGrid(24,circle_mask(24))
prescribed=grid.prescribed_patch()
solution=grid.project(prescribed)
u,v,counts=np.zeros(576),np.zeros(576),np.zeros((2,576))
for q,(i,j,_,axis) in zip(solution.liquid,grid.faces):
    array=u if axis==0 else v
    for cell in (i,j):
        array[cell]+=q
        counts[axis,cell]+=1
u/=np.maximum(1,counts[0]); v/=np.maximum(1,counts[1])
mask=np.array(grid.active).reshape(24,24)
pressure=np.array(solution.pressure).reshape(24,24)
pressure[~mask]=np.nan
fig,ax=plt.subplots(figsize=(6,6),layout='constrained')
im=ax.imshow(pressure,extent=(0,1,1,0),cmap='RdBu_r')
x,y=np.meshgrid((np.arange(24)+0.5)/24,(np.arange(24)+0.5)/24)
ax.quiver(x[::2,::2],y[::2,::2],u.reshape(24,24)[::2,::2],v.reshape(24,24)[::2,::2],angles='xy',scale_units='xy',scale=0.3)
ax.set_title('Pressure and liquid return flux\nPrescribed downward inclusion flux; dimensionless')
fig.colorbar(im,ax=ax,label='pressure')
fig.savefig(ROOT/'reports/liquid-returnflow.png',dpi=160)
plt.close(fig)

report=json.loads((ROOT/'reports/liquid-transport.json').read_text(encoding='utf-8'))
fig,axes=plt.subplots(2,len(report['snapshots']),figsize=(15,6),layout='constrained')
for column,frame in enumerate(report['snapshots']):
    channels=np.array(frame['fractions']).reshape(5,24,24)
    for row,field in enumerate((channels[1:4].sum(axis=0),channels[4])):
        field=field.copy(); field[~mask]=np.nan
        axes[row,column].imshow(field,vmin=0,vmax=0.7,cmap='magma',extent=(0,1,1,0))
        axes[row,column].set_title(f"t={frame['time']:.2f}")
        axes[row,column].set_xticks([]); axes[row,column].set_yticks([])
axes[0,0].set_ylabel('Sand fraction')
axes[1,0].set_ylabel('Gas fraction')
fig.suptitle('Computed fraction transport / rotation after t=4.5\nNo capillarity or contacts: numerical diffusion is visible; not an artwork')
fig.savefig(ROOT/'reports/liquid-transport.png',dpi=150)
plt.close(fig)

comparison=ROOT/'reports/liquid-transport-muscl.json'
if comparison.exists():
    high=json.loads(comparison.read_text(encoding='utf-8'))
    fig,axes=plt.subplots(2,5,figsize=(15,6),layout='constrained')
    for row,result in enumerate((report,high)):
        for column,frame in enumerate(result['snapshots']):
            field=np.array(frame['fractions'][4]).reshape(24,24)
            field[~mask]=np.nan
            axes[row,column].imshow(field,vmin=0,vmax=0.7,cmap='magma',extent=(0,1,1,0))
            axes[row,column].set_title(f"t={frame['time']:.2f}")
            axes[row,column].set_xticks([]); axes[row,column].set_yticks([])
    axes[0,0].set_ylabel('Upwind / Euler')
    axes[1,0].set_ylabel('Limited linear / SSP RK2')
    fig.suptitle('Actual gas-fraction transport, same initial state and rotation\nNeither model has capillarity or contact mechanics')
    fig.savefig(ROOT/'reports/interface-transport-comparison.png',dpi=150)
