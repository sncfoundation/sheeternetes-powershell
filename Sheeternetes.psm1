#Requires -Version 5.1
<#
.SYNOPSIS
    Sheeternetes PowerShell module — a tiny declarative client for the
    Sheeternetes apiserver (a Google Apps Script web app backed by a Sheet).

.DESCRIPTION
    Talks to the apiserver over HTTP with Invoke-RestMethod. Configuration is
    read from environment variables:

        $env:WEBAPP_URL   the Apps Script /exec URL
        $env:TOKEN        the shared secret (default: CHANGE_ME_super_secret)

    Cmdlets:
        Get-SheetPod
        Get-SheetNode
        Get-SheetDeployment
        Set-SheetScale        -Name -Replicas
        Remove-SheetDeployment -Name
        Invoke-SheetApply     -Path <manifest.json>

    The Sheet stays the source of truth; these cmdlets just read and mutate it.
#>

function Get-SheetConfig {
    <#
    .SYNOPSIS
        Resolves the apiserver URL and token from the environment.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $url = $env:WEBAPP_URL
    if ([string]::IsNullOrWhiteSpace($url)) {
        throw "WEBAPP_URL is not set. Set `$env:WEBAPP_URL to the Apps Script /exec URL."
    }

    $token = $env:TOKEN
    if ([string]::IsNullOrWhiteSpace($token)) {
        $token = 'CHANGE_ME_super_secret'
    }

    return @{ Url = $url; Token = $token }
}

function Invoke-SheetGet {
    <#
    .SYNOPSIS
        Low-level GET against the apiserver for a given kind.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('pods', 'nodes', 'deployments', 'events')]
        [string] $Kind
    )

    $cfg = Get-SheetConfig
    $uri = '{0}?token={1}&kind={2}' -f $cfg.Url,
        [uri]::EscapeDataString($cfg.Token),
        [uri]::EscapeDataString($Kind)

    Write-Verbose "GET $uri"
    $resp = Invoke-RestMethod -Method Get -Uri $uri -TimeoutSec 30

    if ($null -eq $resp) { return @() }
    if ($resp.PSObject.Properties.Name -contains 'items') {
        # Return the items, never $null, so the pipeline stays clean.
        return @($resp.items)
    }
    return @($resp)
}

function Invoke-SheetPost {
    <#
    .SYNOPSIS
        Low-level POST of an action payload to the apiserver.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Body
    )

    $cfg = Get-SheetConfig
    $Body['token'] = $cfg.Token
    $json = $Body | ConvertTo-Json -Depth 10 -Compress

    Write-Verbose "POST $($cfg.Url) $json"
    return Invoke-RestMethod -Method Post -Uri $cfg.Url `
        -ContentType 'application/json' -Body $json -TimeoutSec 30
}

function Get-SheetPod {
    <#
    .SYNOPSIS
        Lists pods scheduled on the cluster.
    .EXAMPLE
        Get-SheetPod | Where-Object phase -ne 'Running'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    Invoke-SheetGet -Kind pods | ForEach-Object {
        [pscustomobject]@{
            PSTypeName   = 'Sheeternetes.Pod'
            Name         = $_.name
            Deployment   = $_.deployment
            Node         = $_.node
            Phase        = $_.phase
            ContainerId  = $_.container_id
        }
    }
}

function Get-SheetNode {
    <#
    .SYNOPSIS
        Lists nodes (kubelets) registered in the Sheet.
    .EXAMPLE
        Get-SheetNode | Sort-Object CpuUsed -Descending
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    Invoke-SheetGet -Kind nodes | ForEach-Object {
        [pscustomobject]@{
            PSTypeName    = 'Sheeternetes.Node'
            Name          = $_.name
            Ip            = $_.ip
            CpuTotal      = $_.cpu_total
            CpuUsed       = $_.cpu_used
            MemTotal      = $_.mem_total
            Status        = $_.status
            LastHeartbeat = $_.last_heartbeat
        }
    }
}

function Get-SheetDeployment {
    <#
    .SYNOPSIS
        Lists deployments declared in the Sheet.
    .EXAMPLE
        Get-SheetDeployment | Format-Table Name, Image, Replicas
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    Invoke-SheetGet -Kind deployments | ForEach-Object {
        [pscustomobject]@{
            PSTypeName = 'Sheeternetes.Deployment'
            Name       = $_.name
            Image      = $_.image
            Replicas   = $_.replicas
            CpuReq     = $_.cpu_req
            MemReq     = $_.mem_req
        }
    }
}

function Set-SheetScale {
    <#
    .SYNOPSIS
        Scales a deployment to the requested number of replicas.
    .PARAMETER Name
        The deployment name. Accepts pipeline input by property name, so you can
        pipe a deployment object straight in.
    .PARAMETER Replicas
        Desired replica count.
    .EXAMPLE
        Set-SheetScale -Name hello-web -Replicas 3
    .EXAMPLE
        Get-SheetDeployment | Where-Object Name -eq hello-web | Set-SheetScale -Replicas 0
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateRange(0, [int]::MaxValue)]
        [int] $Replicas
    )

    process {
        if ($PSCmdlet.ShouldProcess($Name, "Scale to $Replicas replica(s)")) {
            Invoke-SheetPost -Body @{
                action   = 'scale'
                name     = $Name
                replicas = $Replicas
            }
        }
    }
}

function Remove-SheetDeployment {
    <#
    .SYNOPSIS
        Deletes a deployment from the Sheet.
    .PARAMETER Name
        The deployment name. Accepts pipeline input by property name.
    .EXAMPLE
        Remove-SheetDeployment -Name hello-web
    .EXAMPLE
        Get-SheetDeployment | Where-Object Name -like 'demo-*' | Remove-SheetDeployment
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    process {
        if ($PSCmdlet.ShouldProcess($Name, 'Delete deployment')) {
            Invoke-SheetPost -Body @{
                action = 'delete'
                name   = $Name
            }
        }
    }
}

function Invoke-SheetApply {
    <#
    .SYNOPSIS
        Applies a manifest of deployments declared in a JSON file.
    .DESCRIPTION
        The manifest is a JSON document with a top-level "deployments" array,
        e.g. { "deployments": [ { "name": "hello-web", "image": "nginx", ... } ] }.
        Each deployment object is passed through to the apiserver unchanged.
    .PARAMETER Path
        Path to the manifest JSON file.
    .EXAMPLE
        Invoke-SheetApply -Path ./lab/hello-web.json
    .EXAMPLE
        Get-ChildItem *.json | Invoke-SheetApply
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName', 'PSPath')]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    process {
        $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
        $spec = Get-Content -LiteralPath $resolved -Raw | ConvertFrom-Json

        if ($null -eq $spec.PSObject.Properties['deployments']) {
            throw "Manifest '$resolved' has no top-level 'deployments' array."
        }

        # Normalize to an array of plain objects for the payload.
        $deployments = @($spec.deployments)

        if ($PSCmdlet.ShouldProcess($resolved, "Apply $($deployments.Count) deployment(s)")) {
            Invoke-SheetPost -Body @{
                action      = 'apply'
                deployments = $deployments
            }
        }
    }
}

Export-ModuleMember -Function @(
    'Get-SheetPod',
    'Get-SheetNode',
    'Get-SheetDeployment',
    'Set-SheetScale',
    'Remove-SheetDeployment',
    'Invoke-SheetApply'
)
