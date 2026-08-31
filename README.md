<p align="center">
  <img src="https://sncfoundation.github.io/logos/powershell.svg" width="96" alt="PowerShell IaC logo">
</p>

<h1 align="center">PowerShell IaC</h1>

<p align="center"><b>Declarative cmdlets / DSC for the cluster</b><br>
A <a href="https://sncfoundation.github.io">Sheet-Native Computing Foundation</a> project &#183; analog of <b>PowerShell DSC</b></p>

---

**Status:** 📝 Unsaved Draft &#183; this project is a proposal. Design notes and contributions are welcome.

## About

Declarative cmdlets / DSC for the cluster Part of the spreadsheet-native stack — the Sheet stays the source of truth, and it reconciles.

## Usage

`Sheeternetes.psm1` is a PowerShell client for the Sheeternetes apiserver (the
Apps Script web app). It reads its configuration from two environment variables:

```powershell
$env:WEBAPP_URL = 'https://script.google.com/macros/s/XXXX/exec'
$env:TOKEN      = 'CHANGE_ME_super_secret'   # optional; this is the default

Import-Module ./Sheeternetes.psm1 -Force
Get-Command -Module Sheeternetes
```

Cmdlets:

```powershell
Get-SheetPod                                  # list pods
Get-SheetNode                                 # list nodes (kubelets)
Get-SheetDeployment                           # list deployments

Invoke-SheetApply -Path ./lab/hello-web.json  # apply a manifest ({ "deployments": [...] })
Set-SheetScale -Name whoami -Replicas 3       # scale a deployment
Remove-SheetDeployment -Name whoami           # delete a deployment
```

Output is plain objects, so the pipeline works as you'd expect:

```powershell
# Nodes sorted by CPU in use
Get-SheetNode | Sort-Object CpuUsed -Descending | Format-Table Name, Ip, CpuUsed, Status

# Scale down everything that looks like a demo
Get-SheetDeployment | Where-Object Name -like 'demo-*' | Set-SheetScale -Replicas 0

# Apply every manifest in a folder
Get-ChildItem ./lab/*.json | Invoke-SheetApply
```

The mutating cmdlets (`Set-SheetScale`, `Remove-SheetDeployment`,
`Invoke-SheetApply`) support `-WhatIf` and `-Confirm`.

## Get involved

- 📋 Tracking issue &amp; design: [sncfoundation/sheeternetes#27](https://github.com/sncfoundation/sheeternetes/issues/27)
- 🗺️ [SNCF Landscape](https://sncfoundation.github.io/landscape.html)
- 🧩 [All projects](https://sncfoundation.github.io/projects.html)
- ⚖️ [Governance &amp; how to contribute](https://github.com/sncfoundation/governance)
- 🎓 [Get certified (CSFE)](https://sncfoundation.github.io/certification.html)

## Status legend

Everything starts as an **Unsaved Draft**. It reconciles up the tiers from there — see the
[maturity model](https://sncfoundation.github.io/foundation.html#maturity).

---

<sub>Licensed under Apache-2.0. The SNCF does not recommend running production on a spreadsheet. If you do, please film it.</sub>
