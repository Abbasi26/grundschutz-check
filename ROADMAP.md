# Roadmap

GrundschutzCheck stays read-only. Nothing here changes a client.

## 0.2 (in progress)

- [x] Documented exceptions with owner and expiry (`-ExceptionPath`)
- [x] Baseline comparison and a regression-only exit code (`-BaselinePath`, `-FailOnRegression`)
- [ ] OSCAL Assessment Results export of the JSON report
- [ ] German report language (`-Language de`)

## Later

- A full SiSyPHuS AP10 audit-subcategory matrix with a citation for each row
- Windows Server profiles
- Intune policy-assignment evaluation (read-only)
- A preview-only switch that shows what remediation would change

## Good first issues

| Idea | Where to start | Test |
| --- | --- | --- |
| Warn in the report when an exception expires within 30 days | `src/Exceptions.ps1` | new case in `tests/ExceptionsBaseline.Tests.ps1` |
| Add an `accepted` column to the per-module tables in HTML and Markdown | `src/Report.ps1` | assert the column in `tests/Report.Tests.ps1` |
| Accept a CSV exception file (`check_id,reason,owner,expires,ticket`) | `Read-GsExceptionFile` | same assertions as the JSON tests |
| `-FailOnSeverity high` to ignore low and medium failures for the exit code | `Invoke-GrundschutzCheck.ps1` | exit-code test with the demo |
| Translate the Markdown report headings to German behind a switch | `ConvertTo-GsMarkdownReport` | snapshot of headings |
| Document a monthly baseline workflow with the Ansible example | `examples/ansible/` | review only |

Please do not invent requirement ids. New checks start in `tools/build_catalog.py`; see [CONTRIBUTING.md](CONTRIBUTING.md).
