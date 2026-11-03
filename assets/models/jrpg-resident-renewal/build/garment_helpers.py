"""Keep a skirt coherent with a common middle and front/back lower bones.

Independent left/right shin rotations can fold a closed skirt into a fin. The
two helpers instead follow averaged lower-leg displacement. Walking keeps the
hem's pelvis orientation; seated poses use the averaged lower-leg orientation.
"""
from mathutils import Vector,Matrix

def update(arm, hem_height, pose_name):
    pelvis=arm.pose.bones['DEF-pelvis'];pelvis_def=pelvis.matrix@pelvis.bone.matrix_local.inverted()
    lower=[]
    for side in ['L','R']:
        pb=arm.pose.bones['DEF-shin.'+side];lower.append(pb.matrix@pb.bone.matrix_local.inverted())
    seated=pose_name in ['sit_talk','eat','rest','_pose_sit','deep_bend']
    rotation=lower[0].to_quaternion().slerp(lower[1].to_quaternion(),.5).to_matrix().to_4x4() if seated else pelvis_def.to_quaternion().to_matrix().to_4x4()
    if 'DEF-skirt_middle' in arm.pose.bones:
        pb=arm.pose.bones['DEF-skirt_middle'];rest=pb.bone.matrix_local
        upper=[]
        for side in ['L','R']:
            thigh=arm.pose.bones['DEF-thigh.'+side];upper.append(thigh.matrix@thigh.bone.matrix_local.inverted())
        middle_rotation=upper[0].to_quaternion().slerp(upper[1].to_quaternion(),.5).to_matrix().to_4x4() if seated else pelvis_def.to_quaternion().to_matrix().to_4x4()
        anchor=(pb.bone.head_local+pb.bone.tail_local)*.5
        desired=(upper[0]@anchor+upper[1]@anchor)*.5 if seated else pelvis_def@anchor
        matrix=middle_rotation@rest;matrix.translation+=desired-matrix@rest.inverted()@anchor;pb.matrix=matrix
    for name,y in [('apron_front',-.11),('apron_back',.11)]:
        pb=arm.pose.bones['DEF-'+name];rest=pb.bone.matrix_local
        anchor=Vector((0,y,hem_height))
        desired=(lower[0]@anchor+lower[1]@anchor)*.5 if seated else pelvis_def@anchor
        if pose_name=='walk':
            # A closed skirt cannot inherit independent rear-shin rotations.
            # Keep its lower ring level and open depth for the legs instead.
            inverse=pelvis_def.inverted();ys=[]
            for side in ['L','R']:
                a=inverse@arm.pose.bones['DEF-shin.'+side].matrix.translation
                b=inverse@arm.pose.bones['DEF-foot.'+side].matrix.translation
                if a.z>=hem_height:ys.append(a.y)
                if b.z>=hem_height:ys.append(b.y)
                if (a.z-hem_height)*(b.z-hem_height)<0:
                    t=(hem_height-a.z)/(b.z-a.z);ys.append(a.lerp(b,t).y)
            offset=min(0,min(ys,default=0)-.040-y) if y<0 else max(0,max(ys,default=0)+.040-y)
            offset=max(-.025,min(.025,offset))
            desired=pelvis_def@(anchor+Vector((0,offset,0)))
        matrix=rotation@rest
        current=matrix@rest.inverted()@anchor
        matrix.translation+=desired-current
        pb.matrix=matrix
