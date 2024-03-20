#requires -modules Microsoft.Graph.Authentication
function Remove-IntuneRemediation {
    <#
    .SYNOPSIS
    Function for removing the remediation.

    .DESCRIPTION
    Function for removing the remediation.

    .PARAMETER remediationScriptId
    ID of the remediation to remove.

    .EXAMPLE
    Remove-IntuneRemediation -remediationScriptId c8f5f560-c55c-4d34-89e0-325000536b41

    Removes the remediation with specified ID.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [guid] $remediationScriptId
    )

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-MgGraph."
    }

    Write-Verbose "Removing remediation script '$remediationScriptId'"
    Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts/$remediationScriptId" -Method DELETE
}