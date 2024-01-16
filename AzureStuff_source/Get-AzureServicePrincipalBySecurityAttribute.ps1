#requires -modules Microsoft.Graph.Beta.Applications
function Get-AzureServicePrincipalBySecurityAttribute {
    <#
    .SYNOPSIS
    Function returns service principals with given security attribute set.

    .DESCRIPTION
    Function returns service principals with given security attribute set.

    .PARAMETER attributeSetName
    Name of the security attribute set.

    .PARAMETER attributeName
    Name of the security attribute.

    .PARAMETER attributeValue
    Value of the security attribute.

    .EXAMPLE
    Get-AzureServicePrincipalBySecurityAttribute -attributeSetName Security -attributeName SecurityLevel -attributeValue 5

    .NOTES
    To be able to read security attributes you need to be member of 'Attribute Assignment Reader' or 'Attribute Assignment Administrator' or have following Graph API permissions. For SP 'CustomSecAttributeAssignment.Read.All' and 'Application.Read.All', for Users 'CustomSecAttributeAssignment.Read.All' and 'User.Read.All'

    https://learn.microsoft.com/en-us/graph/custom-security-attributes-examples?tabs=powershell
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $attributeSetName,

        [Parameter(Mandatory = $true)]
        [string] $attributeName,

        [Parameter(Mandatory = $true)]
        [string[]] $attributeValue
    )

    Write-Warning "To be able to read security attributes you need to be member of 'Attribute Assignment Reader' or 'Attribute Assignment Administrator' or have following Graph API permissions. For SP 'CustomSecAttributeAssignment.Read.All' and 'Application.Read.All', for Users 'CustomSecAttributeAssignment.Read.All' and 'User.Read.All'"

    # beta api is needed to get custom security attributes
    $filter = @()

    $attributeValue | % {
        $filter += "customSecurityAttributes/$attributeSetName/$attributeName eq '$_'"
    }

    $filter = $filter -join " or "

    Get-MgBetaServicePrincipal -All -Filter $filter -Property AppId, Id, AppDisplayName, AccountEnabled, DisplayName, CustomSecurityAttributes -ConsistencyLevel eventual -CountVariable CountVar -ErrorAction Stop
}