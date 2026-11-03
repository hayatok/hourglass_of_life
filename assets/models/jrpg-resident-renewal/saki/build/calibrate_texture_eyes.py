#!/usr/bin/env python3
"""Calibrate each raw resident independently; no source image, geometry or core edits."""
from pathlib import Path
import hashlib,json,math,struct
ROOT=Path(__file__).resolve().parents[5]
CAST=ROOT/'assets/models/jrpg-resident-renewal'

def mesh(path):
 b=path.read_bytes();n=struct.unpack_from('<I',b,12)[0];doc=json.loads(b[20:20+n]);binary=b[28+n:]
 def accessor(i):
  a=doc['accessors'][i];v=doc['bufferViews'][a['bufferView']];dim={'SCALAR':1,'VEC2':2,'VEC3':3}[a['type']];fmt={5126:'f',5125:'I',5123:'H'}[a['componentType']];size=struct.calcsize('<'+fmt*dim);stride=v.get('byteStride',size);start=v.get('byteOffset',0)+a.get('byteOffset',0)
  return [struct.unpack_from('<'+fmt*dim,binary,start+j*stride) for j in range(a['count'])]
 p=doc['meshes'][0]['primitives'][0]
 return doc,binary,accessor(p['attributes']['POSITION']),accessor(p['attributes']['TEXCOORD_0']),[x[0] for x in accessor(p['indices'])]

def bary(p,a,b,c):
 den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
 if abs(den)<1e-12:return None
 u=((b[1]-c[1])*(p[0]-c[0])+(c[0]-b[0])*(p[1]-c[1]))/den;v=((c[1]-a[1])*(p[0]-c[0])+(a[0]-c[0])*(p[1]-c[1]))/den;w=1-u-v
 return (u,v,w) if min(u,v,w)>=-1e-6 else None

def interpolate(items,weights):return [sum(v[i]*w for v,w in zip(items,weights)) for i in range(len(items[0]))]

