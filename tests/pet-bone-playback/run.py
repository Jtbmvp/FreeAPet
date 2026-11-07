#!/usr/bin/env python3
"""Actual client PetAnimator + Pixel data with synthetic Bone/CFrame/engine adapters."""
from pathlib import Path
import subprocess,sys,tempfile,json
R=Path(__file__).resolve().parents[2]
files={**{f"ReplicatedStorage.Shared.Config{'' if p.stem=='init' else '.'+p.stem}":p for p in (R/'src/shared/Config').glob('*.luau')},
 **{f'ReplicatedStorage.Shared.{n}':R/f'src/shared/{n}.luau' for n in ['AnimalMath','ProgressionMath']},
 'ReplicatedStorage.Shared.OriginalPets.Catalog':R/'src/shared/OriginalPets/Catalog.luau',
 'ReplicatedStorage.Shared.OriginalPets.Contract':R/'src/shared/OriginalPets/Contract.luau',
 **{f'ReplicatedStorage.Shared.OriginalPets.Clips.{p.stem}':p for p in (R/'src/shared/OriginalPets/Clips').glob('*.luau')},
 'Client.Controllers.PetAnimator':R/'src/client/Controllers/PetAnimator.luau'}
f='\n'.join(f'factories["{k}"]=function(require,script)\n{p.read_text()}\nend\n' for k,p in files.items())
s=(R/'tests/progression/environment.luau').read_text().replace('-- INSERT_FACTORIES','local CFrame\n'+f)
s+='\n'+(Path(__file__).parent/'cases.luau').read_text()
# Exercise the real faint() helper separately: a native clip must suppress root tween.
b=(R/'src/client/Controllers/BattleScreen.luau').read_text();faint=b[b.index('local function faint('):b.index('function BattleScreen.Start()')]
common=(R/'src/client/Battle/Fx/Common.luau').read_text()
default=common[common.index('function Common.DefaultAttack('):common.index('-- Plays the attacker')]
hit=common[common.index('function Common.Hit(ctx:'):common.index('export type ProjectileOptions')]
s+='\n'+(Path(__file__).parent/'faint-environment.luau').read_text().replace('-- ACTUAL_FAINT_FUNCTION',faint).replace('-- ACTUAL_DEFAULT_ATTACK',default).replace('-- ACTUAL_HIT',hit)
with tempfile.TemporaryDirectory(prefix='pet-bone-playback-') as d:
 p=Path(d)/'run.luau';p.write_text(s)
 r=subprocess.run([sys.argv[1],str(p)],cwd=R,capture_output=True,text=True)
 print(r.stdout,end='');print(r.stderr,end='',file=sys.stderr)
 raise SystemExit(r.returncode)
