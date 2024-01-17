#requires -modules Microsoft.Graph.Authentication, Microsoft.Graph.Applications, Az.Accounts
function Get-AzureManagedIdentity {
    <#
    .SYNOPSIS
    Function for getting Azure AD Managed Identity(ies).

    .DESCRIPTION
    Function for getting Azure AD Managed Identity(ies).

    .PARAMETER objectId
    (optional) objectID of Managed Identity(ies).

    If not specified, all app registrations will be processed.

    .EXAMPLE
    Get-AzureManagedIdentity

    Get all Managed Identities.

    .EXAMPLE
    Get-AzureManagedIdentity -objectId 1234-1234-1234

    Get selected Managed Identity.
    #>

    [CmdletBinding()]
    param (
        [string[]] $objectId
    )

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): The context is invalid. Please login using Connect-MgGraph."
    }

    $servicePrincipalList = @()

    if (!$objectId) {
        $servicePrincipalList = Get-MgServicePrincipal -Filter "servicePrincipalType eq 'ManagedIdentity'" -All
    } else {
        $objectId | % {
            $servicePrincipalList += Get-MgServicePrincipal -ServicePrincipalId $_
        }
    }

    $azureSubscriptions = Get-AzSubscription

    $servicePrincipalList | % {
        $SPObj = $_

        # output
        $SPObj | select *, @{n = 'SubscriptionId'; e = { $_.alternativeNames | ? { $_ -Match "/subscriptions/([^/]+)/" } | % { ([regex]"/subscriptions/([^/]+)/").Matches($_).captures.groups[1].value } } }, @{name = 'SubscriptionName'; expression = { $alternativeNames = $_.alternativeNames; $azureSubscriptions | ? { $_.Id -eq ($alternativeNames | ? { $_ -Match "/subscriptions/([^/]+)/" } | % { ([regex]"/subscriptions/([^/]+)/").Matches($_).captures.groups[1].value }) } | select -exp Name } }, @{n = 'ResourceGroup'; e = { $_.alternativeNames | ? { $_ -Match "/resourcegroups/([^/]+)/" } | % { ([regex]"/resourcegroups/([^/]+)/").Matches($_).captures.groups[1].value } } },
        @{n = 'Type'; e = { if ($_.alternativeNames -match "/Microsoft.ManagedIdentity/userAssignedIdentities/") { 'UserManagedIdentity' } else { 'SystemManagedIdentity' } } }
    }
}