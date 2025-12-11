function Get-PIMMyActiveResourceRole {
    <#
    .SYNOPSIS
    Function returns all active tenant wide (PIM and permanent) resource roles assignments for the current user.

    .DESCRIPTION
    Function returns all active tenant wide (PIM and permanent) resource roles assignments for the current user.
    Role assignments via membership in groups are also included.

    .EXAMPLE
    Get-PIMMyActiveResourceRole
    Returns all active tenant wide (PIM and permanent) resource roles assignments for the current user.
    #>

    [CmdletBinding()]
    param ()

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    # get tenant wide resource active eligible roles for the current user
    $url = "https://management.azure.com///providers/Microsoft.Authorization/roleAssignmentSchedules?`$filter=asTarget()&api-version=2020-10-01-preview"

    Invoke-AzRestMethod -Method Get -Uri $url | Select-Object -ExpandProperty Content | ConvertFrom-Json | Select-Object -ExpandProperty value | Expand-ObjectProperty -propertyName Properties | Select-Object *, @{Name = 'ScopeType'; Expression = { $_.expandedProperties.scope.type } }, @{Name = 'ScopeName'; Expression = { $_.expandedProperties.scope.displayName } }, @{Name = 'principalDisplayName'; Expression = { $_.expandedProperties.principal.displayName } }, @{Name = 'principalUPN'; Expression = { $_.expandedProperties.principal.userPrincipalName } }, @{Name = 'roleName'; Expression = { $_.expandedProperties.roleDefinition.displayName } }
}