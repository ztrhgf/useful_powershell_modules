function Get-AzureADAppUsersAndGroups {
    <#
    .SYNOPSIS
    Get users and groups roles of (selected) service principal.

    .DESCRIPTION
    Get users and groups roles of (selected) service principal.

    .PARAMETER objectId
    ObjectId of service principal.

    If not provided all service principals will be processed.

    .EXAMPLE
    Get-AzureADAppUsersAndGroups

    Returns all service principals and their users and groups roles assignments.

    .EXAMPLE
    Get-AzureADAppUsersAndGroups -objectId 123123

    Returns service principal with objectId 123123 and its users and groups roles assignments.

    .NOTES
    https://github.com/MicrosoftDocs/azure-docs/issues/48159
    #>

    [CmdletBinding()]
    [Alias("Get-AzureADServiceAppRoleAssignment2")]
    param (
        [string] $objectId
    )

    Connect-AzureAD2

    $sessionInfo = Get-AzureADCurrentSessionInfo -ea Stop

    $param = @{}
    if ($objectId) {
        Write-Verbose "Get $objectId service principal"
        $param.objectId = $objectId
    } else {
        Write-Verbose "Get all service principals"
        $param.all = $true
    }

    Get-AzureADServicePrincipal @param | % {
        # Build a hash table of the service principal's app roles. The 0-Guid is
        # used in an app role assignment to indicate that the principal is assigned
        # to the default app role (or rather, no app role).
        $appRoles = @{ [Guid]::Empty.ToString() = "(default)" }
        $_.AppRoles | % { $appRoles[$_.Id] = $_.DisplayName }

        # Get the app role assignments for this app, and add a field for the app role name

        if ($sessionInfo.Account.Type -eq 'user') {
            Get-AzureADServiceAppRoleAssignment -ObjectId $_.ObjectId -All:$true | % {
                $_ | Add-Member -Name "AppRoleDisplayName" -Value $appRoles[$_.Id] -MemberType NoteProperty -PassThru
            }
        } else {
            # running under service principal
            # there is super weird bug when under service principal Get-AzureADServiceAppRoleAssignedTo behaves like Get-AzureADServiceAppRoleAssignment and vice versa (https://github.com/Azure/azure-docs-powershell-azuread/issues/766)!!!
            Get-AzureADServiceAppRoleAssignedTo -ObjectId $_.ObjectId -All:$true | % {
                $_ | Add-Member -Name "AppRoleDisplayName" -Value $appRoles[$_.Id] -MemberType NoteProperty -PassThru
            }
        }
    }
}