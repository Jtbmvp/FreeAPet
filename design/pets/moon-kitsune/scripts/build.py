"""Moon Kitsune: python build.py [export|check|strips DIR clip...] (bpy module or blender -b -P build.py -- ...)."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path[:0] = [HERE, os.path.join(HERE, "..", "..", "_shared")]
import kitsune_clips  # noqa: E402
import kitsune_rig  # noqa: E402
import petrig  # noqa: E402

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
petrig.build(os.path.dirname(HERE), kitsune_rig, kitsune_clips, args)
