"""Directed scalar load routing. Contacts/friction/arching are not resolved."""
import math

WEIGHT={2:2.,3:1.7,4:1.4}


def loads(material,n,gravity):
    gx,gy=gravity
    norm=abs(gx)+abs(gy)
    if norm==0:return [0.]*len(material)
    sx,sy=abs(gx)/norm,abs(gy)/norm
    def index(x,y):
        return (n-1-y if gy<0 else y)*n+(n-1-x if gx<0 else x)
    result=[0.]*len(material)
    for y in range(n):
        for x in range(n):
            i=index(x,y);value=WEIGHT.get(material[i],0.)
            if x>0 and material[index(x-1,y)]>=2:value+=sx*result[index(x-1,y)]
            if y>0 and material[index(x,y-1)]>=2:value+=sy*result[index(x,y-1)]
            result[i]=value
    return result


def fixture():
    n=19
    m=[1 if x in (0,n-1) or y in (0,n-1) else (2+(x+y)%3 if (x*7+y*11)%5<3 else 0) for y in range(n) for x in range(n)]
    for y in range(2,n-2):m[y*n+4]=2
    cases=[]
    for angle in (0,13,30,45,90,120,180,270):
        g=(math.sin(math.radians(angle)),math.cos(math.radians(angle)))
        cases.append(dict(angle=angle,gravity=g,expected=loads(m,n,g)))
    cases.append(dict(angle=None,gravity=(0.,0.),expected=loads(m,n,(0.,0.))))
    return dict(side=n,materials=m,cases=cases,total_weight=sum(WEIGHT.get(v,0.) for v in m))


if __name__=='__main__':
    import json
    from pathlib import Path
    (Path(__file__).resolve().parents[1]/'reports/grain-load-fixture.json').write_text(json.dumps(fixture()),encoding='utf-8')
