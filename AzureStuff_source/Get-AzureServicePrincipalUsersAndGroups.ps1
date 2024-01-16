function Get-AzureServicePrincipalUsersAndGroups {
    <#
    .SYNOPSIS
    Get users and groups roles of (selected) service principal.

    .DESCRIPTION
    Get users and groups roles of (selected) service principal.

    .PARAMETER objectId
    ObjectId of service principal.

    If not provided all service principals will be processed.

    .EXAMPLE
    Get-AzureServicePrincipalUsersAndGroups

    Returns all service principals and their users and groups roles assignments.

    .EXAMPLE
    Get-AzureServicePrincipalUsersAndGroups -objectId 123123

    Returns service principal with objectId 123123 and its users and groups roles assignments.

    .NOTES
    https://github.com/MicrosoftDocs/azure-docs/issues/48159
    #>

    [CmdletBinding()]
    param (
        [string] $objectId
    )

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): The context is invalid. Please login using Connect-MgGraph."
    }

    $param = @{}
    if ($objectId) {
        Write-Verbose "Get $objectId service principal"
        $param.ServicePrincipalId = $objectId
    } else {
        Write-Verbose "Get all service principals"
        $param.all = $true
    }

    Get-MgServicePrincipal @param | % {
        # Build a hash table of the service principal's app roles. The 0-Guid is
        # used in an app role assignment to indicate that the principal is assigned
        # to the default app role (or rather, no app role).
        $appRoles = @{ [Guid]::Empty.ToString() = "(default)" }
        $_.AppRoles | % { $appRoles[$_.Id] = $_.DisplayName }

        Get-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $_.Id -All | % {
            $_ | Add-Member -Name "AppRoleDisplayName" -Value $appRoles[$_.AppRoleId] -MemberType NoteProperty -PassThru
        }
    }
}