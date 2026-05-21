# Elastic Queries

These Elasticsearch Query DSL and Kibana KQL detections mirror `detection/kql-queries.md`.

## 01 BloodHound Enumeration

Kibana KQL:

```kuery
event.code: "4662" and winlog.event_data.ObjectServer: "DS" and (winlog.event_data.AccessMask: *0x100* or winlog.event_data.AccessMask: *0x10*) and not winlog.event_data.SubjectUserName: *$
```

Query DSL:

```json
{"query":{"bool":{"must":[{"term":{"event.code":"4662"}},{"term":{"winlog.event_data.ObjectServer":"DS"}},{"query_string":{"query":"winlog.event_data.AccessMask:(*0x100* OR *0x10*)"}}],"must_not":[{"wildcard":{"winlog.event_data.SubjectUserName":"*$"}}]}}}
```

## 02 Kerberoasting

Kibana KQL:

```kuery
event.code: "4769" and winlog.event_data.TicketEncryptionType: "0x17" and not winlog.event_data.ServiceName: (*$ or "krbtgt") and not winlog.event_data.TargetUserName: *$
```

Query DSL:

```json
{"query":{"bool":{"must":[{"term":{"event.code":"4769"}},{"term":{"winlog.event_data.TicketEncryptionType":"0x17"}}],"must_not":[{"wildcard":{"winlog.event_data.ServiceName":"*$"}},{"term":{"winlog.event_data.ServiceName":"krbtgt"}},{"wildcard":{"winlog.event_data.TargetUserName":"*$"}}]}}}
```

## 03 AS-REP Roasting

Kibana KQL:

```kuery
event.code: "4768" and winlog.event_data.PreAuthType: "0" and winlog.event_data.TicketEncryptionType: ("0x17" or "0x18") and not winlog.event_data.TargetUserName: *$
```

Query DSL:

```json
{"query":{"bool":{"must":[{"term":{"event.code":"4768"}},{"term":{"winlog.event_data.PreAuthType":"0"}},{"terms":{"winlog.event_data.TicketEncryptionType":["0x17","0x18"]}}],"must_not":[{"wildcard":{"winlog.event_data.TargetUserName":"*$"}}]}}}
```

## 04 NTLM Relay

Kibana KQL:

```kuery
event.code: "4624" and winlog.event_data.LogonType: "3" and winlog.event_data.AuthenticationPackageName: "NTLM" and not winlog.event_data.TargetUserName: (*$ or "ANONYMOUS LOGON" or "SYSTEM" or "LOCAL SERVICE" or "NETWORK SERVICE")
```

Query DSL:

```json
{"query":{"bool":{"must":[{"term":{"event.code":"4624"}},{"term":{"winlog.event_data.LogonType":"3"}},{"term":{"winlog.event_data.AuthenticationPackageName":"NTLM"}}],"must_not":[{"wildcard":{"winlog.event_data.TargetUserName":"*$"}},{"terms":{"winlog.event_data.TargetUserName":["ANONYMOUS LOGON","SYSTEM","LOCAL SERVICE","NETWORK SERVICE"]}}]}}}
```

## 05 Pass-the-Hash

Kibana KQL:

```kuery
event.code: "4624" and winlog.event_data.LogonType: ("3" or "9") and winlog.event_data.AuthenticationPackageName: "NTLM" and winlog.event_data.LogonProcessName: (*NtLmSsp* or *seclogo*) and not winlog.event_data.TargetUserName: (*$ or "ANONYMOUS LOGON" or "SYSTEM" or "LOCAL SERVICE" or "NETWORK SERVICE")
```

Query DSL:

```json
{"query":{"bool":{"must":[{"term":{"event.code":"4624"}},{"terms":{"winlog.event_data.LogonType":["3","9"]}},{"term":{"winlog.event_data.AuthenticationPackageName":"NTLM"}},{"query_string":{"query":"winlog.event_data.LogonProcessName:(*NtLmSsp* OR *seclogo*)"}}],"must_not":[{"wildcard":{"winlog.event_data.TargetUserName":"*$"}},{"terms":{"winlog.event_data.TargetUserName":["ANONYMOUS LOGON","SYSTEM","LOCAL SERVICE","NETWORK SERVICE"]}}]}}}
```

## 06 DCSync

Kibana KQL:

```kuery
event.code: "4662" and winlog.event_data.Properties: (*1131f6aa-9c07-11d1-f79f-00c04fc2dcd2* or *1131f6ad-9c07-11d1-f79f-00c04fc2dcd2*) and not winlog.event_data.SubjectUserName: (*$ or MSOL_* or AAD_*)
```

