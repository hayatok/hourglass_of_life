"""Original metre-scale architecture. Dimensions are inferred in asset-brief.md.
Blender Z up / -Y front, with the same 5.6m clear room used by the simulation.
"""
from pathlib import Path
import sys, math, json, os, importlib.util, struct
import bpy, bmesh, numpy as np
from mathutils import Vector, Matrix
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT.parent/'CH_Nagisa/build'))
import mesh_helpers as H
SKILL=Path(os.environ.get('BLENDER_ASSET_SKILL',str(Path.home()/'.codex/skills/blender-image-to-3d')))
CURRENT=None
DETAIL=False
M={}
ASSETS=['Home','Cafe','Workshop']

def mat(name,color,rough=.8,metal=0):
    m=bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.diffuse_color=(*color,1)
    sh=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    sh.inputs['Base Color'].default_value=(*color,1);sh.inputs['Roughness'].default_value=rough;sh.inputs['Metallic'].default_value=metal
    M[name]=m;return m

def group(name,parent,at=(0,0,0),rotation=(0,0,0)):
    ob=bpy.data.objects.new(name,None);H.col('LOW').objects.link(ob);ob.parent=parent;ob.location=at;ob.rotation_euler=rotation;H.own(ob)
    return ob

def finish(ob,material):
    ob.parent=CURRENT;ob.data.materials.append(material);H.own(ob);return ob

def box(name,size,at,material,bevel=.008,rotation=(0,0,0)):
    ob=H.box(CURRENT.name+'_'+name,size,location=at,rotation=rotation)
    if DETAIL and bevel: H.bevel(ob,bevel,1)
    return finish(ob,material)

def rod(name,r,h,at,material,axis='Z',segments=12):
    return finish(H.cylinder(CURRENT.name+'_'+name,r,h,axis=axis,location=at,segments=segments),material)

def extrude_y(name,profile,y0,y1,material):
    n=len(profile);verts=[(x,y,z) for y in [y0,y1] for x,z in profile]
    faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces)
    ob=bpy.data.objects.new(name,me);H.col('LOW').objects.link(ob);return finish(ob,material)

def window(x,width=1.2):
    # Coordinates in the wall's local frame: facade points -Y, height in Z.
    z=1.45;h=1.1
    box('Glass',(width-.10,.045,h-.10),(x,0,z),M['Glass'],0)
    for px in [x-width/2,x+width/2,x]:box('WindowMullion',(.045,.12,h+.08),(px,-.035,z),M['Timber'])
    for pz in [z-h/2,z,z+h/2]:box('WindowRail',(width+.10,.12,.045),(x,-.035,pz),M['Timber'])
    box('Sill',(width+.20,.24,.065),(x,-.04,z-h/2),M['Wood'])
    if DETAIL:
        for side in [-1,1]:
            for i in range(5):box('ShutterSlat',(.19,.05,.15),(x+side*(width/2+.14),.015,z-.37+i*.185),M['Wood'])
        box('WindowHood',(width+.26,.40,.055),(x,-.06,2.08),M['Roof'],rotation=(.12,0,0))

