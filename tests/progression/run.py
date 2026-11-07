#!/usr/bin/env python3
"""Execute actual Luau modules against synthetic in-memory engine adapters.
This does not touch Roblox/Datastores or substitute for Studio persistence QA.
Usage: python3 tests/progression/run.py /path/to/luau
"""
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FILES = {
    **{f"ReplicatedStorage.Shared.Config{'' if p.stem == 'init' else '.' + p.stem}": p for p in (ROOT / 'src/shared/Config').glob('*.luau')},
    **{f"ReplicatedStorage.Shared.{name}": ROOT / f'src/shared/{name}.luau' for name in ['Types', 'ProgressionMath', 'BattleMath', 'AnimalMath', 'ResearchMath']},
    **{f"ServerScriptService.Server.Services.{name}": ROOT / f'src/server/Services/{name}.luau' for name in ['ProfileMigration', 'ProgressionService', 'HomeService', 'PlayerDataService', 'TradeService', 'TradePolicy', 'PlayerMutationGuard', 'ResearchService', 'BattleService']},
}
# Factories contain the source verbatim; requires resolve to the real dependency
# or an explicit engine adapter. No progression/migration formula is rewritten.
factories = '\n'.join(f'factories["{key}"] = function(require, script)\n{path.read_text()}\nend\n' for key, path in FILES.items())
program = (ROOT / 'tests/progression/environment.luau').read_text().replace('-- INSERT_FACTORIES', factories)
program += '\n' + (ROOT / 'tests/progression/cases.luau').read_text()
with tempfile.TemporaryDirectory(prefix='freeapet-progression-') as output:
    path = Path(output) / 'run.luau'
    path.write_text(program)
    result = subprocess.run([sys.argv[1] if len(sys.argv) > 1 else 'luau', str(path)], cwd=ROOT)
    raise SystemExit(result.returncode)
