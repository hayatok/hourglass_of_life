"""Fit each resident's existing humanoid family to the accepted forms.

Clothing-specific weights are authored for skirts/camera; raw UVs and images are
unchanged. The original 35 named bones are retained; skirts add one common middle bone. Source FK clips are retargeted for scale
and arm-rest-angle differences, then grounded on the target mesh.
"""
from pathlib import Path
import bpy,math,json,struct,hashlib,sys,heapq
from mathutils import Vector,Matrix
from collections import defaultdict
from array import array
ROOT=Path(__file__).resolve().parents[1];REPO=ROOT.parents[2];SPECS=json.loads((ROOT/'build/specs.json').read_text())
ACTIVE=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else list(SPECS)
sys.path.insert(0,str(ROOT/'build'));import garment_helpers
LANDMARKS={
 'saki':{'pelvis':.875,'neck':1.295,'head':1.375,'shoulder':(.145,1.30),'elbow':(.254,1.065),'wrist':(.350,.855),'palm':(.380,.780),'arm_depth':(-.016,-.109,-.122),'knee':(.103,.455),'ankle':(.108,.095),'skirt_min':.335},
 'tomo':{'pelvis':.90,'neck':1.32,'head':1.400,'shoulder':(.175,1.31),'elbow':(.275,1.085),'wrist':(.387,.862),'palm':(.418,.785),'arm_depth':(.029,-.065,-.073),'knee':(.120,.48),'ankle':(.138,.115),'skirt_min':0},
 'yui':{'pelvis':.89,'neck':1.33,'head':1.410,'shoulder':(.145,1.32),'elbow':(.220,1.095),'wrist':(.292,.885),'palm':(.317,.813),'arm_depth':(-.014,-.070,-.072),'knee':(.098,.47),'ankle':(.110,.125),'skirt_min':.345}
}
def sm(a,b,x):
 t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)
def merge(*terms):
 out={}
 for factor,weights in terms:
  for bone,w in weights.items():out[bone]=out.get(bone,0)+factor*w
 out={k:v for k,v in sorted(out.items(),key=lambda kv:-kv[1])[:4] if v>=.01};total=sum(out.values());return {k:v/total for k,v in out.items()}
def blend(a,b,t):return merge((1-t,{a:1}),(t,{b:1}))
def segment_distance(p,a,b):
 d=b-a;t=max(0,min(1,(p-a).dot(d)/d.length_squared));return (p-a-t*d).length
