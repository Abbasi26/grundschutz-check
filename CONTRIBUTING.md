# Contributing

GrundschutzCheck is an open-source, read-only checker. Changes should keep the tool honest about what BSI has and has not published.

## Checks

Edit `tools/build_catalog.py`, then regenerate:

```bash
python3 tools/build_catalog.py --write
python3 tools/build_catalog.py --check
```

Do not invent requirement ids. A new citation needs a sentence you can point at in the Hilfsmittel, the IT-Grundschutz-Kompendium, or the Grundschutz++ resolved catalog. If the link is uncertain, set that reference's `mapping` to `unverified`. Leave `windows11_carryover` as `unverified` until BSI publishes a Windows 11 value for that setting.

Add the id to the allow lists in `tests/Catalog.Tests.ps1` and `tests/test_catalog.py` in the same change. A new id that is not on those lists fails the tests on purpose.

Add a Pester case when you add an evaluator behavior. Tests use mocked evidence. They do not read a live registry.

## Tests

PowerShell tests use Pester 5 and run offline:

```bash
pwsh -NoProfile -Command "Invoke-Pester -CI ./tests"
```

Python tests:

```bash
python3 -m pytest tests/test_catalog.py -q
```

PowerShell files (`.ps1`, `.psm1`, `.psd1`) stay ASCII. German text belongs in JSON, Markdown, or is built from a character code inside PowerShell.

## Scope of a change

v0.1 does not apply settings. A remediation snippet is text. Do not add a write path without an explicit switch and a preview, and do not add one in a drive-by change.

Do not add telemetry or a network call in the module.
