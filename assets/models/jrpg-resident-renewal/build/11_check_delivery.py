"""Numerical UV, decoded texture, skin, rig and clip checks on delivered GLBs.

Source hashes and decoded input texture identity are provenance, never checks.
"""
from pathlib import Path
from PIL import Image,ImageChops
import sys,json,math,struct,io
sys.path.insert(0,str(Path(__file__).resolve().parent));import gltf_io
ROOT=Path(__file__).resolve().parents[1]
SPECS=json.loads((ROOT/'build/specs.json').read_text());ident=sys.argv[1];s=SPECS[ident]
formats={5120:'b',5121:'B',5122:'h',5123:'H',5125:'I',5126:'f'}
components={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
def accessor(doc,binary,index):
 a=doc['accessors'][index];count=components[a['type']];fmt='<'+formats[a['componentType']]*count;size=struct.calcsize(fmt)
 if 'bufferView' not in a:values=[tuple(0 for _ in range(count)) for _ in range(a['count'])]
 else:
  view=doc['bufferViews'][a['bufferView']];start=view.get('byteOffset',0)+a.get('byteOffset',0);stride=view.get('byteStride',size);values=[struct.unpack_from(fmt,binary,start+i*stride) for i in range(a['count'])]
 if a.get('normalized'):
  divisor={5120:127,5121:255,5122:32767,5123:65535}[a['componentType']];values=[tuple(max(-1,v/divisor) for v in row) for row in values]
 if a.get('sparse'):raise ValueError('Sparse accessor requires explicit review')
 return values
def flatten_uv(doc,binary):
 rows=[]
 for mesh in doc['meshes']:
  for p in mesh['primitives']:
   uv=accessor(doc,binary,p['attributes']['TEXCOORD_0']);indices=[r[0] for r in accessor(doc,binary,p['indices'])] if 'indices' in p else range(len(uv));rows.extend(uv[i] for i in indices)
 return sorted(rows)
def joints(doc,binary):
 skin=doc['skins'][0];nodes=[doc['nodes'][i] for i in skin['joints']]
 return {'names':[n['name'] for n in nodes],'rest':[{k:n.get(k) for k in ['matrix','translation','rotation','scale']} for n in nodes],'inverse_bind_matrices':accessor(doc,binary,skin['inverseBindMatrices'])}
def clips(doc,binary):
 out={}
 for animation in doc['animations']:
  channels={}
  for c in animation['channels']:
   sampler=animation['samplers'][c['sampler']];target=c['target'];key=doc['nodes'][target['node']]['name']+'/'+target['path'];channels[key]={'times':accessor(doc,binary,sampler['input']),'values':accessor(doc,binary,sampler['output']),'interpolation':sampler.get('interpolation','LINEAR')}
  out[animation['name']]=channels
 return out
raw=ROOT/ident/f'raw/CH_{s["name"]}_JRPG_Raw.glb';out=ROOT/ident/'exports';source,sbin=gltf_io.read(raw);base,bbin=gltf_io.read(out/f'CH_{s["name"]}.glb')
checks=[]
def check(name,ok,details):checks.append({'name':name,'pass':bool(ok),'details':details})
ruv=flatten_uv(source,sbin);buv=flatten_uv(base,bbin);uvdiff=max((abs(a-b) for row_a,row_b in zip(ruv,buv) for a,b in zip(row_a,row_b)),default=math.inf)
check('Actual triangle-corner UV coordinates preserved',len(ruv)==len(buv) and uvdiff<1e-6,{'source_corners':len(ruv),'delivery_corners':len(buv),'max_abs_coordinate_difference':uvdiff})
image_rows=[]
for a,b in zip(source['images'],base['images']):
 ia=Image.open(io.BytesIO(gltf_io.view_bytes(source,sbin,a['bufferView']))).convert('RGBA');ib=Image.open(io.BytesIO(gltf_io.view_bytes(base,bbin,b['bufferView']))).convert('RGBA');diff=ImageChops.difference(ia,ib) if ia.size==ib.size else None
 image_rows.append({'name':a.get('name'),'source_size':ia.size,'delivery_size':ib.size,'nonzero_difference_bbox':list(diff.getbbox(alpha_only=False)) if diff and diff.getbbox(alpha_only=False) else None,'channel_difference_extrema':diff.getextrema() if diff else None,'equal_pixels':diff is not None and not any(maximum for minimum,maximum in diff.getextrema())})
# Input identity remains provenance even when compared as pixels rather than hashes.
# It has no acceptance outcome and does not add a replacement functional check.
base_joints=joints(base,bbin);base_clips=clips(base,bbin);expected={'idle','walk','talk','work','wave','sit_talk','eat','rest','sleep'}
check('Required animated clip set imported',set(base_clips)==expected,{'names':list(base_clips)})
if s['skirt']:
 key='DEF-skirt_middle/rotation';walk=base_clips['walk'][key]['values'][0];seated=base_clips['sit_talk'][key]['values'][0];dot=abs(sum(a*b for a,b in zip(walk,seated)));angle=2*math.acos(min(1.,dot))
 check('Seated garment helper rotation is actually baked',angle>.5,{'middle_helper_walk_to_seated_angle_radians':angle})
manifest=json.loads((out/'asset-manifest.json').read_text());contract=manifest['runtime_contract']
check('Actual rig and skin bind names agree with contract',base_joints['names']==contract['skin_bind_names'] and len(base_joints['names'])==contract['bone_count'],{'joint_names':base_joints['names'],'bind_count':len(base_joints['names'])})
lods=[]
for level in [0,1,2]:
 path=out/f'CH_{s["name"]}{"_LOD"+str(level) if level else ""}.glb';doc,binary=gltf_io.read(path);triangles=0;maximum_influences=0;max_sum_error=0.;valid=True
 for mesh in doc['meshes']:
  for p in mesh['primitives']:
   triangles+=doc['accessors'][p['indices']]['count']//3;weights=accessor(doc,binary,p['attributes']['WEIGHTS_0']);jointrows=accessor(doc,binary,p['attributes']['JOINTS_0'])
   for w,j in zip(weights,jointrows):
    maximum_influences=max(maximum_influences,sum(x>1e-6 for x in w));max_sum_error=max(max_sum_error,abs(sum(w)-1));valid=valid and all(0<=int(n)<len(base_joints['names']) for n,x in zip(j,w) if x>1e-6) and all(x>=0 for x in w)
 skin=joints(doc,binary);clip=clips(doc,binary);same_rig=skin==base_joints;same_clips=clip==base_clips
 check(f'LOD{level} actual skin weights and joints',maximum_influences<=4 and max_sum_error<1e-5 and valid,{'maximum_influences':maximum_influences,'maximum_weight_sum_error':max_sum_error,'joint_indices_valid':valid})
 if level:
  check(f'LOD{level} actual rig transforms and animation tracks match base',same_rig and same_clips,{'same_bind_names_rest_and_inverse_matrices':same_rig,'same_clip_times_values_and_channels':same_clips})
  check(f'LOD{level} uses one material slot without embedded images',len(doc.get('images',[]))==0 and len(doc['materials'])==1 and all(len(m['primitives'])==1 for m in doc['meshes']),{'images':len(doc.get('images',[])),'materials':len(doc['materials'])})
 lods.append({'level':level,'triangles':triangles,'vertices':sum(doc['accessors'][p['attributes']['POSITION']]['count'] for m in doc['meshes'] for p in m['primitives']),'byte_size':path.stat().st_size})
report={'resident':ident,'checks':checks,'all_pass':all(c['pass'] for c in checks),'lods':lods,'provenance_only':{'raw_source_sha256':s['raw_sha256'],'decoded_source_image_identity':{'source_image_count':len(source['images']),'delivery_image_count':len(base.get('images',[])),'images':image_rows},'note':'Input identity only, including decoded pixel comparisons. Not a quality check, count or acceptance gate.'}}
(ROOT/ident/'review/delivery-data-check.json').write_text(json.dumps(report,indent=2)+'\n');print(ident,'PASS' if report['all_pass'] else 'FAIL',[(c['name'],c['pass']) for c in checks]);raise SystemExit(0 if report['all_pass'] else 1)
