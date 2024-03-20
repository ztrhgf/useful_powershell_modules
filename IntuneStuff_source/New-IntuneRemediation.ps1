#requires -modules Microsoft.Graph.Authentication
function New-IntuneRemediation {
    <#
    .SYNOPSIS
    Function creates Intune remediation.

    .DESCRIPTION
    Function creates Intune remediation.

    .PARAMETER displayName
    Remediation name.

    .PARAMETER description
    Remediation description.

    .PARAMETER publisher
    Remediation publisher.

    .PARAMETER runAs
    What account to use to run the remediation, SYSTEM or USER.

    By default SYSTEM.

    .PARAMETER runAs32
    False to run in 64 bit PowerShell.

    By default false.

    .PARAMETER detectScript
    Text of the command that should be used for detection.

    .PARAMETER remediateScript
    Text of the command that should be used for remediation.

    .EXAMPLE
    $detectScript = @'
        if (test-path "C:\temp") {
            exit 0
        } else {
            exit 1
        }
    '@

    $remediateScript = @'
        mkdir C:\temp
    '@

    $param = @{
        displayName     = "TEMP folder create"
        description     = "on demand remediation script"
        detectScript    = $detectScript
        remediateScript = $remediateScript
        publisher       = "on-demand"
    }

    $remediationScript = New-IntuneRemediation @param
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $displayName,

        [string] $description = "Created by New-IntuneRemediation",

        [string] $publisher = "New-IntuneRemediation",

        [ValidateSet('system', 'user')]
        [string] $runAs = "system",

        [boolean] $runAs32 = $false,

        [Parameter(Mandatory = $true)]
        [string] $detectScript,

        [Parameter(Mandatory = $true)]
        [string] $remediateScript
    )

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-MgGraph."
    }

    $body = @{
        "@odata.type"              = "#microsoft.graph.deviceHealthScript"
        "publisher"                = $publisher
        "version"                  = "1.0"
        "displayName"              = $displayName
        "description"              = $description
        "detectionScriptContent"   = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($detectScript))
        "remediationScriptContent" = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($remediateScript))
        "runAsAccount"             = $runAs
        "runAs32Bit"               = $runAs32
    }

    Write-Verbose "Creating the remediation '$displayName'"
    Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts" -Method POST -Body ($body | ConvertTo-Json)
}