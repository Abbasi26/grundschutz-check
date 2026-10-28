# Changelog

## 0.2.0 - 2026-10-28

- `-ExceptionPath`: documented risk acceptances with reason, owner, expiry date, and optional ticket. Failing checks with a current exception are reported as `accepted` and do not set exit code 1. Expired exceptions keep the check at `fail`; exceptions never hide errors. New `accepted` count in the summary and per module.
- `-BaselinePath`: compares the run with an earlier JSON report (newly failing, fixed, still failing, new and removed checks, host fingerprint match). Rendered in HTML and Markdown and stored under `comparison` in the JSON report.
- `-FailOnRegression` on the script: exit 1 only for checks that newly fail against the baseline.
- `examples/exceptions.example.json`, ROADMAP.md with good first issues, issue forms, and a pull request template.

## 0.1.0 - 2026-10-21

- Audit checks query `auditpol /get /subcategory:{GUID} /r` and parse the CSV by column, so German-localized Windows does not return `error` for Logon or Credential Validation. If the GUID query fails, de-DE display names are accepted. Inclusion settings from a German `auditpol` CSV are normalized to English.
- Read-only PowerShell module for Windows PowerShell 5.1 and PowerShell 7.
- Windows 11 client catalog with 63 checks. Values are carried over from the BSI Hilfsmittel for Windows clients 1.0 and marked `windows11_carryover: unverified`.
- Citations use requirement ids read from the IT-Grundschutz-Kompendium Edition 2023 and from Grundschutz++ catalog 2026-09-24. Uncertain links are `mapping: unverified`.
- HTML, Markdown, JSON, and CSV evidence reports. The host name is stored only as a SHA-256 fingerprint.
- `-Demo` renders a report from bundled fictional evidence.
- Example Ansible playbook for remote read-only collection.
- Pester tests and a catalog schema for reuse by other tools.
