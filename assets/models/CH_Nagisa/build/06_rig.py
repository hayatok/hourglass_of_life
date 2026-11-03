"""One stable humanoid skeleton, intentional regional weights, face morphs and skeletal LODs."""
import bpy,bmesh,math,sys,json
from pathlib import Path
from mathutils import Vector,Matrix
sys.path.insert(0,str(Path(__file__).parent))
import mesh_helpers as H
from dimensions import Dimensions
ROOT=Path(__file__).resolve().parents[1]
D=Dimensions(ROOT)
H.OWNER_TAG='phase:06_rig'

def smooth(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)
def combine(items):
    out={}
    for bone,weight in items:
        if weight>.01:out['DEF-'+bone]=out.get('DEF-'+bone,0)+weight
    total=sum(out.values());return {k:v/total for k,v in out.items()}
def weights(tag,co):
    z=co.z
    if tag=='chest_rigid':return {'DEF-chest':1}
    if tag=='long_skirt':
        # Preserve a hanging hem when seated: upper cloth follows thighs, lower cloth shins.
        waist=smooth(.88,1.02,z);knee=smooth(.43,.60,z);left=smooth(-.06,.06,co.x)
        return combine([('pelvis',waist),('thigh.L',(1-waist)*knee*left),
            ('thigh.R',(1-waist)*knee*(1-left)),('shin.L',(1-waist)*(1-knee)*left),
            ('shin.R',(1-waist)*(1-knee)*(1-left))])
    if tag=='hips':
        t=1-smooth(.64,1.0,z)
        left=smooth(-.035,.035,co.x)
        return combine([('pelvis',1-t),('thigh.L',t*left),('thigh.R',t*(1-left))])
    if tag=='chest':
        if z<1.12:
            t=smooth(1.06,1.12,z);return combine([('pelvis',1-t),('spine_01',t)])
        t=smooth(1.15,1.25,z);return combine([('spine_01',1-t),('chest',t)])
    if tag=='neck':
        t=smooth(1.33,1.405,z);return combine([('neck',1-t),('head',t)])
    if tag=='pelvis':
        t=1-smooth(.96,1.075,z)
        # Garment layers use the same angular weights: an offset pocket must not peel off the cloth.
        rx=.108+max(0,min(.55,1.07-z))*.165
        flank=min(1,abs(co.x)/rx)
        front=.5+(.5 if co.y<-.008 else -.5)*math.sqrt(max(0,1-flank*flank))
        return combine([('pelvis',1-t),('apron_front',t*front),('apron_back',t*(1-front))])
    if tag.startswith('leg.'):
        side=tag[-1];t=smooth(.43,.57,z)
        return combine([('thigh.'+side,t),('shin.'+side,1-t)])
    if tag.startswith(('arm.','arm_skin.')):
        side=tag[-1];elbow=1-smooth(1.025,1.13,z)
        hand=1-smooth(.895,.94,z);clavicle=smooth(1.25,1.33,z)*.35
        return combine([('upper_arm.'+side,(1-elbow)*(1-clavicle)),('clavicle.'+side,clavicle),
                        ('forearm.'+side,elbow*(1-hand)),('hand.'+side,elbow*hand)])
    if tag.startswith('foot.') and co.y<-.065:
        t=1-smooth(-.14,-.065,co.y)
        return combine([(tag,1-t),('toe.'+tag[-1],t)])
    return {'DEF-'+tag:1}

