# Remote collection

This playbook copies GrundschutzCheck to a Windows host with `ansible.windows`, runs the read-only check, and fetches `grundschutzcheck-report.json`. It does not use `-Demo`. It does not apply remediation.

The inventory example uses the documentation address `192.0.2.10` and the name `demo-win11-01.example`. Replace both. Pass the WinRM password with `--extra-vars` or an untracked file.

The account needs permission to read HKLM and to run `secedit /export` and `auditpol /get`. That is normally a local administrator. The playbook is still read-only: the check does not change settings.

```bash
ansible-playbook -i inventory.example.ini collect-grundschutzcheck.yml
```

Exit code 1 from the check means at least one finding. The playbook treats that as a successful collection. Exit code 2 means a check could not be evaluated, and the play fails.

Fetched files land in `collected/`, which is gitignored.
