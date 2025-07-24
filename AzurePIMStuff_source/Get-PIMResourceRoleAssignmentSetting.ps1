function Get-PIMResourceRoleAssignmentSetting {
    <#
    .SYNOPSIS
    Gets PIM assignment settings for a given Azure resource role at a specific scope.

    .DESCRIPTION
    This function retrieves Privileged Identity Management (PIM) policy assignment settings for a specified Azure resource role (such as Reader, Contributor, etc.) at a given scope (subscription, resource group, or resource). You can specify the role by name or ID.

    .PARAMETER rolename
    The name of the Azure resource role to query. Mandatory if using the rolename parameter set.

    .PARAMETER roleId
    The object ID of the Azure resource role to query. Mandatory if using the roleId parameter set.

    .PARAMETER scope
    The Azure scope (subscription, resource group, or resource) to query for the role assignment settings. Mandatory.

    .EXAMPLE
    Get-PIMResourceRoleAssignmentSetting -rolename "Reader" -scope "/subscriptions/xxxx/resourceGroups/yyyy"
    Retrieves PIM assignment settings for the Reader role at the specified resource group scope.

    .EXAMPLE
    Get-PIMResourceRoleAssignmentSetting -roleId "acdd72a7-3385-48ef-bd42-f606fba81ae7" -scope "/subscriptions/xxxx/resourceGroups/yyyy"
    Retrieves PIM assignment settings for the specified role ID at the given scope.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "rolename")]
        [string] $rolename,
        [Parameter(Mandatory = $true, ParameterSetName = "roleId")]
        [string] $roleId,
        [Parameter(Mandatory = $true)]
        [string] $scope
    )

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    $base = "https://management.azure.com"
    $endpoint = "$base/$scope/providers/Microsoft.Authorization"
    # Get ID of the role $rolename assignable at the provided scope
    if ($rolename) {
        $restUri = "$endpoint/roleDefinitions?api-version=2022-04-01&`$filter=roleName eq '$rolename'"
    } else {
        $restUri = "$endpoint/roleDefinitions/$roleId?api-version=2022-04-01"
    }
    $roleID = ((Invoke-AzRestMethod -Uri $restUri -ErrorAction Stop).content | ConvertFrom-Json).value.id
    # get the role assignment for the roleID
    $restUri = "$endpoint/roleManagementPolicyAssignments?api-version=2020-10-01&`$filter=roleDefinitionId eq '$roleID'"
    $policyId = ((Invoke-AzRestMethod -Uri $restUri -ErrorAction Stop).content | ConvertFrom-Json).value.properties.policyId
    # get the role policy for the policyID
    $restUri = "$base/$policyId/?api-version=2020-10-01"
    ((Invoke-AzRestMethod -Uri $restUri -ErrorAction Stop).content | ConvertFrom-Json).properties
}