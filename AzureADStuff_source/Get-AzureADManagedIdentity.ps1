function Get-AzureADManagedIdentity {
    <#
    .SYNOPSIS
    Function for getting Azure AD Managed Identity(ies).

    .DESCRIPTION
    Function for getting Azure AD Managed Identity(ies).

    .PARAMETER objectId
    (optional) objectID of Managed Identity(ies).

    If not specified, all app registrations will be processed.

    .EXAMPLE
    Get-AzureADManagedIdentity

    Get all Managed Identities.

    .EXAMPLE
    Get-AzureADManagedIdentity -objectId 1234-1234-1234

    Get selected Managed Identity.
    #>

    [CmdletBinding()]
    param (
        [string[]] $objectId
    )

    try {
        # test if connection already exists
        $null = Get-AzureADCurrentSessionInfo -ea Stop
    } catch {
        throw "You must call the Connect-AzureAD cmdlet before calling any other cmdlets."
    }

    $servicePrincipalList = @()

    if (!$objectId) {
        $servicePrincipalList = Get-AzureADServicePrincipal -Filter "servicePrincipalType eq 'ManagedIdentity'" -All:$true
    } else {
        $objectId | % {
            $servicePrincipalList += Get-AzureADServicePrincipal -ObjectId $_
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