def morphs(ob):
    if ob.get('mesh_role')!='face':return
    groups={g.index:g.name for g in ob.vertex_groups}
    masks={v.index:{groups[w.group] for w in v.groups if w.weight>.2} for v in ob.data.vertices}
    ob.shape_key_add(name='Basis',from_mix=False).value=0
    for name in ['Blink','Smile','Sad','Tired','LookLeft','LookRight']:
        key=ob.shape_key_add(name=name,from_mix=False);key.value=0;key.slider_min=0;key.slider_max=1
        for v in ob.data.vertices:
            co=D.to_base(v.co);tags=masks[v.index];x=co.x
            eye=any(s.startswith('FACE_eye.') for s in tags)
            if name=='Blink' and eye:co.z=1.484+(co.z-1.484)*.018
            if name=='Tired' and eye:co.z=1.489+(co.z-1.489)*.72
            if name=='Smile':
                if 'FACE_mouth' in tags:co.z+=.004*(abs(x)/.022)**1.5
                if any(s.startswith('FACE_brow.') for s in tags):co.z+=.002
            if name=='Sad':
                if 'FACE_mouth' in tags:co.z-=.008*(abs(x)/.022)**1.4
                if any(s.startswith('FACE_brow.') for s in tags):co.z+=.005*(1-abs(x)/.065)
            if name in ['LookLeft','LookRight'] and 'GAZE' in tags:
                co.x+=.005*(1 if name=='LookLeft' else -1)
            key.data[v.index].co=D.to_model(co)

