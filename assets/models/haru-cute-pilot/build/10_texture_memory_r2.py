"""Stage geometry-only distance LODs without mutating the frozen r1 assets.

All non-image buffers, mesh attributes, skins, nodes and animation data remain
byte-identical. LOD0 stays byte-identical, retaining source-PBR inspection.
"""
from pathlib import Path
import json,struct,copy,hashlib,shutil
ROOT=Path(__file__).resolve().parents[1];REPO=ROOT.parents[2]
SOURCE=REPO/'game/assets/models/haru';OUT=REPO/'builds/haru-cute-pilot/r2'
OUT.mkdir(parents=True,exist_ok=True)
def read(path):
    data=path.read_bytes();n,k=struct.unpack_from('<II',data,12);doc=json.loads(data[20:20+n]);offset=20+n;bn,bk=struct.unpack_from('<II',data,offset);return doc,data[offset+8:offset+8+bn]
def write(path,doc,binary):
    js=json.dumps(doc,separators=(',',':')).encode();js+=b' '*((-len(js))%4);binary+=b'\0'*((-len(binary))%4)
    path.write_bytes(struct.pack('<III',0x46546c67,2,12+8+len(js)+8+len(binary))+struct.pack('<II',len(js),0x4e4f534a)+js+struct.pack('<II',len(binary),0x004e4942)+binary)
def digest(data):return hashlib.sha256(data).hexdigest()
def view_bytes(doc,binary,index):
    view=doc['bufferViews'][index];start=view.get('byteOffset',0);return binary[start:start+view['byteLength']]
def accessor_bytes(doc,binary,index):
    a=doc['accessors'][index];return view_bytes(doc,binary,a['bufferView'])
records=[]
for level in range(3):
    name='CH_Haru.glb' if level==0 else f'CH_Haru_LOD{level}.glb';src=SOURCE/name;dst=OUT/name;before,binary=read(src);doc=copy.deepcopy(before)
    if level==0:shutil.copyfile(src,dst)
    else:
        for field in ['images','textures','samplers']:doc.pop(field,None)
        doc['materials']=[{'name':'CH_Haru_GeometryOnly_RuntimeOverride','pbrMetallicRoughness':{'baseColorFactor':[1,1,1,1],'metallicFactor':0,'roughnessFactor':1},'extras':{'policy':'Geometry-only LOD. Runtime actor retains LOD0 material override. Standalone PBR inspection must use LOD0.'}}]
        used=set()
        for a in doc['accessors']:
            if 'bufferView' in a:used.add(a['bufferView'])
            for v in a.get('sparse',{}).values():
                if isinstance(v,dict) and 'bufferView' in v:used.add(v['bufferView'])
        remap={old:new for new,old in enumerate(sorted(used))};compact=bytearray();views=[]
        for old in sorted(used):
            view=copy.deepcopy(doc['bufferViews'][old]);data=view_bytes(doc,binary,old);compact.extend(b'\0'*((-len(compact))%4));view['byteOffset']=len(compact);view['buffer']=0;compact.extend(data);views.append(view)
        for a in doc['accessors']:
            if 'bufferView' in a:a['bufferView']=remap[a['bufferView']]
            for v in a.get('sparse',{}).values():
                if isinstance(v,dict) and 'bufferView' in v:v['bufferView']=remap[v['bufferView']]
        doc['bufferViews']=views;doc['buffers']=[{'byteLength':len(compact)}];write(dst,doc,bytes(compact))
    after,abinary=read(dst)
    # Every accessor includes the same underlying bytes; all references remain valid.
    assert len(before['accessors'])==len(after['accessors'])
    assert all(accessor_bytes(before,binary,i)==accessor_bytes(after,abinary,i) for i in range(len(before['accessors'])))
    for key in ['meshes','nodes','skins','animations','scenes','scene']:assert before[key]==after[key],key
    records.append({'level':level,'file':name,'r1_sha256':digest(src.read_bytes()),'r2_sha256':digest(dst.read_bytes()),'r1_bytes':src.stat().st_size,'r2_bytes':dst.stat().st_size,'images_before':len(before.get('images',[])),'images_after':len(after.get('images',[])),'all_accessor_bytes_identical':True,'mesh_nodes_skins_animation_metadata_identical':True})
manifest=json.loads((SOURCE/'asset-manifest.json').read_text());manifest['candidate_revision']='r2-staging-geometry-only-lods';manifest['candidate_status']='Not installed in game; GPU material retention and texture-memory comparison required.';manifest['r1_source_files']={r['file']:r['r1_sha256'] for r in records};manifest['lod_sha256']={r['file']:r['r2_sha256'] for r in records};manifest['distance_lod_texture_policy']='LOD0 retains exact r1 GLB and all three source PBR images. LOD1/2 have one untextured material slot and no images; actor retains LOD0 override while swapping mesh/skin. Standalone LOD1/2 import is intentionally untextured.';manifest['generation_change']='No generation, rigging, stride, weights, bones, UVs or clip changes.'
(OUT/'asset-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');shutil.copyfile(SOURCE/'animation-contract.json',OUT/'animation-contract.json')
report={'revision':'r2-staging','installed':False,'source_raw_sha256':manifest['raw_source_sha256'],'source_lod0_unchanged':records[0]['r1_sha256']==records[0]['r2_sha256'],'files':records,'total_r1_bytes':sum(r['r1_bytes'] for r in records),'total_r2_bytes':sum(r['r2_bytes'] for r in records)}
(ROOT/'review/r2').mkdir(exist_ok=True);(ROOT/'review/r2/staging-check.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