Query DSL:

```json
{"query":{"bool":{"must":[{"term":{"event.code":"4662"}},{"query_string":{"query":"winlog.event_data.Properties:(*1131f6aa-9c07-11d1-f79f-00c04fc2dcd2* OR *1131f6ad-9c07-11d1-f79f-00c04fc2dcd2*)"}}],"must_not":[{"wildcard":{"winlog.event_data.SubjectUserName":"*$"}},{"wildcard":{"winlog.event_data.SubjectUserName":"MSOL_*"}},{"wildcard":{"winlog.event_data.SubjectUserName":"AAD_*"}}]}}}
```

## 07 Golden Ticket

Kibana KQL:

```kuery
event.code: "4769" and not winlog.event_data.ServiceName: "krbtgt" and not winlog.event_data.TargetUserName: *$ and (winlog.event_data.ServiceName: (*cifs* or *ldap* or *host*) or winlog.event_data.TicketEncryptionType: "0x17")
```

Query DSL:

```json
{"query":{"bool":{"must":[{"term":{"event.code":"4769"}},{"bool":{"should":[{"wildcard":{"winlog.event_data.ServiceName":"*cifs*"}},{"wildcard":{"winlog.event_data.ServiceName":"*ldap*"}},{"wildcard":{"winlog.event_data.ServiceName":"*host*"}},{"term":{"winlog.event_data.TicketEncryptionType":"0x17"}}],"minimum_should_match":1}}],"must_not":[{"term":{"winlog.event_data.ServiceName":"krbtgt"}},{"wildcard":{"winlog.event_data.TargetUserName":"*$"}}]}}}
```

## 08 Silver Ticket

Kibana KQL:

```kuery
event.code: "4624" and winlog.event_data.LogonType: "3" and winlog.event_data.AuthenticationPackageName: "Kerberos" and not winlog.event_data.TargetUserName: (*$ or "ANONYMOUS LOGON" or "SYSTEM" or "LOCAL SERVICE" or "NETWORK SERVICE")
```

Query DSL:

```json
{"query":{"bool":{"must":[{"term":{"event.code":"4624"}},{"term":{"winlog.event_data.LogonType":"3"}},{"term":{"winlog.event_data.AuthenticationPackageName":"Kerberos"}}],"must_not":[{"wildcard":{"winlog.event_data.TargetUserName":"*$"}},{"terms":{"winlog.event_data.TargetUserName":["ANONYMOUS LOGON","SYSTEM","LOCAL SERVICE","NETWORK SERVICE"]}}]}}}
```

## 09 Unconstrained Delegation Abuse

Kibana KQL:

```kuery
event.code: "4624" and winlog.event_data.LogonType: "3" and winlog.event_data.AuthenticationPackageName: "Kerberos" and winlog.event_data.TargetUserName: *$ and host.name: (*castelblack* or *meereen* or *WEB01* or *APP01*)
```

Query DSL:

```json
{"query":{"bool":{"must":[{"term":{"event.code":"4624"}},{"term":{"winlog.event_data.LogonType":"3"}},{"term":{"winlog.event_data.AuthenticationPackageName":"Kerberos"}},{"wildcard":{"winlog.event_data.TargetUserName":"*$"}},{"query_string":{"query":"host.name:(*castelblack* OR *meereen* OR *WEB01* OR *APP01*)"}}]}}}
```

## 10 Cross-Forest Trust Abuse

Kibana KQL:

```kuery
event.code: ("4768" or "4769" or "4624") and winlog.event_data.TargetDomainName: ("NORTH" or "SEVENKINGDOMS" or "north.sevenkingdoms.local" or "sevenkingdoms.local") and (winlog.event_data.ServiceName: (*krbtgt* or *cifs* or *ldap* or *host*) or winlog.event_data.TicketEncryptionType: "0x17")
```

Query DSL:

```json
{"query":{"bool":{"must":[{"terms":{"event.code":["4768","4769","4624"]}},{"terms":{"winlog.event_data.TargetDomainName":["NORTH","SEVENKINGDOMS","north.sevenkingdoms.local","sevenkingdoms.local"]}},{"bool":{"should":[{"wildcard":{"winlog.event_data.ServiceName":"*krbtgt*"}},{"wildcard":{"winlog.event_data.ServiceName":"*cifs*"}},{"wildcard":{"winlog.event_data.ServiceName":"*ldap*"}},{"wildcard":{"winlog.event_data.ServiceName":"*host*"}},{"term":{"winlog.event_data.TicketEncryptionType":"0x17"}}],"minimum_should_match":1}}]}}}
```
