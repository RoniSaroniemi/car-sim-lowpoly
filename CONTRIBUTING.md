# Working on this example

Reproduce the baseline before tuning it. Keep physics, skeleton binding and shader changes separately reviewable; compare the same speed and boundary conditions. Explain which observed behaviour a change improves and how you checked it.

Run `python3 tools/demo.py verify` after changing the graph or runtime implementation. Use plain-body mode with local detail disabled to inspect the skin, and then compare textured/ghost views. Update documentation when you change topology assumptions or solver ownership.

`checksums.json` describes the published handover, not arbitrary local edits. If you deliberately update shipped model/source inputs, regenerate that manifest for the files it already lists:

```python
from pathlib import Path
import hashlib, json
p = Path('checksums.json')
files = json.loads(p.read_text())
p.write_text(json.dumps({name: hashlib.sha256(Path(name).read_bytes()).hexdigest()
                         for name in files}, indent=2) + '\n')
```

The GitHub workflow checks package integrity, the seven cabin-fit unit cases, six structural crash runs, seven wheel cases, bone binding, wheel load transfer, detachment, replay and reset, plus shared-runtime driving/steering/braking checks on Linux using the pinned standard Godot release. Rendered screenshot review remains separate because headless dummy rendering does not validate shader appearance.

Do not introduce a second full-mass chassis or make mesh detail responsible for physical load transfer. When extending wheel rotation, breakable joints, general-world contact or detached bodies, define which solver owns each mass and how momentum crosses the boundary.

Keep scenes limited to input, camera, level and inspection. Put vehicle updates
in the shared runtime/dynamics/wheel/structure modules; tune per-car values in
the vehicle profile. Do not copy physics into `driving_sandbox.gd`.
