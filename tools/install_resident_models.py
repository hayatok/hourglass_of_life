"""Install verified GLBs and derive editable Godot wrapper scenes from their source contracts."""
from pathlib import Path
import json,shutil

ROOT=Path(__file__).resolve().parents[1]
ASSETS={'nagisa':'Nagisa','ryo':'Ryo','rin':'Rin','rin_adult':'RinAdult',
        'osamu':'Osamu','fumi':'Fumi','maho':'Maho','ritsu':'Ritsu','aoi':'Aoi'}

for resident,name in ASSETS.items():
    prefix='CH_'+name;source=ROOT/'assets/models'/prefix
    for rel in ['review/08_animation/geometry-checks.json','review/09_roundtrip/rest-contract-checks.json']:
        report=json.loads((source/rel).read_text())
        if report['failures']:raise RuntimeError(str(source/rel)+': '+str(report['failures']))
    destination=ROOT/'game/assets/models'/resident;destination.mkdir(parents=True,exist_ok=True)
    for suffix in ['', '_LOD1','_LOD2']:
        file=prefix+suffix+'.glb';shutil.copyfile(source/'exports'/file,destination/file)
    contract=json.loads((source/'exports/animation-contract.json').read_text())
    textures=json.loads((source/'textures/texture-contract.json').read_text())
    names=[p['name'] for p in textures['palette']]
    hair=[names.index(n) for n in ['Hair','Hair mid','Hair strand']]
    profile_file=source/'profile.json'
    profile=json.loads(profile_file.read_text()) if profile_file.exists() else {'height':1.65}
    speed=next(c.get('speed_mps',1.6) for c in contract['clips'] if c['name']=='walk')
    scene=f'''[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://game/scripts/jrpg_resident_model.gd" id="1"]
[ext_resource type="PackedScene" path="res://game/assets/models/{resident}/{prefix}.glb" id="2"]

[node name="{name}" type="Node3D"]
script = ExtResource("1")
rest_height = {profile['height']:.6f}
walk_speed = {speed:.6f}
hair_cells = Vector3i({hair[0]},{hair[1]},{hair[2]})

[node name="Model" parent="." instance=ExtResource("2")]
'''
    (ROOT/'game/scenes/characters'/f'{resident}.tscn').write_text(scene)
    print('Installed',resident,'height',round(profile['height'],3),'stride m/s',round(speed,3),'hair cells',hair)
