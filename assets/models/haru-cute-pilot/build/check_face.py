#!/usr/bin/env python3
"""Reproduce the non-destructive UV-face shader prototype in an isolated Godot project."""
from pathlib import Path
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import tempfile


def main():
    repo=Path(__file__).resolve().parents[4]
    pilot=repo/'assets/models/haru-cute-pilot'
    output=pilot/'review/texture-face'
    spec=importlib.util.spec_from_file_location('face_landmarks',pilot/'build/face_landmarks.py')
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.produce()
    files=['raw/CH_Haru_JRPG_Pilot_Raw.glb','build/check_face.gd','build/texture_face.gdshader','review/texture-face/landmarks.json']
    project=Path(tempfile.mkdtemp(prefix='hourglass-haru-face-'))
    sources=[]
    for name in files:
        source=pilot/name
        target=project/'assets/models/haru-cute-pilot'/name
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(source,target)
        sources.append({'file':name,'sha256':hashlib.sha256(source.read_bytes()).hexdigest()})
    (project/'project.godot').write_text('''config_version=5
[application]
config/name="Haru UV face shader prototype"
config/features=PackedStringArray("4.7", "GL Compatibility")
[display]
window/size/viewport_width=1000
window/size/viewport_height=1000
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
anti_aliasing/quality/msaa_3d=2
''')
    (output/'source-fixture.json').write_text(json.dumps({'project':str(project),'sources':sources,'purpose':'Static raw-mesh shader feasibility; no actor or Sim; no source image/geometry edits.'},indent=2)+'\n')
    godot=os.environ.get('GODOT_BIN','/Applications/Godot.app/Contents/MacOS/Godot')
    for command,log in [([godot,'--headless','--editor','--import','--path',str(project)],'editor-import.log'),([godot,'--path',str(project),'--script','res://assets/models/haru-cute-pilot/build/check_face.gd','--',f'--output={output}'],'prototype.log')]:
        result=subprocess.run(command,cwd=project,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=90)
        (output/log).write_text(result.stdout)
        if result.returncode or re.search(r'(?m)^(?:SCRIPT ERROR|ERROR):',result.stdout):
            raise RuntimeError(f'Godot failed; see {output/log}')
    for source in sources:
        source['sha256_after'] = hashlib.sha256((pilot/source['file']).read_bytes()).hexdigest()
    fixture = json.loads((output/'source-fixture.json').read_text())
    fixture['sources'] = sources
    fixture['fingerprint_policy'] = 'Provenance only; not checks or pass/fail gates.'
    (output/'source-fixture.json').write_text(json.dumps(fixture,indent=2)+'\n')
    print(f'Static face prototype saved: {output}')


if __name__=='__main__':
    main()
