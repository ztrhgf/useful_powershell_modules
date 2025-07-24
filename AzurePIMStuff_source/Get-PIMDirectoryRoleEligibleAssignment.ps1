function Get-PIMDirectoryRoleEligibleAssignment {
    <#
    .SYNOPSIS
    Function returns Azure Directory role eligible assignments.

    .DESCRIPTION
    Function returns Azure Directory role eligible assignments.

    .PARAMETER skipAssignmentSettings
    If specified, the function will not retrieve assignment settings for the roles. This can speed up the function if you don't need the detailed settings.

    .EXAMPLE
    Get-PIMDirectoryRoleEligibleAssignment
    #>

    [CmdletBinding()]
    param (
        [switch] $skipAssignmentSettings
    )

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-MgGraph."
    }

    Invoke-MgGraphRequest -Uri "v1.0/roleManagement/directory/roleEligibilityScheduleInstances?`$expand=roleDefinition,principal" | Get-MgGraphAllPages | % {
        if ($skipAssignmentSettings) {
            $_ | select *, @{n = 'PrincipalName'; e = { $_.principal.displayName } }, @{n = 'RoleName'; e = { $_.roleDefinition.displayName } }
        } else {
            $rules = Get-PIMDirectoryRoleAssignmentSetting -roleId $_.roleDefinitionId

            $_ | select *, @{n = 'PrincipalName'; e = { $_.principal.displayName } }, @{n = 'RoleName'; e = { $_.roleDefinition.displayName } }, @{n = 'Policy'; e = { $rules } }
        }
    }
}