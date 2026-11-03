"""Bind the derived Haru mesh to the existing 35-bone animation family.

Source animations are reused from Aoi. The target skeleton's joints are fitted
to Haru, and target-specific regional weights are authored without changing UVs.
"""
from pathlib import Path
import bpy, math, json
from mathutils import Vector, Matrix
ROOT=Path(__file__).resolve().parents[1];REPO=ROOT.parents[2]
BUILD=REPO/'builds/haru-cute-pilot'
bpy.ops.wm.open_mainfile(filepath=str(BUILD/'CH_Haru_JRPG_Pilot_Derived.blend'))
body=next(o for o in bpy.data.collections['LOW'].objects if o.type=='MESH')
world=body.matrix_world.copy(); ratio=1.71/1.77
for v in body.data.vertices:v.co=(world@v.co)*ratio
body.parent=None;body.matrix_world=Matrix.Identity(4);body.name='CH_Haru_Body_LOD0';body.data.name='CH_Haru_BodyMesh_LOD0'
for o in list(bpy.data.collections['LOW'].objects):
    if o!=body:bpy.data.objects.remove(o,do_unlink=True)
with bpy.data.libraries.load(str(REPO/'assets/models/CH_Aoi/CH_Aoi_animation_master.blend'),link=False) as (src,dst):
    dst.objects=['CH_Aoi_Rig'];dst.actions=list(src.actions)
arm=dst.objects[0];arm.name='CH_Haru_Rig';arm.data.name='CH_Haru_Skeleton'
bpy.data.collections['RIG_DEF'].objects.link(arm)
arm.animation_data_clear()
for pb in arm.pose.bones:pb.matrix_basis=Matrix.Identity(4)
bpy.context.view_layer.objects.active=arm;arm.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
eb=arm.data.edit_bones
def fit(name,head,tail):
    b=eb['DEF-'+name];b.head=head;b.tail=tail;b.align_roll(Vector((0,-1,0)))
fit('root',(0,0,0),(0,0,.15))
fit('pelvis',(0,0,.885),(0,0,1.005))
fit('spine_01',(0,0,1.005),(0,0,1.125))
fit('spine_02',(0,0,1.125),(0,0,1.235))
fit('chest',(0,0,1.235),(0,0,1.33))
fit('neck',(0,0,1.33),(0,0,1.405))
fit('head',(0,0,1.405),(0,0,1.63))
# Keep garment helper names for family compatibility; the short jacket is
# weighted to the torso/pelvis rather than the original long apron animation.
fit('apron_front',(0,-.09,.99),(0,-.1,.87))
fit('apron_back',(0,.08,.99),(0,.09,.87))
for side,s in [('L',1),('R',-1)]:
    fit('clavicle.'+side,(s*.04,0,1.31),(s*.168,0,1.31))
    fit('upper_arm.'+side,(s*.168,0,1.31),(s*.249,-.002,1.087))
    fit('forearm.'+side,(s*.249,-.002,1.087),(s*.342,-.012,.864))
    fit('hand.'+side,(s*.342,-.012,.864),(s*.375,-.012,.785))
    for i,(hx,hz,tx,tz) in enumerate([(.356,.817,.349,.764),(.369,.789,.383,.724),(.383,.783,.401,.712),(.397,.791,.420,.733),(.408,.805,.430,.757)]):
        fit(f'finger{i}.{side}',(s*hx,-.017,hz),(s*tx,-.022,tz))
    fit('thigh.'+side,(s*.083,.002,.885),(s*.112,.008,.485))
    fit('shin.'+side,(s*.112,.008,.485),(s*.132,.015,.112))
    fit('foot.'+side,(s*.132,.015,.112),(s*.145,-.095,.035))
    fit('toe.'+side,(s*.145,-.095,.035),(s*.155,-.160,.026))
bpy.ops.object.mode_set(mode='OBJECT')
def sm(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)
def merge(*terms):
    out={}
    for w,m in terms:
        for k,v in m.items():out[k]=out.get(k,0)+w*v
    out={k:v for k,v in sorted(out.items(),key=lambda kv:-kv[1])[:4] if v>=.01}
    total=sum(out.values());return {k:v/total for k,v in out.items()}
def blend(a,b,t):return merge((1-t,{a:1}),(t,{b:1}))
def segment_distance(p,a,b):
    direction=b-a;t=max(0,min(1,(p-a).dot(direction)/direction.length_squared));return (p-a-direction*t).length
