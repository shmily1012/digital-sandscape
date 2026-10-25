"""Prototype: reusable discrete projector kernel plus circular Neumann correction.

Uniform mobility only; compact particle support must remain well inside the
circle. This approximates the staircase boundary with a smooth circle.
"""
import json
import math
from pathlib import Path
from experiments.liquid.grain_coupling import face_weights

def build_kernel(period=512,radius=4):
    import sys
    sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'.tools/plot-libs'))
    import numpy as np
    k=2*np.pi*np.fft.fftfreq(period)
    dx=1-np.exp(-1j*k)[None,:]
    dy=1-np.exp(-1j*k)[:,None]
    denominator=abs(dx)**2+abs(dy)**2
    denominator[0,0]=1
    result=[]
    for a,d in enumerate((dx,dy)):
        for b,e in enumerate((dx,dy)):
            operator=(1 if a==b else 0)-d.conjugate()*e/denominator
            real=np.fft.ifft2(operator).real
            result.append([[float(real[y%period,x%period]) for x in range(-radius,radius+1)] for y in range(-radius,radius+1)])
    return dict(period=period,radius=radius,values=result)

def estimate(grid,grain,kernel,container_radius=.46):
    if any(abs(m-1)>1e-12 for _,_,m,_ in grid.faces):raise ValueError('Uniform unit mobility required')
    if math.hypot(grain.x-.5,grain.y-.5)+4*grid.h>=container_radius:
        raise ValueError('Kernel approximation outside validated interior region')
    weights=face_weights(grid,grain)
    support=[[],[]]
    for weight,(i,j,_,axis) in zip(weights,grid.faces):
        if weight<=0:continue
        x,y=i%grid.size,i//grid.size
        center=complex((x+1 if axis==0 else x+.5)*grid.h-.5,(y+.5 if axis==0 else y+1)*grid.h-.5)
        support[axis].append((x,y,center,weight))
    radius=kernel['radius']
    response=[]
    for a in range(2):
        for b in range(2):
            value=0.0
            for x,y,z,w in support[a]:
                for xx,yy,zz,ww in support[b]:
                    dx,dy=x-xx,y-yy
                    if max(abs(dx),abs(dy))>radius:raise ValueError('Kernel stencil too short')
                    infinite=kernel['values'][2*a+b][dy+radius][dx+radius]/grid.h**2
                    harmonic=1/(2*math.pi*container_radius**2*(1-z*zz.conjugate()/container_radius**2)**2)
                    boundary=harmonic.real if a==b else (harmonic.imag if a==0 else -harmonic.imag)
                    value+=w*ww*(infinite-boundary)
            response.append(value)
    return response