def wall(name,parent,at,yaw,style,front=False):
    global CURRENT
    CURRENT=group(name,parent,at,rotation=(0,0,yaw))
    finish_wall=M['Teal'] if style=='Workshop' else M['Plaster']
    if front:
        gap=3.8 if style=='Workshop' else 1.4
        # The central passage is truly open. No decorative panel crosses its route.
        for side in [-1,1]:
            if style=='Workshop':
                width=2.9-gap/2
                box('FrontPier',(width,.16,2.7),(side*(gap/2+width/2),0,1.35),finish_wall)
            else:
                for lo,hi in [(gap/2,1.35),(2.25,2.9)]:box('FrontPier',(hi-lo,.16,2.7),(side*(lo+hi)/2,0,1.35),finish_wall)
                for z,h in [(.45,.9),(2.35,.7)]:box('WindowSpandrel',(.9,.16,h),(side*1.8,0,z),finish_wall)
            box('DoorPost',(.12,.22,2.35),(side*gap/2,-.035,1.175),M['Timber'])
        box('FrontHeader',(gap,.16,.45),(0,0,2.475),finish_wall)
        if style!='Workshop':
            # Deliberately open leaves, with their source pivot at the hinge line.
            for side in [-1,1]:
                hinge=group('OpenDoor'+('L' if side<0 else 'R'),CURRENT,(side*.7,-.12,0),(0,0,side*math.pi/2))
                saved=CURRENT;CURRENT=hinge
                box('Door',(.67,.065,2.20),(-side*.335,0,1.1),M['Wood'])
                for z in [.5,1.5]:box('DoorPanel',(.49,.025,.7),(-side*.335,-.045,z),M['Timber'])
                CURRENT=saved
            for x in [-1.8,1.8]:window(x,.9)
        if style=='Cafe':
            # Sloping canvas and repeated scallops; underside clears all residents.
            box('Awning',(4.8,1.0,.065),(0,-.50,2.64),M['Canvas'],rotation=(.16,0,0))
            for i in range(16):
                rod('Scallop',.15,.045,(-2.25+i*.3,-1.0,2.44),M['Canvas'],axis='Y',segments=12)
            for x in [-2.4,2.4]:box('AwningBracket',(.05,.8,.05),(x,-.4,2.48),M['Metal'])
    else:
        for lo,hi in [(-2.9,-2.25),(-1.05,1.05),(2.25,2.9)]:box('WallPier',(hi-lo,.16,2.7),((lo+hi)/2,0,1.35),finish_wall)
        for x in [-1.65,1.65]:
            box('BelowWindow',(1.2,.16,.90),(x,0,.45),finish_wall)
            box('AboveWindow',(1.2,.16,.70),(x,0,2.35),finish_wall)
            window(x)
    for z in [.12,2.64]:box('WallTrim',(5.8,.21,.12),(0,-.015,z),M['Timber'])
    for x in [-2.84,2.84]:box('CornerPost',(.12,.22,2.7),(x,0,1.35),M['Timber'])
    if style=='Workshop' and DETAIL:
        # Board seams stay within the wall volume and never span an opening.
        for i in range(27):
            x=-2.75+i*.21
            if front and abs(x)<2.0:continue
            if not front and (1.05<abs(x)<2.25):
                for z,h in [(.45,.9),(2.35,.7)]:box('CladdingSeam',(.012,.012,h),(x,-.086,z),M['TealDark'],0)
            else:box('CladdingSeam',(.012,.012,2.55),(x,-.086,1.35),M['TealDark'],0)

def roof(parent):
    global CURRENT
    CURRENT=group('Roof',parent)
    pitch=math.atan2(1.4,3.25)
    for side in [-1,1]:
        box('RoofSlope',(3.54,6.40,.09),(side*1.625,0,3.40),M['Roof'],rotation=(0,side*pitch,0))
        if DETAIL:
            for ix in range(8):
                x=side*(.20+ix*.405)
                for iy in range(19):
                    y=-3.12+iy*.345
                    shade=M['RoofLight'] if (ix*13+iy*7)%5==0 else M['Roof']
                    ob=box('Tile',(.42,.32,.045),(x,y,4.13-abs(x)*1.4/3.25),shade,.008,rotation=(0,side*pitch,0))
            for y in [-3.21,3.21]:
                box('Fascia',(3.58,.14,.17),(side*1.63,y,3.40),M['Wood'],rotation=(0,side*pitch,0))
        else:
            for y in [-3.21,3.21]:box('Fascia',(3.58,.14,.17),(side*1.63,y,3.40),M['Wood'],rotation=(0,side*pitch,0))
    for i in range(15):rod('RidgeCap',.095,.43,(0,-3.01+i*.43,4.15),M['RoofLight'],'Y')

def building(style,index):
    global CURRENT
    root=group('AR_'+style,None,(index*8,0,0))
    CURRENT=group('Floor',root)
    box('Base',(5.96,5.96,.18),(0,0,-.12),M['Stone'])
    if DETAIL:
        for i in range(24):
            shade=M['FloorLight'] if i%4==0 else M['Floor']
            box('Floorboard',(5.6,.231,.06),(0,-2.683+i*.233,-.03),shade,.003)
    else:box('Floor',(5.6,5.6,.06),(0,0,-.03),M['Floor'])
    for name,at,yaw in [('North',(0,2.9,0),math.pi),('South',(0,-2.9,0),0),('East',(2.9,0,0),math.pi/2),('West',(-2.9,0,0),-math.pi/2)]:
        wall(name,root,at,yaw,style,name=='South')
    # Gable caps belong to walls, so a cutaway removes the near gable as well.
    for name,y,turn in [('North',2.9,math.pi),('South',-2.9,0)]:
        CURRENT=bpy.data.objects[name] if index==0 else next(o for o in root.children if o.name.split('.')[0]==name)
        extrude_y('Gable',[(-2.9,2.7),(2.9,2.7),(0,4.05)],-.08,.08,M['Teal'] if style=='Workshop' else M['Plaster'])
        box('GableBeam',(.12,.18,1.18),(0,0,3.28),M['Timber'])
        box('GableVent',(.58,.06,.30),(0,-.10,3.24),M['Wood'])
    roof(root)
    return root