groups={b.name:body.vertex_groups.new(name=b.name) for b in arm.data.bones}
for v in body.data.vertices:
    p=v.co;z=p.z;x=abs(p.x);side='L' if p.x>=0 else 'R'
    if z>1.345:
        w=blend('DEF-neck','DEF-head',sm(1.345,1.425,z))
    elif z<.90:
        thigh=sm(.43,.54,z);foot=1-sm(.115,.20,z)
        leg=merge((thigh,{'DEF-thigh.'+side:1}),((1-thigh)*(1-foot),{'DEF-shin.'+side:1}),((1-thigh)*foot,blend('DEF-foot.'+side,'DEF-toe.'+side,1-sm(-.145,-.085,p.y))))
        pelvis=sm(.81,.94,z)
        w=merge((1-pelvis,leg),(pelvis,{'DEF-pelvis':1}))
    else:w={'DEF-pelvis':1}
    if .90<=z<=1.345:
        if z<1.065:w=blend('DEF-pelvis','DEF-spine_01',sm(.96,1.065,z))
        elif z<1.205:w=blend('DEF-spine_01','DEF-chest',sm(1.105,1.205,z))
        else:w=blend('DEF-chest','DEF-neck',sm(1.28,1.375,z))
    # Arms are separated from the coat by a continuous shoulder/axilla mask.
    arm_threshold=.151+.045*(1-sm(1.06,1.29,z))
    arm_amount=sm(arm_threshold-.008,arm_threshold+.022,x)*(1-sm(1.335,1.40,z))*sm(.67,.73,z)
    if arm_amount:
        fore=1-sm(1.055,1.125,z);hand=1-sm(.855,.902,z)
        aw=merge((1-fore,{'DEF-upper_arm.'+side:1}),(fore*(1-hand),{'DEF-forearm.'+side:1}),(fore*hand,{'DEF-hand.'+side:1}))
        if z<.814:
            fingers=[arm.data.bones[f'DEF-finger{i}.{side}'] for i in range(5)]
            nearest=min(fingers,key=lambda b:segment_distance(p,b.head_local,b.tail_local))
            fw=1-sm(.778,.815,z)
            aw=merge((1-fw,aw),(fw,{nearest.name:1}))
        clav=sm(1.245,1.325,z)*.35
        aw=merge((1-clav,aw),(clav,{'DEF-clavicle.'+side:1}))
        w=merge((1-arm_amount,w),(arm_amount,aw))
    for name,value in w.items():groups[name].add([v.index],value,'REPLACE')
modifier=body.modifiers.new('Humanoid skin','ARMATURE');modifier.object=arm
modifier.use_deform_preserve_volume=False # glTF/Godot linear skinning contract.
body.parent=arm
# Retarget the existing local FK tracks; vertical translations are re-grounded
# below because source and target leg lengths differ.
arm.animation_data_create();bpy.context.scene.render.fps=30
grounding={}
for action in bpy.data.actions:
    if not action.slots:continue
    arm.animation_data.action=action;arm.animation_data.action_slot=action.slots[0]
    action.use_fake_user=True
    start,end=[int(v) for v in action.frame_range]
    # Ground each frame of the animation, keeping the feet on the delivery plane.
    corrections=[]
    if action.name not in ['sleep','_pose_sleep']:
        for frame in range(start,end+1):
            bpy.context.scene.frame_set(frame);bpy.context.view_layer.update()
            evaluated=body.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=evaluated.to_mesh()
            low=min(v.co.z for v in mesh.vertices);evaluated.to_mesh_clear()
            root=arm.pose.bones['DEF-root'];root.location.y+=.005-low
            root.keyframe_insert('location',frame=frame,group=root.name);corrections.append(.005-low)
    grounding[action.name]={'maximum_correction_m':max([abs(v) for v in corrections],default=0)}
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:key.interpolation='LINEAR'
arm.animation_data.action=None
for pb in arm.pose.bones:pb.matrix_basis=Matrix.Identity(4)
bpy.context.scene.frame_set(0);bpy.context.scene['target_height_m']=1.71
bpy.context.scene['authoring_forward']='-Y';bpy.context.scene['authoring_up']='Z'
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(BUILD/'CH_Haru_Rig.blend'))
report={'source_animation_master':'assets/models/CH_Aoi/CH_Aoi_animation_master.blend','bones':len(arm.data.bones),'target_height_m':1.71,'binding':'Target-specific regional linear weights, 4 maximum, normalized; UV and source material unchanged','influences_max':max(len(v.groups) for v in body.data.vertices),'unweighted':sum(not v.groups for v in body.data.vertices),'clips':[a.name for a in bpy.data.actions if not a.name.startswith('_')],'grounding':grounding,'facial_controls':{'supported':False,'names':[],'reason':'The generated face is one painted atlas, without separated eyelids/eyes/mouth.'},'joints':{b.name:{'head':list(b.head_local),'tail':list(b.tail_local)} for b in arm.data.bones}}
(ROOT/'review/bind-report.json').write_text(json.dumps(report,indent=2)+'\n')
print('BOUND',len(arm.data.bones),'bones',len(body.data.vertices),'vertices',report['influences_max'],'max influences')
