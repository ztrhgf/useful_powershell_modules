function Get-AzureAdGroupMemberRecursive {
    <#
    .SYNOPSIS
    Function for recursive enumeration of all Azure AD group.

    .DESCRIPTION
    Function for recursive enumeration of all Azure AD group.
    Group can be identified via id or name.

    .PARAMETER azureGroupObj
    AzureAD group object.

    .PARAMETER azureGroupName
    AzureAD group name.

    .PARAMETER azureGroupId
    AzureAD group id.

    .PARAMETER includeNestedGroup
    Switch for outputting of nested groups (not just their members).

    .EXAMPLE
    Get-AzureAdGroupMemberRecursive -azureGroupName "IT RBAC"

    .EXAMPLE
    Get-AzureAdGroupMemberRecursive -azureGroupId 123412341234

    .NOTES
    #https://gist.github.com/alexmags/cb69108c65fb38614b6625b4400c98c2
    #>

    [cmdletbinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true, ParameterSetName = "azureGroupObj")]
        $azureGroupObj,

        [Parameter(Mandatory = $true, ParameterSetName = "azureGroupName")]
        [string] $azureGroupName,

        [Parameter(Mandatory = $true, ParameterSetName = "azureGroupId")]
        [string] $azureGroupId,

        [switch] $includeNestedGroup
    )

    Begin {
        Connect-AzureAD2
    }

    Process {
        if ($azureGroupObj) {
            $azureGroupName = $azureGroupObj.DisplayName
            $azureGroupId = $azureGroupObj.ObjectId
        } elseif ($azureGroupName) {
            $azureGroupId = Get-AzureADGroup -SearchString $azureGroupName | select -ExpandProperty ObjectId
        } elseif ($azureGroupId) {
            $azureGroupName = Get-AzureADGroup -ObjectId $azureGroupId | select -ExpandProperty DisplayName
        } else {
            throw "You haven't specified any parameter"
        }

        Write-Verbose -Message "Enumerating $azureGroupName ($azureGroupId)"

        Get-AzureADGroupMember -ObjectId $azureGroupId -All $true | % {
            if ($_.ObjectType -eq 'Group') {
                if ($includeNestedGroup) {
                    $_
                }

                Get-AzureAdGroupMemberRecursive -AzureGroupObj $_
            } else {
                $_
            }
        }
    }
}