def uv_point(point,vertices,uvs,indices):
 hits=[]
 for i in range(0,len(indices),3):
  ids=indices[i:i+3];weights=bary(point,*[uvs[j] for j in ids])
  if weights:hits.append({'position':interpolate([vertices[j] for j in ids],weights),'uv':list(point),'triangle':i//3})
 if not hits:raise ValueError(f'UV has no triangle: {point}')
 return max(hits,key=lambda h:h['position'][2])

def front_ray(x,y,vertices,uvs,indices):
 hits=[]
 for i in range(0,len(indices),3):
  ids=indices[i:i+3];weights=bary((x,y),*[vertices[j][:2] for j in ids])
  if weights:hits.append({'position':interpolate([vertices[j] for j in ids],weights),'uv':interpolate([uvs[j] for j in ids],weights),'triangle':i//3})
 if not hits:raise ValueError(f'Front ray misses: {x},{y}')
 return max(hits,key=lambda h:h['position'][2])

def calibrate(rid):
 folder=CAST/rid;raw=next((folder/'raw').glob('*.glb'));cfg=json.loads((folder/'build/eye-calibration.json').read_text());doc,binary,verts,uvs,indices=mesh(raw);output=folder/'review/texture-eyes';output.mkdir(parents=True,exist_ok=True)
 im=doc['images'][0];view=doc['bufferViews'][im['bufferView']];start=view.get('byteOffset',0);source=binary[start:start+view['byteLength']];(output/'source-basecolor.jpg').write_bytes(source)
 guesses=[uv_point([x/2048 for x in point],verts,uvs,indices) for point in cfg['iris_pixels']]
 guesses.sort(key=lambda h:h['position'][0])
 distance=guesses[1]['position'][0]-guesses[0]['position'][0]
 assert distance>.02,(rid,guesses)
 eyes={};rays={};eye_y=sum(h['position'][1] for h in guesses)/2
 for side,point in zip(['left','right'],guesses):
  x,y,z=point['position'];offset=cfg.get('center_offset_raw',{}).get(side,[0,0]);x+=offset[0];y+=offset[1];center=front_ray(x,y,verts,uvs,indices);dx=front_ray(x+.001,y,verts,uvs,indices);dy=front_ray(x,y+.001,verts,uvs,indices)
  assert math.dist(center['uv'],dx['uv'])<.02 and math.dist(center['uv'],dy['uv'])<.02,(rid,side,'local UV seam')
  scale=cfg.get('radius_scale',{}).get(side,[1,1]);rx=distance*cfg['radius_x_fraction']*scale[0];ry=distance*cfg['radius_y_fraction']*scale[1]
  sx=(-1 if side=='left' else 1)*distance*.12
  skin=front_ray(sx,eye_y+cfg.get('skin_y_offset',-.004),verts,uvs,indices)
  eye={'center':center['uv'],'axis_x':[(dx['uv'][j]-center['uv'][j])*rx/.001 for j in range(2)],'axis_y':[(dy['uv'][j]-center['uv'][j])*ry/.001 for j in range(2)],'skin_uv':skin['uv']}
  determinant=eye['axis_x'][0]*eye['axis_y'][1]-eye['axis_x'][1]*eye['axis_y'][0]
  assert abs(determinant)>1e-8
  eyes[side]=eye;rays[side]={'center':center,'skin':skin,'radius_raw_units':[rx,ry],'uv_basis_determinant':determinant}
 layout={'schema_version':1,'implementation':'UV eye shader candidate: Blink and TiredEyes only; no facial morph or mouth control.','resident':rid,'source_raw_sha256':hashlib.sha256(raw.read_bytes()).hexdigest(),'source_basecolor_jpeg_sha256':hashlib.sha256(source).hexdigest(),'calibration':'Each eye independently annotated on this raw atlas, then front-ray barycentric UV calibrated; no Haru coordinates reused.','eyes':eyes}
 extras=[]
 for patch in cfg.get('additional_eye_patches',[]):
  side=patch['eye'];x,y=patch['probe_raw'];step=.0003
  p=front_ray(x,y,verts,uvs,indices);px=front_ray(x+step,y,verts,uvs,indices);py=front_ray(x,y+step,verts,uvs,indices)
  assert math.dist(p['uv'],px['uv'])<.02 and math.dist(p['uv'],py['uv'])<.02
  jx=[(px['uv'][i]-p['uv'][i])/step for i in range(2)];jy=[(py['uv'][i]-p['uv'][i])/step for i in range(2)]
  center=rays[side]['center']['position'];rx,ry=rays[side]['radius_raw_units']
  extra={'eye':side,'center':[p['uv'][i]+jx[i]*(center[0]-x)+jy[i]*(center[1]-y) for i in range(2)],'axis_x':[a*rx for a in jx],'axis_y':[a*ry for a in jy],'skin_uv':eyes[side]['skin_uv']}
  extras.append(extra);rays[side]['additional_chart']={'probe':p,'step':step,'same_physical_eye_center':center}

 if extras:
  layout['additional_eye_patches']=extras;layout['calibration_note']='One physical eye crosses a UV seam, so one extra affine chart covers the same physical eye on the other island.'
 layout['eyelid_method']=cfg.get('eyelid_method','compress')
 (output/'face-layout-candidate.json').write_text(json.dumps(layout,indent=2)+'\n')
 (output/'ray-calibration.json').write_text(json.dumps({'resident':rid,'raw':str(raw.relative_to(ROOT)),'eye_rays':rays,'eye_distance_raw_units':distance,'eye_y':eye_y,'camera_y':eye_y+.012,'camera_size':cfg.get('camera_size',.245),'source_sha256':layout['source_raw_sha256'],'status':'Raw static candidate; rig/LOD and actual actor validation pending.'},indent=2)+'\n')
 print(rid,json.dumps({'left':guesses[0]['position'],'right':guesses[1]['position'],'camera_y':eye_y+.012}))
 return layout
if __name__=='__main__':
 import sys
 for rid in sys.argv[1:] or ['saki','tomo','yui']:calibrate(rid)
