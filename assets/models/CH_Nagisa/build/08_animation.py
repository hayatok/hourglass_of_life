"""FK clips and an explicit motion/event contract. All locomotion is in-place.
The animation master retains review poses; only named game clips ship in delivery.
"""
import bpy,math,sys,json
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).parent))
import mesh_helpers as H
from dimensions import Dimensions
ROOT=Path(__file__).resolve().parents[1]
D=Dimensions(ROOT)
CLIPS={'idle':(72,True),'walk':(24,True),'talk':(72,True),'work':(60,True),
       'sit_talk':(72,True),'sleep':(90,True),'wave':(60,False),'eat':(72,True),'rest':(90,True)}
CLIPS['walk']=(int(D.motion.get('walk_frames',24)),True)

def pose(arm,name,t):
    p={b.name.removeprefix('DEF-'):b for b in arm.pose.bones}
    for b in p.values():b.rotation_mode='XYZ';b.rotation_euler=(0,0,0);b.location=(0,0,0);b.scale=(1,1,1)
    phase=math.tau*t
    for side,s in [('L',1),('R',-1)]:
        p['upper_arm.'+side].rotation_euler.z=-s*.32
        p['forearm.'+side].rotation_euler.x=.10
        for i in range(5):p['finger%d.%s'%(i,side)].rotation_euler.x=.05
    p['chest'].rotation_euler.x=.016*math.sin(phase)
    p['head'].rotation_euler.x=.018
    p['head'].rotation_euler.z=.014*math.sin(phase)
    if name=='walk':
        for side,s in [('L',1),('R',-1)]:
            swing=math.sin(phase)*s
            p['thigh.'+side].rotation_euler.x=.49*swing*D.motion.get('stride',1)
            p['shin.'+side].rotation_euler.x=-.72*max(0,-swing)*D.motion.get('stride',1)
            p['upper_arm.'+side].rotation_euler.x=-.28*swing
            p['forearm.'+side].rotation_euler.x=.15+.16*max(0,swing)
            p['foot.'+side].rotation_euler.x=-.10*swing
        p['pelvis'].location.y=.012*D.body_scale*(1-math.cos(phase*2))
        p['pelvis'].rotation_euler.z=.035*math.sin(phase)
        p['apron_front'].rotation_euler.x=.46*abs(math.sin(phase))
        p['apron_back'].rotation_euler.x=-.36*abs(math.sin(phase))
    if name in ['talk','sit_talk']:
        p['upper_arm.L'].rotation_euler.x=.25+.12*math.sin(phase)
        p['forearm.L'].rotation_euler.x=.55+.18*math.sin(phase)
        p['hand.L'].rotation_euler.y=.14*math.sin(phase)
        p['head'].rotation_euler.x=.06+.045*math.sin(phase*2)
        p['chest'].rotation_euler.z=.025*math.sin(phase)
    if name in ['work','_pose_reach']:
        for side,s in [('L',1),('R',-1)]:
            p['upper_arm.'+side].rotation_euler.x=.68+.08*math.sin(phase+s)
            p['upper_arm.'+side].rotation_euler.z=-s*.38
            p['forearm.'+side].rotation_euler.x=.61+.16*math.sin(phase*2+s)
            p['hand.'+side].rotation_euler.x=.12*math.sin(phase*2+s)
            for i in range(5):p['finger%d.%s'%(i,side)].rotation_euler.x=.38
        p['chest'].rotation_euler.x=.12;p['head'].rotation_euler.x=.18
    if name in ['sit_talk','eat','rest','_pose_sit']:
        p['pelvis'].location.y=-.50*D.body_scale
        for side,s in [('L',1),('R',-1)]:
            p['thigh.'+side].rotation_euler.x=1.42
            p['shin.'+side].rotation_euler.x=-1.50
            p['foot.'+side].rotation_euler.x=.08
            p['upper_arm.'+side].rotation_euler.x=.82
            p['upper_arm.'+side].rotation_euler.z=-s*.45
            p['forearm.'+side].rotation_euler.x=.72
        p['apron_front'].rotation_euler.x=1.48
        p['apron_back'].rotation_euler.x=.25
        p['chest'].rotation_euler.x=.04
        if name=='rest':p['head'].rotation_euler.x=.12;p['head'].rotation_euler.z=.05
        if name=='eat':
            p['upper_arm.R'].rotation_euler.x=.80+.1*math.sin(phase)
            p['forearm.R'].rotation_euler.x=1.1+.25*math.sin(phase)
    if name in ['sleep','_pose_sleep']:
        # Face up on a mattress; the town aligns the head to its pillow contact.
        p['root'].rotation_euler.x=-math.pi/2;p['root'].location.y=.48
        for side,s in [('L',1),('R',-1)]:
            p['upper_arm.'+side].rotation_euler.z=-s*.36
            p['forearm.'+side].rotation_euler.x=.2
        p['head'].rotation_euler.z=.08
    if name in ['wave','_pose_overhead']:
        ramp=min(1,t*5,(1-t)*5) if name=='wave' else 1
        p['upper_arm.L'].rotation_euler.z=-.32+2.05*ramp
        p['forearm.L'].rotation_euler.x=.1+.55*ramp
        p['hand.L'].rotation_euler.z=.25*math.sin(phase*3)*ramp
        p['head'].rotation_euler.z=-.04*ramp
    if name=='_pose_stride':
        pose(arm,'walk',.25)
    if name=='_pose_twist':
        p['spine_01'].rotation_euler.y=.35;p['chest'].rotation_euler.y=.30;p['head'].rotation_euler.y=.25
    return p