def build():
    H.open_master(str(ROOT/'CH_Nagisa_materials.blend'));H.clear_owned()
    armdata=bpy.data.armatures.new('CH_Nagisa_Skeleton')
    arm=bpy.data.objects.new('CH_Nagisa_Rig',armdata);H.col('RIG_DEF').objects.link(arm);H.own(arm)
    bpy.ops.object.select_all(action='DESELECT');arm.select_set(True);bpy.context.view_layer.objects.active=arm
    bpy.ops.object.mode_set(mode='EDIT')
    def bone(name,head,tail,parent=None):
        b=armdata.edit_bones.new('DEF-'+name);b.head=D.to_model(head);b.tail=D.to_model(tail)
        if parent:b.parent=armdata.edit_bones['DEF-'+parent]
        b.align_roll(Vector((0,-1,0)));return b
    bone('root',(0,0,0),(0,0,.15))
    bone('pelvis',(0,0,.94),(0,0,1.04),'root')
    bone('spine_01',(0,0,1.04),(0,0,1.16),'pelvis')
    bone('spine_02',(0,0,1.16),(0,0,1.24),'spine_01')
    bone('chest',(0,0,1.24),(0,0,1.32),'spine_02')
    bone('neck',(0,0,1.32),(0,0,1.40),'chest')
    bone('head',(0,0,1.40),(0,0,1.62),'neck')
    bone('apron_front',(0,-.10,1.07),(0,-.14,.56),'pelvis')
    bone('apron_back',(0,.075,1.07),(0,.115,.56),'pelvis')
    for side,s in [('L',1),('R',-1)]:
        bone('clavicle.'+side,(s*.033,0,1.30),(s*.123,0,1.30),'chest')
        bone('upper_arm.'+side,(s*.123,0,1.30),(s*.210,-.005,1.075),'clavicle.'+side)
        bone('forearm.'+side,(s*.210,-.005,1.075),(s*.312,-.012,.90),'upper_arm.'+side)
        bone('hand.'+side,(s*.312,-.012,.90),(s*.332,-.012,.842),'forearm.'+side)
        for f,(dx,length) in enumerate([(-.019,.045),(-.006,.068),(.007,.073),(.019,.064),(.029,.048)]):
            z=.87 if f==0 else .842;x=s*(.331+dx)
            bone('finger%d.%s'%(f,side),(x,-.012,z),(x+s*.001,-.018,z-length),'hand.'+side)
        bone('thigh.'+side,(s*.068,.005,.94),(s*.069,.022,.50),'pelvis')
        bone('shin.'+side,(s*.069,.022,.50),(s*.068,.025,.12),'thigh.'+side)
        bone('foot.'+side,(s*.068,.025,.12),(s*.077,-.10,.035),'shin.'+side)
        bone('toe.'+side,(s*.077,-.10,.035),(s*.077,-.16,.025),'foot.'+side)
    bpy.ops.object.mode_set(mode='OBJECT')
    arm.show_in_front=True;armdata.display_type='STICK'
    originals=[o for o in H.col('LOW').objects if o.type=='MESH']
    for ob in originals:
        tags={g.index:g.name[4:] for g in ob.vertex_groups if g.name.startswith('TAG_')}
        bone_groups={b.name:ob.vertex_groups.new(name=b.name) for b in armdata.bones}
        for v in ob.data.vertices:
            candidates=[(g.weight,tags[g.group]) for g in v.groups if g.group in tags]
            tag=max(candidates)[1] if candidates else 'head'
            for name,weight in weights(tag,D.to_base(v.co)).items():bone_groups[name].add([v.index],weight,'REPLACE')
        modifier=ob.modifiers.new('Humanoid skin','ARMATURE');modifier.object=arm
        ob.parent=arm
        # Distance copies preserve the regional tags so their face morphs can be rebuilt too.
        for lod,ratio in [(1,.42),(2,.12)]:
            copy=ob.copy();copy.data=ob.data.copy();copy.name=ob.name[:-1]+str(lod);copy.data.name=copy.name+'_Mesh'
            H.col('LOW').objects.link(copy);H.own(copy)
            bpy.context.view_layer.objects.active=copy
            modifier=copy.modifiers.new('LOD reduction','DECIMATE');modifier.ratio=ratio
            modifier.use_collapse_triangulate=True
            bpy.ops.object.modifier_move_up(modifier=modifier.name)
            bpy.ops.object.modifier_apply(modifier=modifier.name)
            bm=bmesh.new();bm.from_mesh(copy.data)
            bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.calc_area()<1e-10],context='FACES')
            bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
            bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
            bm.to_mesh(copy.data);bm.free()
            copy.data.validate(clean_customdata=True);copy.data.update()
            copy.hide_render=True;copy.hide_set(True)
    meshes=[o for o in H.col('LOW').objects if o.type=='MESH']
    for ob in meshes:
        morphs(ob)
        for g in list(ob.vertex_groups):
            if not g.name.startswith('DEF-'):ob.vertex_groups.remove(g)
        for v in ob.data.vertices:
            retained=sorted([(g.group,g.weight) for g in v.groups if g.weight>=.01],key=lambda item:-item[1])[:4]
            total=sum(w for _,w in retained)
            for index in [g.group for g in v.groups]:ob.vertex_groups[index].remove([v.index])
            for index,weight in retained:ob.vertex_groups[index].add([v.index],weight/total,'REPLACE')
    for role,parent,pos in [('hand.L','hand.L',(.333,-.018,.84)),('hand.R','hand.R',(-.333,-.018,.84)),
                            ('head','head',(0,-.075,1.49)),('chest','chest',(0,-.08,1.25)),
                            ('foot.L','foot.L',(.077,-.06,.015)),('foot.R','foot.R',(-.077,-.06,.015))]:
        empty=bpy.data.objects.new('SOCKET_'+role,None);H.col('SOCKETS').objects.link(empty);H.own(empty)
        empty.empty_display_type='ARROWS';empty.empty_display_size=.04
        empty.parent=arm;empty.parent_type='BONE';empty.parent_bone='DEF-'+parent
        bpy.context.view_layer.update()
        empty.matrix_world=Matrix.Translation(D.to_model(pos))@Matrix.Rotation(math.pi,4,'Z')
        empty['axes']='local +Y attachment forward; +Z up'
    # Optional physics proxy stays separate from the visible costume and animation deformation.
    import importlib
    B=importlib.import_module('02_blockout')
    collider=B.rings('Collision',[(.005,.04,.04,0,0),(.18,.23,.23,0,0),
        (1.43,.23,.23,0,0),(1.645,.025,.025,0,0)],bpy.data.materials['CH_Nagisa_Body'],n=12,collection='COLLISION')
    collider.name='COL_body';collider.parent=arm;collider['owner']=H.OWNER_TAG
    for vertex in collider.data.vertices:vertex.co=D.to_model(vertex.co)
    bm=bmesh.new();bm.from_mesh(collider.data);bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(collider.data);bm.free()
    collider.data.uv_layers.new(name='ProxyUV')
    collider.hide_render=True;collider.hide_set(True)
    bpy.context.scene.frame_set(1)
    H.save_master(str(ROOT/'CH_Nagisa_rig.blend'))
    print('RIG',len(armdata.bones),'bones; LODs',[(o.name,len(o.data.polygons)) for o in meshes])

if __name__=='__main__':build()
