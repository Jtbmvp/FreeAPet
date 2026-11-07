#!/usr/bin/env python3
"""Run real TradeService source with deterministic engine/profile adapters.

No Roblox connection or real profile I/O. Save completion/crash cuts are models,
not reproduction of an actual DataStore outage. Existing progression environment
is read-only input. This runner owns only tests/security-trade and its report.
"""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
files = {
    **{f"ReplicatedStorage.Shared.Config{'' if p.stem == 'init' else '.' + p.stem}": p
       for p in (ROOT / 'src/shared/Config').glob('*.luau')},
    "ReplicatedStorage.Shared.Types": ROOT / 'src/shared/Types.luau',
    "ReplicatedStorage.Shared.ProgressionMath": ROOT / 'src/shared/ProgressionMath.luau',
    "ServerScriptService.Server.Services.TradeService": ROOT / 'src/server/Services/TradeService.luau',
}
sources = {k: p.read_text() for k, p in files.items()}
factories = '\n'.join(f'factories["{k}"] = function(require, script)\n{s}\nend\n' for k, s in sources.items())
program = (ROOT / 'tests/progression/environment.luau').read_text().replace('-- INSERT_FACTORIES', factories)
program += '\n' + (Path(__file__).parent / 'cases.luau').read_text()
with tempfile.TemporaryDirectory(prefix='sentinel-trade-') as tmp:
    source = Path(tmp) / 'run.luau'
    source.write_text(program)
    run = subprocess.run([sys.argv[1] if len(sys.argv) > 1 else 'luau', str(source)],
                         cwd=ROOT, capture_output=True, text=True, timeout=30)
report = {
    'scope': 'actual TradeService with synthetic engine/profile adapters; no live saves',
    'sourceSha256': {str(files[k].relative_to(ROOT)): hashlib.sha256(v.encode()).hexdigest()
                     for k, v in sources.items()},
    'sourceChangedDuringRun': [k for k, p in files.items() if p.read_text() != sources[k]],
    'exitCode': run.returncode, 'stdout': run.stdout, 'stderr': run.stderr,
}
out = ROOT / 'build/sentinel-security-2026-11-04'
out.mkdir(parents=True, exist_ok=True)
(out / 'trade-regression-results.json').write_text(json.dumps(report, indent=2) + '\n')
print(run.stdout, end='')
print(run.stderr, end='', file=sys.stderr)
raise SystemExit(run.returncode or bool(report['sourceChangedDuringRun']))
