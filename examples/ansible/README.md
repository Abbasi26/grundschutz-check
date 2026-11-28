# Remote collection

This playbook copies GrundschutzCheck to a Windows host with `ansible.windows`, runs the read-only check, and fetches `grundschutzcheck-report.json`. It does not use `-Demo`. It does not apply remediation.

The inventory example uses the documentation address `192.0.2.10` and the name `demo-win11-01.example`. Replace both. Pass the WinRM password with `--extra-vars` or an untracked file.

The account needs permission to read HKLM and to run `secedit /export` and `auditpol /get`. That is normally a local administrator. The playbook is still read-only: the check does not change settings.

```bash
ansible-playbook -i inventory.example.ini collect-grundschutzcheck.yml
```

Exit code 1 from the check means at least one finding. The playbook treats that as a successful collection. Exit code 2 means a check could not be evaluated, and the play fails.

Fetched files land in `collected/`, which is gitignored.

## Monthly baseline comparison

Use the fetched JSON report as the baseline for the next monthly run:

1. After a successful collection, move `collected/grundschutzcheck-report.json`
   to protected, access-controlled storage outside the repository. Keep the
   month in the filename, for example `baselines/2026-11.json`. The report
   contains host-related data, including the host fingerprint and check
   results; do not publish it or commit it to the repository.
2. Before the next run, make that JSON file available to the Windows host in a
   protected directory. Add the following arguments to the playbook's
   read-only check command (or pass the equivalent arguments in your managed
   Ansible task):

   ```text
   -BaselinePath "C:\ProgramData\GrundschutzCheck\baseline\2026-11.json" -FailOnRegression
   ```

3. Fetch the new JSON report and retain it as the next month's baseline after
   reviewing the result.

With `-FailOnRegression`, exit code 1 means that at least one check is newly
failing compared with the baseline. Existing failures do not cause exit code
1 again, so the monthly job can focus on regressions. Exit code 2 still means
that a check could not be evaluated and must be handled as an evaluation
error. Exit code 0 means there was no new failure.
