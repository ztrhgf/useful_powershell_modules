function Get-AzureDirectoryObjectMemberOf {
    <#
    .SYNOPSIS
    Get permanent membership of given Azure account transitively.

    .DESCRIPTION
    Get permanent membership of given Azure account transitively.

    .PARAMETER id
    Id(s) of the Azure accounts you want membership for.

    .PARAMETER securityEnabledOnly
    Switch to return only security enabled groups.

    .EXAMPLE
    Get-AzureDirectoryObjectMemberOf -id 90daa3a7-7fed-4fa7-b979-db74bcd7cbd1

    Get membership of given Azure account.

    .NOTES
    https://learn.microsoft.com/en-us/graph/api/directoryobject-getmembergroups?view=graph-rest-1.0&tabs=http
    #>

    [CmdletBinding()]
    [Alias("Get-AzureAccountMemberOf", "Get-AzureAccountPermanentMemberOf")]
    param (
        [Parameter(Mandatory = $true)]
        [guid[]] $id,

        [switch] $securityEnabledOnly
    )

    $body = @{
        securityEnabledOnly = $securityEnabledOnly.ToBool()
    }

    $header = @{'Content-Type' = "application/json" }

    New-GraphBatchRequest -url "/directoryObjects/<placeholder>/getMemberGroups" -body $body -header $header -method POST -placeholder $id -placeholderAsId | Invoke-GraphBatchRequest -graphVersion beta | % {
        [PSCustomObject]@{
            Id       = $_.RequestId
            MemberOf = (Get-AzureDirectoryObject -id $_.Value)
        }
    }
}