#!/usr/bin/env python3
"""Read-only GLB triangle/UV landmark probe. No image editing or mesh mutation."""
from pathlib import Path
import struct,json,math,hashlib
ROOT=Path(__file__).resolve().parents[4]
RAW=ROOT/'assets/models/haru-cute-pilot/raw/CH_Haru_JRPG_Pilot_Raw.glb'
OUT=ROOT/'assets/models/haru-cute-pilot/review/texture-face'
INPUTS=ROOT/'assets/models/haru-cute-pilot/production-inputs/texture-face'
def read_mesh():
 b=RAW.read_bytes();n=struct.unpack_from('<I',b,12)[0];d=json.loads(b[20:20+n]);offset=20+n;blen=struct.unpack_from('<I',b,offset)[0];data=b[offset+8:offset+8+blen]
 def accessor(i):
  a=d['accessors'][i];v=d['bufferViews'][a['bufferView']];dim={'SCALAR':1,'VEC2':2,'VEC3':3}[a['type']];fmt={5126:'f',5125:'I'}[a['componentType']];stride=v.get('byteStride',dim*4);start=v.get('byteOffset',0)+a.get('byteOffset',0);return [struct.unpack_from('<'+fmt*dim,data,start+j*stride) for j in range(a['count'])]
 p=d['meshes'][0]['primitives'][0];return accessor(p['attributes']['POSITION']),accessor(p['attributes']['TEXCOORD_0']),[x[0] for x in accessor(p['indices'])]
def bary(point,a,b,c):
 den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
 if abs(den)<1e-12:return None
 u=((b[1]-c[1])*(point[0]-c[0])+(c[0]-b[0])*(point[1]-c[1]))/den;v=((c[1]-a[1])*(point[0]-c[0])+(a[0]-c[0])*(point[1]-c[1]))/den;w=1-u-v
 return (u,v,w) if min(u,v,w)>=-1e-6 else None
def interpolate(values,weights):return [sum(v[k]*w for v,w in zip(values,weights)) for k in range(len(values[0]))]
def uv_to_xyz(point,verts,uvs,indices):
 hits=[]
 for i in range(0,len(indices),3):
  ids=indices[i:i+3];weights=bary(point,*[uvs[j] for j in ids])
  if weights:hits.append({'position':interpolate([verts[j] for j in ids],weights),'triangle':i//3,'weights':weights})
 return hits
def front_ray(x,y,verts,uvs,indices):
 hits=[]
 for i in range(0,len(indices),3):
  ids=indices[i:i+3];weights=bary((x,y),*[verts[j][:2] for j in ids])
  if weights:
   position=interpolate([verts[j] for j in ids],weights);hits.append({'position':position,'uv':interpolate([uvs[j] for j in ids],weights),'triangle':i//3,'weights':weights})
 return max(hits,key=lambda p:p['position'][2]) if hits else None
def produce():
 v,uv,idx=read_mesh();probe={};landmarks={}
 for name,point in {'eye_image_left':(1627/2048,1497/2048),'eye_image_right':(1714/2048,1557/2048)}.items():
  probe[name]={'image_uv':point,'unflipped':uv_to_xyz(point,v,uv,idx),'flipped':uv_to_xyz((point[0],1-point[1]),v,uv,idx)}
 for name,x,y,rx,ry in [('eye_left',-.02477,.886889,.014,.0115),('eye_right',.025363,.888157,.014,.0115),('mouth',0,.8495,.0195,.006)]:
  c=front_ray(x,y,v,uv,idx);dx=front_ray(x+.001,y,v,uv,idx);dy=front_ray(x,y+.001,v,uv,idx);skin=front_ray(0,.883 if name.startswith('eye_') else .857,v,uv,idx)
  landmarks[name]={'center':c,'axis_x':[(dx['uv'][j]-c['uv'][j])*rx/.001 for j in range(2)],'axis_y':[(dy['uv'][j]-c['uv'][j])*ry/.001 for j in range(2)],'radius_3d':[rx,ry],'skin_uv':skin['uv']}
 def simplify(points,tolerance=.00008):
  if len(points)<3:return points
  a,b=points[0],points[-1];dx,dy=b[0]-a[0],b[1]-a[1];den=dx*dx+dy*dy
  distances=[]
  for point in points:
   t=max(0,min(1,((point[0]-a[0])*dx+(point[1]-a[1])*dy)/den)) if den else 0
   distances.append(math.hypot(point[0]-a[0]-dx*t,point[1]-a[1]-dy*t))
  i=max(range(len(points)),key=lambda i:distances[i])
  if distances[i]<=tolerance:return [a,b]
  return simplify(points[:i+1],tolerance)[:-1]+simplify(points[i:],tolerance)
 for name,center,curve in [('original_mouth',.8495,.0020),('smile_mouth',.8485,.0065),('tired_mouth',.8523,-.0038)]:
  runs=[[]]
  for i in range(257):
   x=(i/256*2-1)*.0165;y=center+curve*(abs(x/.0165)**1.8);hit=front_ray(x,y,v,uv,idx);point=hit['uv']
   if runs[-1] and math.dist(runs[-1][-1],point)>.015:runs.append([])
   runs[-1].append(point)
  segments=[]
  for run in runs:
   points=simplify(run)
   segments.extend([a+b for a,b in zip(points,points[1:])])
  assert len(segments)<=64,(name,len(segments))
  landmarks[name]=segments
  print(name,'UV islands/runs',len(runs),'native shader segments',len(segments))
 probe['mouth_seam_scan']=[front_ray(0,y,v,uv,idx) for y in [.855,.860,.861,.862,.863,.864,.865]]
 probe['ray']={'origin_z':.5,'direction':[0,0,-1],'selection':'Nearest positive-front intersection; barycentric interpolation of original mesh UVs.'}
 probe['source_sha256']=hashlib.sha256(RAW.read_bytes()).hexdigest()
 OUT.mkdir(parents=True,exist_ok=True)
 (OUT/'uv-probe.json').write_text(json.dumps(probe,indent=2)+'\n')
 INPUTS.mkdir(parents=True,exist_ok=True)
 (INPUTS/'landmarks.json').write_text(json.dumps(landmarks,indent=2)+'\n')
 b=RAW.read_bytes();n=struct.unpack_from('<I',b,12)[0];doc=json.loads(b[20:20+n]);data=b[28+n:];view=doc['bufferViews'][doc['images'][0]['bufferView']];(INPUTS/'source-basecolor.jpg').write_bytes(data[view.get('byteOffset',0):view.get('byteOffset',0)+view['byteLength']])
 print('Read-only face UV landmarks and unchanged embedded JPEG extracted')
if __name__=='__main__':produce()
