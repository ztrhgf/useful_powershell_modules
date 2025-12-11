function Get-PIMManagementGroupEligibleAssignment {
    <#
    .SYNOPSIS
    Function returns all PIM eligible IAM assignments on selected (all) Azure Management group(s).

    .DESCRIPTION
    Function returns all PIM eligible IAM assignments on selected (all) Azure Management group(s).

    .PARAMETER name
    Name of the Azure Management Group(s) to process.

    .PARAMETER skipAssignmentSettings
    If specified, the function will not retrieve assignment settings for the roles. This can speed up the function if you don't need the detailed settings.

    .EXAMPLE
    Get-PIMManagementGroupEligibleAssignment

    Returns all PIM eligible IAM assignments over all Azure Management Groups.

    .EXAMPLE
    Get-PIMManagementGroupEligibleAssignment -Name IT_test

    Returns all PIM eligible IAM assignments over selected Azure Management Group.
    #>

    [CmdletBinding()]
    param (
        [string[]] $name,

        [switch] $skipAssignmentSettings
    )

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    if ($name) {
        $managementGroupNameList = $name
    } else {
        #TIP KQL instead of Get-AzManagementGroup to avoid error: ... does not have authorization to perform action 'Microsoft.Management/register/action' over scope ...
        $managementGroupNameList = Search-AzGraph2 -query "ResourceContainers
| where type =~ 'microsoft.management/managementgroups'
| project name" | Select-Object -ExpandProperty Name
    }

    New-AzureBatchRequest -url "https://management.azure.com/providers/Microsoft.Management/managementGroups/<placeholder>/providers/Microsoft.Authorization/roleEligibilitySchedules?api-version=2020-10-01&`$filter=atScope()" -placeholder $managementGroupNameList | Invoke-AzureBatchRequest | Expand-ObjectProperty -propertyName Properties | Expand-ObjectProperty -propertyName ExpandedProperties | ? memberType -EQ 'Direct' | % {
        if ($skipAssignmentSettings) {
            $assignmentSetting = $null
        } else {
            $roleId = ($_.roleDefinitionId -split "/")[-1]
            $assignmentSetting = Get-PIMResourceRoleAssignmentSetting -roleId $roleId -scope $_.Scope.Id
        }

        $_ | select *, @{n = 'Policy'; e = { $assignmentSetting } }
    }
}