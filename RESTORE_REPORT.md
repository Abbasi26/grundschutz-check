# Restore report — grundschutz-check (project name: GrundschutzCheck)

## Mapping
- Cursor transcript: `bc-50cd5d21-839b-5bea-97da-2706221693af.jsonl`
- GitHub empty repo target: `grundschutz-check`
- Project name inside the tree: **GrundschutzCheck** (module/scripts keep that name)

## Method
1. Replayed all `search_replace` edit diffs from the transcript in order (65 edits, 0 parse failures).
2. Regenerated derived artifacts with the project's own builder: `python3 tools/build_catalog.py --write` → `catalog/windows11-client.json` (63 checks) and `demo/evidence.json`.
3. Wrote a clean `SPEC.md` from the original task prompt.
4. No model regeneration was required for source; builder output matches the committed-catalog test.

## Transcript vs generated
| Area | Source |
|------|--------|
| PowerShell module/scripts, `src/**`, `tests/**`, docs, examples, CI | Restored from transcript diffs |
| `catalog/windows11-client.json`, `demo/evidence.json` | Regenerated locally via `tools/build_catalog.py --write` |
| `SPEC.md` | Written at restore time from the task prompt |
| Code written by dual-provider pipeline this run | **None** (not needed) |

## Tests
- Pester: **23 passed**, 0 failed
- `pytest tests/test_catalog.py`: **4 passed**
- `tools/build_catalog.py --check`: ok (63 checks)
- Demo: pass=44 fail=19 error=0 total=63; HTML/MD/JSON/CSV written

## Ready to push
**Yes** (local `main` commit prepared; push left to parent).

## Gaps
- None for v0.1 acceptance. Live Windows collection is intentionally refused on non-Windows (covered by Pester).
- Empty remote `grundschutz-check` still needs the push.
