function Get-PIMResourceRoleAssignmentSetting {
    <#
        .SYNOPSIS
        Gets PIM assignment settings for a given Azure resource role at a specific scope.

        .DESCRIPTION
        This function retrieves Privileged Identity Management (PIM) policy assignment settings for a specified Azure resource role (such as Reader, Contributor, etc.) at a given scope (subscription, resource group, or resource). You can specify the role by name or ID.

        .PARAMETER roleName
        The name of the Azure resource role to query. Mandatory if using the roleName parameter set.

        .PARAMETER roleId
        The object ID of the Azure resource role to query. Mandatory if using the roleId parameter set.

        .PARAMETER scope
        The Azure scope (subscription, resource group, or resource) to query for the role assignment settings. Mandatory.

        .EXAMPLE
        Get-PIMResourceRoleAssignmentSetting -roleName "Reader" -scope "/subscriptions/xxxx/resourceGroups/yyyy"
        Retrieves PIM assignment settings for the Reader role at the specified resource group scope.

        .EXAMPLE
        Get-PIMResourceRoleAssignmentSetting -roleId "acdd72a7-3385-48ef-bd42-f606fba81ae7" -scope "/subscriptions/xxxx/resourceGroups/yyyy"
        Retrieves PIM assignment settings for the specified role ID at the given scope.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "rolename")]
        [string] $roleName,

        [Parameter(Mandatory = $true, ParameterSetName = "roleId")]
        [guid] $roleId,

        [Parameter(Mandatory = $true)]
        [string] $scope
    )

    (Get-Variable "roleId").Attributes.Clear()

    $scope = $scope.TrimStart('/')

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    $base = "https://management.azure.com"
    $endpoint = "$base/$scope/providers/Microsoft.Authorization"

    if ($roleName) {
        # get ID of the role $roleName assignable at the provided scope
        $restUri = "$endpoint/roleDefinitions?api-version=2022-05-01-preview&`$filter=roleName eq '$roleName'"
        Write-Verbose "Getting role ID for role '$roleName' at scope '$scope' (uri '$restUri')"
        $roleID = ((Invoke-AzRestMethod -Uri $restUri -ErrorAction Stop).content | ConvertFrom-Json).value.id
        if (!$roleID) {
            throw "$($MyInvocation.MyCommand): Role '$roleName' not found at scope '$scope'."
        }
    } else {
        $roleID = "/$scope/providers/Microsoft.Authorization/roleDefinitions/$roleId"
    }

    # get the role assignment for the roleID
    $restUri = "$endpoint/roleManagementPolicyAssignments?api-version=2020-10-01&`$filter=roleDefinitionId eq '$roleID'"
    Write-Verbose "Getting PIM role assignment for role ID '$roleID' at scope '$scope' (uri '$restUri')"
    $policyId = ((Invoke-AzRestMethod -Uri $restUri -ErrorAction Stop).content | ConvertFrom-Json).value.properties.policyId

    # get the role policy for the policyID
    $restUri = "$base/$policyId/?api-version=2020-10-01"
    Write-Verbose "Getting PIM role policy for policy ID '$policyId' (uri '$restUri')"
    ((Invoke-AzRestMethod -Uri $restUri -ErrorAction Stop).content | ConvertFrom-Json).properties
}