def initialize():
    spec=importlib.util.spec_from_file_location('init_architecture',SKILL/'scripts/init_master.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    module.main(module.parse(['--out',str(ROOT/'AR_Neighborhood_calibration.blend'),'--name','AR_Neighborhood','--height','4.25',
        '--ref-extra',str(ROOT/'ref/buildings.png'),str(ROOT/'ref/town.png'),'--cell','2','--cam-elev','25','--cam-az','30','--cam-dist','12','--cam-lens','50']))

def build(detail):
    global DETAIL
    DETAIL=detail;H.open_master(str(ROOT/'AR_Neighborhood_calibration.blend'));H.OWNER_TAG='phase:03_architecture' if detail else 'phase:02_architecture'
    for name,color,rough,metal in [
        ('Plaster',(.72,.66,.52),.95,0),('Timber',(.24,.10,.035),.8,0),('Wood',(.47,.25,.095),.74,0),
        ('Roof',(.055,.10,.19),.8,0),('RoofLight',(.085,.15,.26),.75,0),('Floor',(.39,.22,.10),.88,0),('FloorLight',(.45,.28,.13),.86,0),
        ('Stone',(.26,.29,.28),.94,0),('Teal',(.09,.23,.19),.86,0),('TealDark',(.05,.13,.11),.9,0),
        ('Glass',(.30,.47,.49),.22,0),('Canvas',(.19,.34,.23),.95,0),('Metal',(.04,.055,.06),.5,.5)]:mat(name,color,rough,metal)
    for i,style in enumerate(ASSETS):building(style,i)
    H.save_master(str(ROOT/('AR_Neighborhood_forms.blend' if detail else 'AR_Neighborhood_blockout.blend')))
    H.save_master(str(ROOT/'AR_Neighborhood_master.blend'))

