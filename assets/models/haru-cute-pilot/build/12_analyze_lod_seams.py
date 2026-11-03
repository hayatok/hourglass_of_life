"""Distinguish indexed UV seams from actual geometric boundary gaps."""
from pathlib import Path
import struct,json,math,collections
ROOT=Path(__file__).resolve().parents[1];REPO=ROOT.parents[2]
def read(path):
    raw=path.read_bytes();n,k=struct.unpack_from('<II',raw,12);doc=json.loads(raw[20:20+n]);offset=20+n;bn,bk=struct.unpack_from('<II',raw,offset);return doc,raw[offset+8:offset+8+bn]
def acc(doc,binary,index):
    a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']];start=v.get('byteOffset',0)+a.get('byteOffset',0);n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']];fmt='<'+{5121:'B',5123:'H',5125:'I',5126:'f'}[a['componentType']]*n;size=struct.calcsize(fmt);stride=v.get('byteStride',size);return [struct.unpack_from(fmt,binary,start+i*stride) for i in range(a['count'])]
def analyze(path):
    doc,raw=read(path);p=doc['meshes'][0]['primitives'][0];points=acc(doc,raw,p['attributes']['POSITION']);indices=[i[0] for i in acc(doc,raw,p['indices'])];joints=acc(doc,raw,p['attributes']['JOINTS_0']);weights=acc(doc,raw,p['attributes']['WEIGHTS_0']);groups=collections.defaultdict(list)
    for i,pos in enumerate(points):groups[tuple(round(v,6) for v in pos)].append(i)
    weight_differences=[]
    for group in groups.values():
        if len(group)<2:continue
        maps=[{j:w for j,w in zip(joints[i],weights[i]) if w>0} for i in group]
        for a in maps[1:]:weight_differences.append(sum(abs(maps[0].get(j,0)-a.get(j,0)) for j in set(a)|set(maps[0])))
    edges=collections.Counter();geometric_edges=collections.Counter();head_edges=collections.Counter()
    for face in zip(indices[0::3],indices[1::3],indices[2::3]):
        for a,b in zip(face,(face[1],face[2],face[0])):
            edges[tuple(sorted((a,b)))]+=1
            pa=tuple(round(v,6) for v in points[a]);pb=tuple(round(v,6) for v in points[b]);key=tuple(sorted((pa,pb)));geometric_edges[key]+=1
            if min(pa[1],pb[1])>1.30:head_edges[key]+=1
    def boundary_info(counter):
        selected=[edge for edge,n in counter.items() if n==1];return {'edges':len(selected),'total_length_m':sum(math.dist(*edge) for edge in selected)}
    return {'file':str(path.relative_to(REPO)),'vertices':len(points),'triangles':len(indices)//3,'indexed_boundary_edges':sum(n==1 for n in edges.values()),'geometric_boundary_rounded_1um':boundary_info(geometric_edges),'head_neck_geometric_boundary':boundary_info(head_edges),'coincident_vertex_groups':sum(len(v)>1 for v in groups.values()),'max_coincident_weight_l1_difference':max(weight_differences,default=0),'coincident_weight_discrepancies_over_1e_5':sum(v>1e-5 for v in weight_differences),'head_note':'Head/neck report filters edges above world-up glTF Y=1.30m; geometric boundaries merge equal-position UV/normal splits for analysis only.'}
if __name__=='__main__':
    result=[analyze(REPO/'game/assets/models/haru'/name) for name in ['CH_Haru.glb','CH_Haru_LOD1.glb','CH_Haru_LOD2.glb']]
    (ROOT/'review/lod-seams').mkdir(exist_ok=True);(ROOT/'review/lod-seams/r2-analysis.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
