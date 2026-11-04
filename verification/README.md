# Verification output

`handover_validation.json` and `handover_wheel_validation.json` record the passing structural and wheel suites run in the isolated published handover. `baseline.json` preserves the older 175-link pre-wheel reference; the current graph has 187 links.

Run `python3 tools/demo.py verify` for fresh `structural_validation.json` and `wheel_validation.json` reports. Use `verify-wheels` for only the wheel suite. Generated reports/screenshots are ignored by Git. Committed evidence images live under `docs/images/`. See `docs/VALIDATION.md` for scope and limitations.
