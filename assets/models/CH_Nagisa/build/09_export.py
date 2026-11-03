"""Use the skill exporter and keep each LOD independently importable, with the same rig/clips."""
import bpy,sys,os,json,importlib.util
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
skill=Path(os.environ.get('BLENDER_ASSET_SKILL',str(Path.home()/'.codex/skills/blender-image-to-3d')))
spec=importlib.util.spec_from_file_location('asset_export',skill/'scripts/export_delivery.py')
delivery=importlib.util.module_from_spec(spec);spec.loader.exec_module(delivery)
args=delivery.parse(['--blend',str(ROOT/'CH_Nagisa_delivery.blend'),'--out',str(ROOT/'exports'),
    '--name','CH_Nagisa','--format','GLB','--collections','LOW,RIG_DEF,SOCKETS','--no-apply',
    '--engine','Godot 4.7 Compatibility','--inferred',
    'real height,hidden anatomy,garment depth,hand contours,shoe underside,face depth,material response,all animation'])
delivery.main(args)
manifest_path=ROOT/'exports/asset-manifest.json';manifest=json.loads(manifest_path.read_text())
arm=bpy.data.objects['CH_Nagisa_Rig'];lod0=[bpy.data.objects['CH_Nagisa_'+p+'_LOD0'] for p in ['Body','Face']]
for lod in [1,2]:
    meshes=[bpy.data.objects['CH_Nagisa_'+p+'_LOD'+str(lod)] for p in ['Body','Face']]
    for ob in lod0:ob.hide_render=True
    for ob in meshes:ob.hide_render=False;ob.hide_set(False)
    path=ROOT/'exports'/f'CH_Nagisa_LOD{lod}.glb'
    delivery.export(str(path),meshes+[arm],args)
    manifest['files']['LOD'+str(lod)]=str(path)
    manifest['lods'].append({'level':lod,'objects':[m.name for m in meshes],'tris':sum(delivery.tri_count(m) for m in meshes)})
    for ob in meshes:ob.hide_render=True
for ob in lod0:ob.hide_render=False
manifest['texture_contract']=json.loads((ROOT/'textures/texture-contract.json').read_text())
manifest['rest_pose']='A-pose in the source; game clips begin from their authored pose. In-place locomotion.'
manifest['lod_policy']='Separate GLBs with the same rig/morphs. Authored targets: LOD1 below 100 px, LOD2 below 45 px. Automatic distance switching in the town is not implemented yet.'
manifest['validation_notes']=['Coincident seam vertices are intentional between cloth layers and eye/lash corners.',
    'No cloth solver; apron front/back bones have authored motion.']
manifest['source_texture_files']=manifest['dependencies']
manifest['dependencies']=[]  # All three textures are embedded in each GLB.
manifest['files']={k:Path(v).name for k,v in manifest['files'].items()}
manifest['source']='../CH_Nagisa_delivery.blend'
manifest_path.write_text(json.dumps(manifest,indent=2))
contract_path=ROOT/'exports/animation-contract.json'
contract=json.loads(contract_path.read_text())
for clip in contract['clips']:
    if clip['name']=='walk':clip['speed_mps']=float(bpy.data.actions['walk'].get('speed_mps',1.6))
contract_path.write_text(json.dumps(contract,indent=2))
print('EXPORTED THREE LODS')