def uvhash(ob):return hashlib.sha256(b''.join(struct.pack('<2f',*v.uv) for v in ob.data.uv_layers.active.data)).hexdigest()
for ident,s in SPECS.items():
 if ident not in ACTIVE:continue
 inputs=ROOT/ident/'production-inputs';inputs.mkdir(parents=True,exist_ok=True)
 build=REPO/f'builds/jrpg-resident-renewal/{ident}';bpy.ops.wm.open_mainfile(filepath=str(build/f'CH_{s["name"]}_Forms.blend'));body=next(o for o in bpy.data.collections['LOW'].objects if o.type=='MESH');world=body.matrix_world.copy();uv_before=uvhash(body);uv_before_values=[tuple(v.uv) for v in body.data.uv_layers.active.data]
 for v in body.data.vertices:v.co=world@v.co
 body.parent=None;body.matrix_world=Matrix.Identity(4);body.name=f'CH_{s["name"]}_Body_LOD0';body.data.name=body.name+'_Mesh'
 for o in list(bpy.data.collections['LOW'].objects):
  if o!=body:bpy.data.objects.remove(o,do_unlink=True)
 source=REPO/f'assets/models/CH_{s["rig_source"]}/CH_{s["rig_source"]}_animation_master.blend'
 source_profile=json.loads((source.parent/'profile.json').read_text())
 with bpy.data.libraries.load(str(source),link=False) as (src,dst):dst.objects=[f'CH_{s["rig_source"]}_Rig'];dst.actions=list(src.actions)
 arm=dst.objects[0];arm.name=f'CH_{s["name"]}_Rig';arm.data.name=f'CH_{s["name"]}_Skeleton';bpy.data.collections['RIG_DEF'].objects.link(arm);arm.animation_data_clear()
 old_arm_angles={side:math.atan2(abs(arm.data.bones['DEF-upper_arm.'+side].tail_local.x-arm.data.bones['DEF-upper_arm.'+side].head_local.x),arm.data.bones['DEF-upper_arm.'+side].head_local.z-arm.data.bones['DEF-upper_arm.'+side].tail_local.z) for side in ['L','R']}
 for pb in arm.pose.bones:pb.matrix_basis=Matrix.Identity(4)
 bpy.context.view_layer.objects.active=arm;arm.select_set(True);bpy.ops.object.mode_set(mode='EDIT');eb=arm.data.edit_bones;d=LANDMARKS[ident];h=s['height']
 def fit(name,head,tail):
  b=eb.get('DEF-'+name) or eb.new('DEF-'+name);b.head=head;b.tail=tail;b.align_roll(Vector((0,-1,0)))
 hip=d['pelvis'];neck=d['neck'];head=d['head']
 fit('root',(0,0,0),(0,0,.15));fit('pelvis',(0,0,hip),(0,0,hip+.115));fit('spine_01',(0,0,hip+.115),(0,0,1.12*h/1.7));fit('spine_02',(0,0,1.12*h/1.7),(0,0,1.225*h/1.7));fit('chest',(0,0,1.225*h/1.7),(0,0,neck));fit('neck',(0,0,neck),(0,0,head));fit('head',(0,0,head),(0,0,h-.08))
 fit('apron_front',(0,-.09,hip+.12),(0,-.12,d['skirt_min'] or .6));fit('apron_back',(0,.08,hip+.12),(0,.11,d['skirt_min'] or .6))
 if s['skirt']:
  fit('skirt_middle',(0,0,hip),(0,0,d['knee'][1]+.10));eb['DEF-skirt_middle'].parent=eb['DEF-pelvis']
 for side,sign in [('L',1),('R',-1)]:
  sh=Vector((sign*d['shoulder'][0],0,d['shoulder'][1]));el=Vector((sign*d['elbow'][0],d['arm_depth'][0],d['elbow'][1]));wr=Vector((sign*d['wrist'][0],d['arm_depth'][1],d['wrist'][1]));pa=Vector((sign*d['palm'][0],d['arm_depth'][2],d['palm'][1]));fit('clavicle.'+side,(sign*.035,0,sh.z),sh);fit('upper_arm.'+side,sh,el);fit('forearm.'+side,el,wr);fit('hand.'+side,wr,pa)
  down=(pa-wr).normalized();across=Vector((sign*.93,0,.36));width=.044*h/1.7
  for i,(offset,length) in enumerate([(-.60,.045),(-.33,.066),(0,.074),(.33,.065),(.58,.049)]):
   base=pa+across*(offset*width)
   if i==0:base=wr.lerp(pa,.50)+across*(-.55*width)
   tip=base+down*length+across*((i-2)*.003)
   fit(f'finger{i}.{side}',base,tip)
  knee=Vector((sign*d['knee'][0],.012,d['knee'][1]));ankle=Vector((sign*d['ankle'][0],.020,d['ankle'][1]));toe=Vector((sign*(d['ankle'][0]+.008),-.10,.035));fit('thigh.'+side,(sign*.079,.002,hip),knee);fit('shin.'+side,knee,ankle);fit('foot.'+side,ankle,toe);fit('toe.'+side,toe,(toe.x+sign*.006,-.16,.025))
 bpy.ops.object.mode_set(mode='OBJECT')
 if s['skirt']:arm.pose.bones['DEF-skirt_middle'].rotation_mode='XYZ'
 # Hair below the neck must still follow the head; Yui's low ponytail is
 # recognized only in the upper-body back region and its plum hue.
 image=next(node.image for node in body.data.materials[0].node_tree.nodes if node.type=='TEX_IMAGE' and node.image and 'basecolor' in node.image.name);pixels=array('f',[0.])*len(image.pixels);image.pixels.foreach_get(pixels);iw,ih=image.size;vertex_uv={}
 for loop in body.data.loops:vertex_uv.setdefault(loop.vertex_index,body.data.uv_layers.active.data[loop.index].uv.copy())
 hair=set();arm_skin=set();skirt_exclude=set()
 for v in body.data.vertices:
  uv=vertex_uv[v.index];x=max(0,min(iw-1,int(uv.x*iw)));y=max(0,min(ih-1,int(uv.y*ih)));r,g,b=pixels[(y*iw+x)*4:(y*iw+x)*4+3]
  if ident=='yui' and v.co.z>1.30 and v.co.y>0.015 and r>=b*1.005 and r-g>.015 and b-g>.015 and max(r,g,b)<.60:hair.add(v.index)
  if abs(v.co.x)>(.28 if ident=='tomo' else .17) and .65<v.co.z<1.20 and r>.25 and r>g*1.15 and r<g*2.35 and g>b*1.12:arm_skin.add(v.index)
  if ident=='saki' and v.co.z<.65 and abs(v.co.x)<.20 and r>.25 and r>g*1.05 and g>b*1.08:skirt_exclude.add(v.index)
  if ident=='yui' and v.co.z<.65 and abs(v.co.x)<.18 and max(r,g,b)<.48 and (max(r,g,b)-min(r,g,b))/max(.001,max(r,g,b))<.23:skirt_exclude.add(v.index)
  if s['skirt'] and v.co.z<.62:
   # Interior calf surfaces are separated from the flared cloth by depth, even
   # where atlas bleeding makes one skin/legging texel look like the skirt.
   leg_distance=min(segment_distance(v.co,arm.data.bones['DEF-'+part+'.'+side].head_local,arm.data.bones['DEF-'+part+'.'+side].tail_local) for part in ['shin','thigh'] for side in ['L','R'])
   if leg_distance<.105 or abs(v.co.x)<.21 and abs(v.co.y)<.105:skirt_exclude.add(v.index)
 groups_by_position=defaultdict(list)
 for v in body.data.vertices:groups_by_position[tuple(round(c,6) for c in v.co)].append(v.index)
 # Fill isolated classifier holes using mesh adjacency, bounded to the actual
 # hand/forearm or back-of-head region. This avoids one palm vertex retaining a
 # leg influence, and one ponytail vertex retaining an arm influence.
 adjacency=[set() for _ in body.data.vertices]
 for edge in body.data.edges:
  a,b=edge.vertices;adjacency[a].add(b);adjacency[b].add(a)
 # UV-split copies are one surface point for propagation, before filling holes.
 # A colour seed on either chart can therefore reach both chart neighborhoods.
 for ids in groups_by_position.values():
  for i in ids:adjacency[i].update(j for j in ids if j!=i)
  if any(i in hair for i in ids):hair.update(ids)
  if any(i in arm_skin for i in ids):arm_skin.update(ids)
  if any(i in skirt_exclude for i in ids):skirt_exclude.update(ids)
 for selection,region in [(arm_skin,lambda p:abs(p.x)>(.28 if ident=='tomo' else .17) and .65<p.z<1.20),(hair,lambda p:ident=='yui' and p.y>.07 and p.z>1.30),(skirt_exclude,lambda p:s['skirt'] and p.z<.65 and abs(p.x)<.20 and abs(p.y)<.10)]:
  for _ in range(3):
   additions=[i for i,neighbors in enumerate(adjacency) if i not in selection and region(body.data.vertices[i].co) and len(neighbors)>=2 and sum(j in selection for j in neighbors)/len(neighbors)>=.60]
   selection.update(additions)
 for ids in groups_by_position.values():
  if any(i in hair for i in ids):hair.update(ids)
  if any(i in arm_skin for i in ids):arm_skin.update(ids)
  if any(i in skirt_exclude for i in ids):skirt_exclude.update(ids)
 # Decide which connected surface belongs to a distal arm before blending
 # weights. A low hand must not inherit the thigh/pelvis base simply because
 # its absolute height overlaps the skirt. Distances travel along the surface,
 # rather than across a narrow air gap between a cuff and the dress.
 def surface_distance(seeds):
  distances=[math.inf]*len(body.data.vertices);queue=[]
  for i in seeds:distances[i]=0.;heapq.heappush(queue,(0.,i))
  while queue:
   distance,i=heapq.heappop(queue)
   if distance>distances[i]:continue
   for j in adjacency[i]:
    candidate=distance+(body.data.vertices[i].co-body.data.vertices[j].co).length
    if candidate<distances[j]:distances[j]=candidate;heapq.heappush(queue,(candidate,j))
  return distances
 arm_seeds=set(arm_skin)
 for v in body.data.vertices:
  p=v.co
  if abs(p.x)>d['wrist'][0]-.025 and .65<p.z<d['elbow'][1]+.04:arm_seeds.add(v.index)
 arm_distances=surface_distance(arm_seeds)
 torso_distances=surface_distance([v.index for v in body.data.vertices if v.co.z<.60 or abs(v.co.x)<.075 and hip<v.co.z<neck])
 arm_regions=[];arm_fixed={i:1. for i in arm_seeds}
 for v in body.data.vertices:
  p=v.co;amount=0.
  if .65<p.z<d['shoulder'][1]+.035 and abs(p.x)>.11:
   delta=torso_distances[v.index]-arm_distances[v.index]
   if math.isfinite(delta):amount=sm(-.080,.080,delta)
  else:arm_fixed[v.index]=0.
  if abs(p.x)<.075 and hip<p.z<neck:arm_fixed[v.index]=0.
  if v.index in arm_skin:amount=1.
  arm_regions.append(amount)
 # A hard nearest-seed cut can cross a sleeve that the generated mesh joins to
 # the torso. Smooth the field along actual edges, keeping hands and torso
 # centers fixed. This also avoids narrow strips jumping on wave/work poses.
 for _ in range(100):
  arm_regions=[arm_fixed.get(i,(arm_regions[i]+sum(arm_regions[j] for j in neighbors))/(1+len(neighbors))) for i,neighbors in enumerate(adjacency)]
 for i,value in enumerate(arm_regions):
  if value<.01:arm_regions[i]=0.
  elif value>.99:arm_regions[i]=1.
 cloth_regions=[0.]*len(body.data.vertices)
 if s['skirt']:
  low=d['skirt_min']-.025;top=hip+.12;cloth_seeds=set();leg_seeds=set();cloth_fixed={}
  for v in body.data.vertices:
   p=v.co;i=v.index
   if p.z<d['skirt_min']-.035:leg_seeds.add(i)
   if not low<p.z<top or arm_regions[i]>.05:
    cloth_fixed[i]=0.;continue
   outer=(p.x/.22)**2+(p.y/.125)**2
   if outer>1.25 or p.z>hip-.14:
    cloth_seeds.add(i);cloth_fixed[i]=1.
   if p.z<.62 and i in skirt_exclude:
    distance=min(segment_distance(p,arm.data.bones['DEF-'+part+'.'+side].head_local,arm.data.bones['DEF-'+part+'.'+side].tail_local) for part in ['shin','thigh'] for side in ['L','R'])
    if distance<.055:leg_seeds.add(i);cloth_fixed[i]=0.
  cloth_distances=surface_distance(cloth_seeds);leg_distances=surface_distance(leg_seeds)
  for v in body.data.vertices:
   delta=leg_distances[v.index]-cloth_distances[v.index]
   if math.isfinite(delta):cloth_regions[v.index]=sm(-.08,.08,delta)
  for _ in range(100):
   cloth_regions=[cloth_fixed.get(i,(cloth_regions[i]+sum(cloth_regions[j] for j in neighbors))/(1+len(neighbors))) for i,neighbors in enumerate(adjacency)]
  for i,value in enumerate(cloth_regions):
   if value<.01:cloth_regions[i]=0.
   elif value>.99:cloth_regions[i]=1.
 groups={b.name:body.vertex_groups.new(name=b.name) for b in arm.data.bones};weight_maps=[];camera_vertices=0;skirt_vertices=0
 for v in body.data.vertices:
  p=v.co;z=p.z;x=abs(p.x);side='L' if p.x>=0 else 'R'
  if z>neck+.015:w=blend('DEF-neck','DEF-head',sm(neck+.015,head+.025,z))
  elif z<hip+.025:
   knee_mix=sm(d['knee'][1]-.05,d['knee'][1]+.06,z);foot=1-sm(d['ankle'][1]+.005,d['ankle'][1]+.10,z)
   legs={}
   for leg_side in ['L','R']:legs[leg_side]=merge((knee_mix,{'DEF-thigh.'+leg_side:1}),((1-knee_mix)*(1-foot),{'DEF-shin.'+leg_side:1}),((1-knee_mix)*foot,blend('DEF-foot.'+leg_side,'DEF-toe.'+leg_side,1-sm(-.145,-.085,p.y))))
   width=.075 if s['skirt'] and z>d['skirt_min']-.025 else (.055 if z>d['knee'][1]+.13 else 0.)
   left=sm(-width,width,p.x) if width else (1. if side=='L' else 0.)
   leg=merge((left,legs['L']),(1-left,legs['R']));pelvis=sm(hip-.18,hip+.05,z);w=merge((1-pelvis,leg),(pelvis,{'DEF-pelvis':1}))
  else:
   if z<hip+.18:w=blend('DEF-pelvis','DEF-spine_01',sm(hip+.07,hip+.18,z))
   elif z<1.23*h/1.7:w=blend('DEF-spine_01','DEF-chest',sm(1.10*h/1.7,1.23*h/1.7,z))
   else:w=blend('DEF-chest','DEF-neck',sm(neck-.04,head,z))
  limb_bones=[arm.data.bones['DEF-'+name+'.'+side] for name in ['upper_arm','forearm','hand','finger0','finger1','finger2','finger3','finger4']]
  arm_distance=min(segment_distance(p,b.head_local,b.tail_local) for b in limb_bones)
  arm_amount=arm_regions[v.index]
  cloth_amount=cloth_regions[v.index]
  if v.index in arm_skin:arm_amount=1
  if cloth_amount:
   waist=sm(hip-.20,hip-.02,z);middle=sm(d['knee'][1]+.02,hip-.18,z);front=1-sm(-.025,.025,p.y);cw=merge((waist,{'DEF-pelvis':1}),((1-waist)*middle,{'DEF-skirt_middle':1}),((1-waist)*(1-middle)*front,{'DEF-apron_front':1}),((1-waist)*(1-middle)*(1-front),{'DEF-apron_back':1}));w=merge((1-cloth_amount,w),(cloth_amount,cw));skirt_vertices+=cloth_amount>.5
  if arm_amount:
   if z<hip+.025:
    # Ambiguous generated joins blend into the torso, never into leg bones.
    # Distal hands are fixed at arm_amount=1 by the surface seeds above.
    w=blend('DEF-pelvis','DEF-spine_01',sm(hip-.03,hip+.16,z))
   fore=1-sm(d['elbow'][1]-.035,d['elbow'][1]+.04,z);hand=1-sm(d['wrist'][1]-.015,d['wrist'][1]+.045,z);aw=merge((1-fore,{'DEF-upper_arm.'+side:1}),(fore*(1-hand),{'DEF-forearm.'+side:1}),(fore*hand,{'DEF-hand.'+side:1}))
   if z<d['palm'][1]+.025:
    nearest=min([arm.data.bones[f'DEF-finger{i}.{side}'] for i in range(5)],key=lambda b:segment_distance(p,b.head_local,b.tail_local));finger=1-sm(d['palm'][1]-.008,d['palm'][1]+.025,z);aw=merge((1-finger,aw),(finger,{nearest.name:1}))
   clav=sm(d['shoulder'][1]-.07,d['shoulder'][1]+.02,z)*.3;aw=merge((1-clav,aw),(clav,{'DEF-clavicle.'+side:1}));w=merge((1-arm_amount,w),(arm_amount,aw))
  if s['camera']:
   camera_amount=(1-sm(-.125,-.085,p.y))*(1-sm(.115,.155,x))*sm(.86,.90,z)*(1-sm(1.12,1.17,z))
   if camera_amount:w=merge((1-camera_amount,w),(camera_amount,{'DEF-chest':1}))
   camera_vertices+=camera_amount==1.
  if v.index in hair:w={'DEF-head':1}
  weight_maps.append(w)
 # Every UV/normal split at the same rest point gets exactly the same weights.
 for ids in groups_by_position.values():
  average=merge(*[(1/len(ids),weight_maps[i]) for i in ids])
  for i in ids:weight_maps[i]=average
 for i,w in enumerate(weight_maps):
  for name,value in w.items():groups[name].add([i],value,'REPLACE')
 modifier=body.modifiers.new('Humanoid skin','ARMATURE');modifier.object=arm;modifier.use_deform_preserve_volume=False;body.parent=arm
 scale=h/source_profile['height'];bias={side:-(1 if side=='L' else -1)*(math.atan2(abs(arm.data.bones['DEF-upper_arm.'+side].tail_local.x-arm.data.bones['DEF-upper_arm.'+side].head_local.x),arm.data.bones['DEF-upper_arm.'+side].head_local.z-arm.data.bones['DEF-upper_arm.'+side].tail_local.z)-old_arm_angles[side]) for side in ['L','R']}
 arm.animation_data_create();bpy.context.scene.render.fps=30;grounding={}
 for action in bpy.data.actions:
  if not action.slots:continue
  for layer in action.layers:
   for strip in layer.strips:
    for bag in strip.channelbags:
     for curve in bag.fcurves:
      offset=next((value for side,value in bias.items() if curve.data_path=='pose.bones["DEF-upper_arm.'+side+'"].rotation_euler' and curve.array_index==2),0.)
      for key in curve.keyframe_points:
       if curve.data_path.endswith('.location'):key.co.y*=scale
       if s['skirt'] and action.name=='walk' and curve.array_index==0 and any('DEF-'+part+'.' in curve.data_path for part in ['thigh','shin']):key.co.y*={'saki':.45,'yui':.40}[ident]
       key.co.y+=offset;key.interpolation='LINEAR'
  arm.animation_data.action=action;arm.animation_data.action_slot=action.slots[0];action.use_fake_user=True;corrections=[]
  if action.name not in ['sleep','_pose_sleep']:
   for frame in range(int(action.frame_range[0]),int(action.frame_range[1])+1):
    bpy.context.scene.frame_set(frame);bpy.context.view_layer.update()
    if s['skirt']:
     garment_helpers.update(arm,d['skirt_min']+.015,action.name);bpy.context.view_layer.update()
     for bone_name in ['DEF-apron_front','DEF-apron_back','DEF-skirt_middle']:
      pb=arm.pose.bones[bone_name];pb.keyframe_insert('location',frame=frame,group=bone_name);pb.keyframe_insert('rotation_euler',frame=frame,group=bone_name)
    ev=body.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=ev.to_mesh();low=min(v.co.z for v in mesh.vertices);ev.to_mesh_clear();delta=.005-low;arm.pose.bones['DEF-root'].location.y+=delta;arm.pose.bones['DEF-root'].keyframe_insert('location',frame=frame,group='DEF-root');corrections.append(delta)
  elif s['skirt']:
   for frame in range(int(action.frame_range[0]),int(action.frame_range[1])+1):
    bpy.context.scene.frame_set(frame);bpy.context.view_layer.update();garment_helpers.update(arm,d['skirt_min']+.015,action.name);bpy.context.view_layer.update()
    for bone_name in ['DEF-apron_front','DEF-apron_back','DEF-skirt_middle']:
     pb=arm.pose.bones[bone_name];pb.keyframe_insert('location',frame=frame,group=bone_name);pb.keyframe_insert('rotation_euler',frame=frame,group=bone_name)
  grounding[action.name]=max([abs(c) for c in corrections],default=0)
  for layer in action.layers:
   for strip in layer.strips:
    for bag in strip.channelbags:
     for curve in bag.fcurves:
      for key in curve.keyframe_points:key.interpolation='LINEAR'
 arm.animation_data.action=None
 for pb in arm.pose.bones:pb.matrix_basis=Matrix.Identity(4)
 bpy.context.scene.frame_set(0);bpy.context.scene['target_height_m']=h;uv_difference=max([abs(a-b) for old,new in zip(uv_before_values,body.data.uv_layers.active.data) for a,b in zip(old,new.uv)],default=0.);assert uv_difference==0.;bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(build/f'CH_{s["name"]}_Rig.blend'))
 report={'source_animation_master':str(source.relative_to(REPO)),'source_height_m':source_profile['height'],'target_height_m':h,'bones':len(arm.data.bones),'clips':[a.name for a in bpy.data.actions if not a.name.startswith('_')],'source_motion_profile':source_profile['motion'],'retarget_translation_scale':scale,'upper_arm_local_z_bias_radians':bias,'landmarks_inferred_from_forms':d,'maximum_influences':max(len(v.groups) for v in body.data.vertices),'unweighted':sum(not v.groups for v in body.data.vertices),'uv_coordinate_max_abs_difference':uv_difference,'uv_loop_count':len(uv_before_values),'uv_sha256_before':uv_before,'uv_sha256_after':uvhash(body),'camera_rigid_chest_vertices':camera_vertices,'skirt_weighted_vertices':skirt_vertices,'yui_low_ponytail_head_vertices':len(hair),'coincident_seam_weights_synchronized':True,'grounding_max_corrections_m':grounding,'arm_partition':'Surface-distance seeds with 100-step adjacency smoothing; hands fixed to arm family, torso centers fixed, UV seam copies share adjacency.','skirt_middle_bone':s['skirt'],'camera_rigid_region_m':{'max_y':-.125,'max_abs_x':.115,'z':[.90,1.12],'transition_m':.04} if s['camera'] else None,'acceptance':'Body candidate. Extreme poses/camera/skirt contact review pending.'};(ROOT/ident/'production-inputs/bind-report.json').write_text(json.dumps(report,indent=2)+'\n');print('BOUND',ident,len(arm.data.bones),report['maximum_influences'],camera_vertices,skirt_vertices,len(hair))
