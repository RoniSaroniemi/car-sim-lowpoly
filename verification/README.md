# Verification output

`baseline.json` is the original passing six-run report from the packaged structural snapshot. Run `python3 tools/demo.py verify` to produce a fresh `structural_validation.json` for this checkout and your selected Godot executable.

New reports and captured screenshots in this directory are ignored by Git. The committed evidence images live in `docs/images/`. See `docs/VALIDATION.md` for what the checks cover and what they do not establish.

`handover_validation.json` is the fresh passing six-run report produced in the isolated repository before publication.
