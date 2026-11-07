#!/usr/bin/env python3
"""Actual Luau services, deterministic engine/persistence adapters; offline only."""
from pathlib import Path
import subprocess,sys,tempfile
R=Path(__file__).resolve().parents[2]
files={**{f"ReplicatedStorage.Shared.Config{'' if p.stem=='init' else '.'+p.stem}":p for p in (R/'src/shared/Config').glob('*.luau')},
 **{f'ReplicatedStorage.Shared.{n}':R/f'src/shared/{n}.luau' for n in ['Types','AnimalMath','BattleMath','ProgressionMath','ResearchMath']},
 **{f'ServerScriptService.Server.Services.{n}':R/f'src/server/Services/{n}.luau' for n in ['AnimalService','ProfileMigration','TradeService','TradePolicy','PlayerMutationGuard','StarterService','HudCommerceService','TeamService']}}
f='\n'.join(f'factories["{k}"]=function(require,script)\n{p.read_text()}\nend\n' for k,p in files.items())
s=(R/'tests/progression/environment.luau').read_text().replace('-- INSERT_FACTORIES',f)
s+='\n'+(Path(__file__).parent/'cases.luau').read_text()
with tempfile.TemporaryDirectory(prefix='coder-offline-') as d:
 p=Path(d)/'run.luau';p.write_text(s)
 raise SystemExit(subprocess.run([sys.argv[1],str(p)],cwd=R).returncode)
