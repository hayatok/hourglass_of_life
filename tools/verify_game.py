"""Run real engine checks with explicit completion markers and strict error handling.
Godot can otherwise exit zero after a GDScript error. Logs and the result ledger stay local.
"""
from pathlib import Path
import argparse,json,os,re,shutil,subprocess,sys,time

ROOT=Path(__file__).resolve().parents[1]
CHECKS={
 'simulation':('test_simulation.gd',r'Simulation checks: \d+ passed, 0 failed'),
 'social':('test_social_life.gd',r'Social life checks: \d+ passed, 0 failed'),
 'work':('test_work_family.gd',r'Work/family checks: \d+ passed, 0 failed'),
 'life':('test_life_course.gd',r'Life course checks: \d+ passed, 0 failed'),
 'cognition':('test_cognition.gd',r'Cognition checks: \d+ passed, 0 failed'),
 'knowledge_exchange':('test_knowledge_exchange.gd',r'Knowledge exchange checks: \d+ passed, 0 failed'),
 'resident_activities':('test_resident_activities.gd',r'Resident activity checks: \d+ passed, 0 failed'),
 'autonomy':('test_autonomy.gd',r'Autonomy checks: \d+ passed, 0 failed'),
 'resident_agenda':('test_resident_agenda.gd',r'Resident agenda checks: \d+ passed, 0 failed'),
 'agenda_preparation':('test_agenda_preparation.gd',r'Agenda preparation checks: \d+ passed, 0 failed'),
 'resident_support':('test_resident_support_plans.gd',r'Resident support plan checks: \d+ passed, 0 failed'),
 'support_index':('test_support_index.gd',r'Support index checks: \d+ passed, 0 failed'),
 'resident_lod':('test_resident_lod.gd',r'Resident LOD checks: \d+ passed, 0 failed'),
 'resident_proposals':('test_resident_proposals.gd',r'Resident proposal UI checks: \d+ passed, 0 failed'),
 'observation_hud':('test_observation_hud.gd',r'Observation HUD checks: \d+ passed, 0 failed'),
 'population_ui':('test_population_ui.gd',r'Population UI checks: \d+ passed, 0 failed'),
 'population':('test_population.gd',r'Population checks: \d+ passed, 0 failed'),
 'population_environment':('test_population_environment.gd',r'Population environment checks: \d+ passed, 0 failed'),
 'jrpg_renewal':('test_jrpg_renewal_gameplay.gd',r'JRPG renewal gameplay checks: \d+ passed, 0 failed'),
 'haru_jrpg':('test_haru_jrpg_gameplay.gd',r'Haru JRPG gameplay checks: \d+ passed, 0 failed'),
 'population_collaboration':('test_population_collaboration.gd',r'Population collaboration checks: \d+ passed, 0 failed'),
 'new_resident_life':('test_new_resident_life.gd',r'New resident life checks: \d+ passed, 0 failed'),
 'autonomy_presentation':('test_autonomy_presentation.gd',r'Autonomy presentation checks: \d+ passed, 0 failed'),
 'social_chain_presentation':('test_social_chain_presentation.gd',r'Social chain presentation checks: \d+ passed, 0 failed'),
 'character':('test_character_model.gd',r'Character import and motion checks: PASS'),
 'cast':('test_resident_models.gd',r'Resident cast and growth checks: PASS'),
 'activities':('test_activity_furniture.gd',r'Furniture and activity checks: \d+ passed, 0 failed'),
 'neighborhood':('test_neighborhood.gd',r'Neighborhood checks: \d+ passed, 0 failed')
}
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--godot',default=os.environ.get('GODOT_BIN') or shutil.which('godot') or '/Applications/Godot.app/Contents/MacOS/Godot')
p.add_argument('--gpu',action='store_true',help='Also render character, cast and full-scene checks on a real display')
p.add_argument('--checks',nargs='+',choices=CHECKS,default=list(CHECKS))
p.add_argument('--output',type=Path,default=ROOT/'builds/verification',help='Keep separate logs for focused follow-up checks')
a=p.parse_args();out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
results=[]

def run(name,args,marker=None,timeout=180):
    started=time.monotonic();command=[a.godot]+args+['--path',str(ROOT)]
    failed=None;text=''
    try:
        result=subprocess.run(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=timeout)
        text=result.stdout
        if result.returncode:failed='exit '+str(result.returncode)
    except subprocess.TimeoutExpired as e:
        text=e.stdout or ''
        if isinstance(text,bytes):text=text.decode(errors='replace')
        failed='timed out before completion'
    except OSError as e:failed=str(e)
    if re.search(r'SCRIPT ERROR:|(^|\n)ERROR:|Parse Error:',text):failed='engine reported an error'
    if marker and not re.search(marker,text):failed=failed or 'completion marker missing'
    (out/(name+'.log')).write_text(text)
    row={'check':name,'passed':failed is None,'seconds':round(time.monotonic()-started,2),'failure':failed,
         'log':name+'.log','completion':next((l for l in text.splitlines() if marker and re.search(marker,l)),None)}
    results.append(row);print(name,'PASS' if row['passed'] else 'FAIL: '+str(failed),flush=True)
    (out/'results.json').write_text(json.dumps(results,indent=2)+'\n')
    if failed:
        print(text[-3000:]);sys.exit(1)

run('import',['--headless','--editor','--import'])
for name in a.checks:
    file,marker=CHECKS[name]
    run(name,['--headless','--script','tests/'+file],marker,timeout=600 if name in ['life','autonomy','social_chain_presentation'] else 180)
if a.gpu:
    for name in ['character','cast','resident_lod','activities','neighborhood','observation_hud','resident_proposals','population_ui','population_environment','haru_jrpg','jrpg_renewal','population_collaboration','autonomy_presentation','social_chain_presentation']:
        file,marker=CHECKS[name];run(name+'-gpu',['--script','tests/'+file],marker,timeout=600 if name=='social_chain_presentation' else 180)
    run('scene-gpu',['--script','tests/test_scene.gd'],r'Scene/UI smoke: PASS',timeout=600)
print('All requested engine checks completed.',flush=True)
