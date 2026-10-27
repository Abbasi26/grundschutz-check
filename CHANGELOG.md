# Changelog

## 0.1.0 - 2026-10-21

- Audit checks query `auditpol /get /subcategory:{GUID} /r` and parse the CSV by column, so German-localized Windows does not return `error` for Logon or Credential Validation. If the GUID query fails, de-DE display names are accepted. Inclusion settings from a German `auditpol` CSV are normalized to English.
- Read-only PowerShell module for Windows PowerShell 5.1 and PowerShell 7.
- Windows 11 client catalog with 63 checks. Values are carried over from the BSI Hilfsmittel for Windows clients 1.0 and marked `windows11_carryover: unverified`.
- Citations use requirement ids read from the IT-Grundschutz-Kompendium Edition 2023 and from Grundschutz++ catalog 2026-09-24. Uncertain links are `mapping: unverified`.
- HTML, Markdown, JSON, and CSV evidence reports. The host name is stored only as a SHA-256 fingerprint.
- `-Demo` renders a report from bundled fictional evidence.
- Example Ansible playbook for remote read-only collection.
- Pester tests and a catalog schema for reuse by other tools.