def export():
    H.open_master(str(ROOT/'AR_Neighborhood_forms.blend'))
    mats=sorted({m.name:m for ob in H.col('LOW').objects if ob.type=='MESH' for m in ob.data.materials}.values(),key=lambda m:m.name)
    arrays=[np.ones((256,256,4),np.float32) for _ in range(3)];arrays[2][:,:,:3]=(.5,.5,1)
    for i,m in enumerate(mats):
        sh=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');c=list(sh.inputs['Base Color'].default_value)
        x=i%8*32;y=i//8*32
        arrays[0][y:y+32,x:x+32,:3]=[v*12.92 if v<=.0031308 else 1.055*v**(1/2.4)-.055 for v in c[:3]]
        arrays[1][y:y+32,x:x+32,:3]=(1,sh.inputs['Roughness'].default_value,sh.inputs['Metallic'].default_value)
    material=bpy.data.materials.new('AR_Neighborhood_Palette');nodes=material.node_tree.nodes;links=material.node_tree.links
    sh=next(n for n in nodes if n.type=='BSDF_PRINCIPLED');textures=[]
    for kind,arr in zip(['BaseColor','ORM','Normal'],arrays):
        path=ROOT/'textures'/('AR_Neighborhood_'+kind+'.png');im=bpy.data.images.new(kind,width=256,height=256,alpha=True);im.colorspace_settings.name='Non-Color'
        im.pixels.foreach_set(arr.ravel());im.filepath_raw=str(path);im.file_format='PNG';im.save();bpy.data.images.remove(im)
        im=bpy.data.images.load(str(path),check_existing=False);im.colorspace_settings.name='sRGB' if kind=='BaseColor' else 'Non-Color'
        tex=nodes.new('ShaderNodeTexImage');tex.image=im;tex.interpolation='Closest';textures.append(tex)
    links.new(textures[0].outputs['Color'],sh.inputs['Base Color']);split=nodes.new('ShaderNodeSeparateColor');links.new(textures[1].outputs['Color'],split.inputs[0])
    links.new(split.outputs['Green'],sh.inputs['Roughness']);links.new(split.outputs['Blue'],sh.inputs['Metallic'])
    normal=nodes.new('ShaderNodeNormalMap');links.new(textures[2].outputs['Color'],normal.inputs['Color']);links.new(normal.outputs[0],sh.inputs['Normal'])
    indices={m.name:i for i,m in enumerate(mats)}
    manifest={'units':'metres','blender_up':'Z','blender_front':'-Y','engine_up':'Y','engine_front':'+Z','models':{},
      'inferred':'See asset-brief.md: perspective reference, single inhabited floor, all dimensions and hidden construction inferred',
      'art_acceptance':'work in progress; not a passed final reference gate','texture_contract':{'size':[256,256],'BaseColor':'sRGB','ORM':'Non-Color R=AO(1) G=roughness B=metallic','Normal':'Non-Color OpenGL +Y neutral'}}
    for style in ASSETS:
        source=bpy.data.objects['AR_'+style];root=bpy.data.objects.new('AR_'+style+'_Export',None);H.col('EXPORT').objects.link(root);outputs=[]
        for part in source.children:
            copies=[]
            for ob in part.children_recursive:
                if ob.type!='MESH':continue
                copy=ob.copy();copy.data=ob.data.copy();copy.parent=None;H.col('EXPORT').objects.link(copy)
                # Inferred recessed workshop front keeps the east-west street clear.
                adaptation=Matrix.Translation((0,.325,0))@Matrix.Diagonal((1,.88,1,1)) if style=='Workshop' else Matrix.Identity(4)
                copy.matrix_world=adaptation@source.matrix_world.inverted()@ob.matrix_world
                bpy.ops.object.select_all(action='DESELECT');copy.select_set(True);bpy.context.view_layer.objects.active=copy
                H.apply_all_modifiers(copy);bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
                old=list(copy.data.materials);bm=bmesh.new();bm.from_mesh(copy.data)
                bmesh.ops.triangulate(bm,faces=list(bm.faces));bmesh.ops.dissolve_degenerate(bm,dist=1e-7,edges=list(bm.edges));bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(copy.data);bm.free()
                # Dissolve may produce a polygon; re-lock triangles before palette UVs.
                bm=bmesh.new();bm.from_mesh(copy.data);bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(copy.data);bm.free()
                uv=copy.data.uv_layers.new(name='PaletteUV');uv.active_render=True
                for p in copy.data.polygons:
                    slot=indices[old[p.material_index].name];u=(slot%8+.5)/8;v=(slot//8+.5)/8
                    for k,loop in enumerate(p.loop_indices):uv.data[loop].uv=(u+[-.012,.012,0][k%3],v+[-.012,-.012,.012][k%3])
                    p.material_index=0
                copy.data.materials.clear();copy.data.materials.append(material);copies.append(copy)
            bpy.ops.object.select_all(action='DESELECT')
            for ob in copies:ob.select_set(True)
            bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();joined=bpy.context.object
            joined.name='AR_'+style+'_'+part.name.split('.')[0]+'_LOD0';joined.data.name=joined.name;joined.parent=root;outputs.append(joined)
        bpy.ops.object.select_all(action='DESELECT');root.select_set(True)
        for ob in outputs:ob.select_set(True)
        tris=sum(len(o.data.polygons) for o in outputs);assert tris<80000,(style,tris)
        file=ROOT/'exports'/('AR_'+style+'.glb')
        bpy.ops.export_scene.gltf(filepath=str(file),export_format='GLB',use_selection=True,export_animations=False,export_yup=True)
        manifest['models'][style]={'file':file.name,'triangles':tris,'groups':[o.name for o in outputs],'materials':1,'embedded_images':3,'clear_room_m':[5.6,4.928 if style=='Workshop' else 5.6],'floor_top_m':0,'door_clear_width_m':3.8 if style=='Workshop' else 1.4}
        for ob in [root]+outputs:ob.hide_render=True;ob.hide_set(True)
    (ROOT/'exports/asset-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');H.save_master(str(ROOT/'AR_Neighborhood_delivery.blend'))
    print('ARCHITECTURE EXPORT',[(k,v['triangles']) for k,v in manifest['models'].items()])

def roundtrip():
    manifest=json.loads((ROOT/'exports/asset-manifest.json').read_text());report={'models':{},'failures':[]}
    for name,data in manifest['models'].items():
        file=ROOT/'exports'/data['file'];raw=file.read_bytes();n=struct.unpack_from('<I',raw,12)[0];gltf=json.loads(raw[20:20+n])
        bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(file))
        meshes=[o for o in bpy.context.scene.objects if o.type=='MESH'];tris=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in meshes)
        if tris!=data['triangles']:report['failures'].append(name+' triangle mismatch')
        if len(meshes)!=6:report['failures'].append(name+' missing independent facade/floor/roof groups')
        if len(gltf.get('images',[]))!=3 or any('uri' in x for x in gltf.get('images',[])+gltf.get('buffers',[])):report['failures'].append(name+' external or missing images')
        report['models'][name]={'triangles':tris,'mesh_names':[o.name for o in meshes],'embedded_images':len(gltf.get('images',[]))}
    (ROOT/'review/roundtrip.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
    assert not report['failures'],report['failures']
