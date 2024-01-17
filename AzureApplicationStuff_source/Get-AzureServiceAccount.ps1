#requires -modules Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Groups
function Get-AzureServiceAccount {
    <#
    .SYNOPSIS
    Function for getting information about Azure user service account.
    As a hack for storing user manager and description, we use helper ACL group 'ACL_Owner_<svcAccID>'.

    .DESCRIPTION
    Function for getting information about Azure user service account.
    As a hack for storing user manager and description, we use helper ACL group 'ACL_Owner_<svcAccID>'.

    .PARAMETER UPN
    UPN of the service account.
    For exmaple: svc_test@contoso.onmicrosoft.com

    .EXAMPLE
    Get-AzureServiceAccount -UPN svc_test@contoso.onmicrosoft.com
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidatePattern('.+@.+$')]
        [string] $UPN
    )

    $ErrorActionPreference = "Stop"

    $null = Connect-MgGraph -Scopes User.Read.All, Group.Read.All

    # check that such user does exist
    if (!($svcUser = Get-MgUser -Filter "userPrincipalName eq '$UPN'")) {
        Write-Warning "User $UPN doesn't exists"
    }

    $groupName = "ACL_Owner_" + $svcUser.Id

    if (!($svcGroup = Get-MgGroup -Filter "displayName eq '$groupName'")) {
        Write-Warning "Group $groupName doesn't exists. This shouldn't happen!"
    }

    if ($svcGroup) {
        $managedBy = Get-MgGroupMember -GroupId $svcGroup.Id
        if ($managedBy.count -gt 1) { Write-Warning "There is more than one manager. This shouldn't happen!" }
    }

    $object = [PSCustomObject]@{
        userPrincipalName = $UPN
        Description       = $svcGroup.Description
        ManagedByObjectId = $managedBy.Id
        ManagedBy         = $managedBy.AdditionalProperties.displayName
    }

    return $object
}