def ground(arm,body):
    bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get()
    evaluated=body.evaluated_get(dg);mesh=evaluated.to_mesh()
    low=min(v.co.z for v in mesh.vertices);evaluated.to_mesh_clear()
    arm.pose.bones['DEF-root'].location.y+=.005-low

def build():
    H.open_master(str(ROOT/'CH_Nagisa_rig.blend'))
    arm=bpy.data.objects['CH_Nagisa_Rig'];body=bpy.data.objects['CH_Nagisa_Body_LOD0']
    arm.animation_data_create();bpy.context.scene.render.fps=30
    for action in list(bpy.data.actions):bpy.data.actions.remove(action)
    for name,(frames,loop) in {**CLIPS,**{n:(1,False) for n in ['_pose_reach','_pose_sit','_pose_stride','_pose_twist','_pose_sleep','_pose_overhead']}}.items():
        action=bpy.data.actions.new(name);action.use_fake_user=True
        action['loop']=loop;action['root_motion']=False;action['interruptible']=True;action['locomotion_allowed']=name=='walk'
        if name=='walk':
            action['speed_mps']=1.6*D.body_scale*D.motion.get('stride',1)*24/frames
            action['blend_direction']='forward'
        arm.animation_data.action=action
        arm.animation_data.action_slot=action.slots.new(id_type='OBJECT',name=arm.name)
        step=1 if name=='walk' else 3
        for frame in sorted(set([0,frames]+list(range(0,frames+1,step)))):
            bpy.context.scene.frame_set(frame);p=pose(arm,name,frame/frames)
            if name not in ['sleep','_pose_sleep']:ground(arm,body)
            for bone in p.values():
                bone.keyframe_insert('rotation_euler',frame=frame,group=bone.name)
                bone.keyframe_insert('location',frame=frame,group=bone.name)
        events={'walk':{'footstep.L':0,'footstep.R':frames//2},'work':{'contact.L':15,'contact.R':45},
                'wave':{'greeting':15},'eat':{'sip':36}}.get(name,{})
        for event,frame in events.items():marker=action.pose_markers.new(event);marker.frame=frame
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    for curve in bag.fcurves:
                        for key in curve.keyframe_points:key.interpolation='LINEAR'
        print('CLIP',name,'seconds',frames/30)
    idle=bpy.data.actions['idle'];arm.animation_data.action=idle;arm.animation_data.action_slot=idle.slots[0]
    bpy.context.scene.frame_set(0)
    H.save_master(str(ROOT/'CH_Nagisa_animation_master.blend'))
    for action in list(bpy.data.actions):
        if action.name.startswith('_pose_'):bpy.data.actions.remove(action)
    H.save_master(str(ROOT/'CH_Nagisa_delivery.blend'))

if __name__=='__main__':build()
