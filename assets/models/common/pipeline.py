"""Shared reproducible stages; each resident has its own calibrated master and profile.
The first resident's topology/rig/export scripts are templates, not duplicated character shapes.
"""
import sys,types,importlib.util,json,math,os
from pathlib import Path
import bpy

COMMON=Path(__file__).resolve().parent
SOURCE=COMMON.parent/'CH_Nagisa/build'
sys.path.insert(0,str(SOURCE));sys.path.insert(0,str(COMMON))
import mesh_helpers as H
from dimensions import Dimensions

def template(root,file,name):
    module=types.ModuleType(name)
    module.__file__=str(root/'build'/file)
    sys.modules[name]=module
    source=(SOURCE/file).read_text().replace('CH_Nagisa',root.name)
    exec(compile(source,module.__file__,'exec'),module.__dict__)
    return module

def warp(root):
    d=Dimensions(root);maximum=0;worst=None
    for collection in ['LOW','HIGH']:
        for ob in list(H.col(collection).objects):
            if ob.type not in ['MESH','CURVE']:continue
            bpy.ops.object.select_all(action='DESELECT')
            hidden=ob.hide_get();ob.hide_set(False);ob.select_set(True)
            bpy.context.view_layer.objects.active=ob
            if ob.type=='CURVE':bpy.ops.object.convert(target='MESH')
            # Freeze construction transforms before applying the authored proportional map.
            bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
            for vertex in ob.data.vertices:
                before=vertex.co.copy();vertex.co=d.to_model(before)
                error=(d.to_base(vertex.co)-before).length
                if error>maximum:
                    maximum=error;worst=(ob.name,tuple(before),tuple(vertex.co),tuple(d.to_base(vertex.co)))
            if 'coverage_cut_z' in ob:ob['coverage_cut_z']=d.z(ob['coverage_cut_z'])
            ob.hide_set(hidden)
    if maximum>1e-4:raise RuntimeError('Proportion inverse exceeds tolerance: '+str((maximum,worst)))
    print('PROPORTION ROUNDTRIP',maximum)

def initialize(root):
    skill=Path(os.environ.get('BLENDER_ASSET_SKILL',str(Path.home()/'.codex/skills/blender-image-to-3d')))
    spec=importlib.util.spec_from_file_location('initialize_master',skill/'scripts/init_master.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    profile=json.loads((root/'profile.json').read_text())
    args=['--out',str(root/(root.name+'_master.blend')),'--name',root.name,
          '--height',str(profile['height']),'--ref-front',str(root/'ref/front.png'),
          '--ref-right',str(root/'ref/side.png'),'--ref-back',str(root/'ref/back.png'),
          '--subject-frac',str(profile['reference']['subject_fraction']),
          '--ground-frac',str(profile['reference']['ground_fraction']),
          '--cell','2','--cam-elev','25','--cam-az','25','--cam-dist','5','--cam-lens','50']
    module.main(module.parse(args))
    H.save_master(str(root/(root.name+'_calibration.blend')))

def run(root,stage):
    root=Path(root).resolve();prefix=root.name
    b=template(root,'02_blockout.py','02_blockout')
    if stage in ['02','03']:
        import resident_forms as forms
        f=template(root,'03_forms.py','03_forms')
        profile=json.loads((root/'profile.json').read_text())
        if stage=='02':
            initialize(root)
            b.build()
            forms.primary(root,b,f,profile)
            H.save_master(str(root/(prefix+'_canonical.blend')))
        else:
            H.open_master(str(root/(prefix+'_canonical.blend')))
            forms.refine(root,b,f,profile)
        warp(root)
        H.save_master(str(root/(prefix+'_master.blend')))
        H.save_master(str(root/(prefix+('_blockout.blend' if stage=='02' else '_forms.blend'))))
    else:
        file={'04':'04_topology.py','05':'05_materials.py','06':'06_rig.py',
              '08':'08_animation.py','08-check':'08_check_animation.py','09':'09_export.py',
              '09-check':'09_check_import.py'}[stage]
        template(root,file,'__main__')

if __name__=='__main__':
    args=sys.argv[sys.argv.index('--')+1:]
    run(args[0],args[1])
