#requires -modules Microsoft.Graph.Authentication
function Get-AzureGroupSettings {
    <#
    .SYNOPSIS
    Function for getting group settings.
    Official Get-MgGroup -Property Settings doesn't return anything for some reason.

    .DESCRIPTION
    Function for getting group settings.
    Official Get-MgGroup -Property Settings doesn't return anything for some reason.

    .PARAMETER groupId
    Group ID.

    .EXAMPLE
    Get-AzureGroupSettings -groupId 01c19ec3-e1bb-44f3-ab36-86071b745375

    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $groupId
    )

    Invoke-MgGraphRequest -Uri "v1.0/groups/$groupId/settings" -OutputType PSObject | select -exp value | select *, @{n = 'ValuesAsObject'; e = {
            # return settings values as proper hashtable
            $hash = @{}
            $_.Values | % { $hash.($_.name) = $_.value }
            $hash
        }
    } #-ExcludeProperty Values
}