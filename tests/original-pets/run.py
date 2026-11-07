#!/usr/bin/env python3
"""Actual staged modules with synthetic engine/AnimationTrack adapters.
No Studio import, asset fetch, DataStore access or art modification.
"""
from pathlib import Path
import subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2]
files={
 **{f"ReplicatedStorage.Shared.Config{'' if p.stem=='init' else '.'+p.stem}":p for p in (ROOT/'src/shared/Config').glob('*.luau')},
 **{f'ReplicatedStorage.Shared.{name}':ROOT/f'src/shared/{name}.luau' for name in ['ProgressionMath','AnimalMath','OriginalPets.Catalog','OriginalPets.Contract'] if '.' not in name},
 'ReplicatedStorage.Shared.OriginalPets.Catalog':ROOT/'src/shared/OriginalPets/Catalog.luau',
 'ReplicatedStorage.Shared.OriginalPets.Contract':ROOT/'src/shared/OriginalPets/Contract.luau',
 'StarterPlayer.StarterPlayerScripts.Client.Animation.OriginalPetPlayer':ROOT/'src/client/Animation/OriginalPetPlayer.luau',
}
factories='\n'.join(f'factories["{k}"]=function(require,script)\n{p.read_text()}\nend\n' for k,p in files.items())
program=(ROOT/'tests/progression/environment.luau').read_text().replace('-- INSERT_FACTORIES','local CFrame\nlocal Instance\n'+factories)
program+='\n'+(ROOT/'tests/original-pets/cases.luau').read_text()
with tempfile.TemporaryDirectory(prefix='freeapet-originals-') as directory:
 p=Path(directory)/'run.luau';p.write_text(program)
 raise SystemExit(subprocess.run([sys.argv[1] if len(sys.argv)>1 else 'luau',str(p)],cwd=ROOT).returncode)
