#!/usr/bin/env python3
from pathlib import Path
import subprocess,sys,tempfile,json
R=Path(__file__).resolve().parents[2]
files={f'Client.Battle.{n}':R/f'src/client/Battle/{n}.luau'for n in ['BattleCamera','BattleIntro','BattleSettings','ShotRecipes','CapsuleRigFallback','CapsuleClipPlayer','CapsuleSequence']}
files.update({f'Client.Battle.Fx.{n}':R/f'src/client/Battle/Fx/{n}.luau'for n in ['AttackProfiles','AttackPresentation','EffectPool']})
files['Client.Battle.Fx']=R/'src/client/Battle/Fx/init.luau'
files['Server.Services.BattlePresentationService']=R/'src/server/Services/BattlePresentationService.luau'
files.update({f"ReplicatedStorage.Shared.Config{'' if p.stem=='init' else '.'+p.stem}":p for p in (R/'src/shared/Config').glob('*.luau')})
common=(R/'src/client/Battle/Fx/Common.luau').read_text();common=common[common.index('local damageLabels:'):common.index('export type ProjectileOptions')]
f='\n'.join(f'factories["{k}"]=function(require,script)\n{p.read_text()}\nend\n'for k,p in files.items())
s=(R/'tests/progression/environment.luau').read_text().replace('-- INSERT_FACTORIES','local RaycastParams,TweenInfo\nlocal CFrame,Instance,NumberSequence,NumberSequenceKeypoint,NumberRange,ColorSequence,UDim2\n'+f)
s+='\n'+(Path(__file__).parent/'environment.luau').read_text().replace('-- COMMON_HIT_SECTION',common)
def lua(v):
 if isinstance(v,dict):return '{'+','.join('['+json.dumps(k)+']='+lua(x)for k,x in v.items())+'}'
 if isinstance(v,list):return '{'+','.join(lua(x)for x in v)+'}'
 if isinstance(v,str):return json.dumps(v)
 if v is True:return 'true'
 if v is False:return 'false'
 if v is None:return 'nil'
 return str(v)
capsule=json.loads((R/'design/terra/map-v3-preflight-2026-11-03/uploaded-import/capsule-original-rig-data.json').read_text())
s+='\nlocal capsuleFixture='+lua(capsule)+'\n'
s+='\n'+(Path(__file__).parent/'cases.luau').read_text()
with tempfile.TemporaryDirectory(prefix='battle-presentation-')as d:
 p=Path(d)/'run.luau';p.write_text(s)
 r=subprocess.run([sys.argv[1],str(p)],cwd=R,capture_output=True,text=True)
 print(r.stdout,end='');print(r.stderr,end='',file=sys.stderr)
 if r.returncode:(R/'build/coder-battle-integration-2026-11-05/failed-test.luau').write_text(s)
 raise SystemExit(r.returncode)
