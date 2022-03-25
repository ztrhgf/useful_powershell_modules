function Get-AzureADAppConsentRequest {
    <#
    .SYNOPSIS
    Function for getting AzureAD app consent requests.

    .DESCRIPTION
    Function for getting AzureAD app consent requests.

    .PARAMETER header
    Graph api authentication header.
    Can be create via New-GraphAPIAuthHeader.

    .PARAMETER openAdminConsentPage
    Switch for opening web page with form for granting admin consent for each not yet review application.

    .EXAMPLE
    $header = New-GraphAPIAuthHeader
    Get-AzureADAppConsentRequest -header $header

    .NOTES
    Requires at least permission ConsentRequest.Read.All (to get requests), Directory.Read.All (to get service principal publisher)
    https://docs.microsoft.com/en-us/graph/api/appconsentapprovalroute-list-appconsentrequests?view=graph-rest-1.0&tabs=http
    https://docs.microsoft.com/en-us/graph/api/resources/consentrequests-overview?view=graph-rest-1.0
    #>

    [CmdletBinding()]
    param (
        $header,

        [switch] $openAdminConsentPage
    )

    if (!$header) {
        try {
            $header = New-GraphAPIAuthHeader -reuseExistingAzureADSession -ErrorAction Stop
        } catch {
            throw "Unable to retrieve authentication header for graph api. Create it using New-GraphAPIAuthHeader and pass it using header parameter"
        }
    }

    Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/beta/identityGovernance/appConsent/appConsentRequests" -header $Header | % {
        $userConsentRequestsUri = $_.'userConsentRequests@odata.context' -replace [regex]::escape('$metadata#')
        Write-Verbose "Getting user consent requests via '$userConsentRequestsUri'"
        $userConsentRequests = Invoke-GraphAPIRequest -uri $userConsentRequestsUri -header $Header

        $userConsentRequests = $userConsentRequests | select status, reason, @{name = 'createdBy'; expression = { $_.createdBy.user.userPrincipalName } }, createdDateTime, @{name = 'approval'; expression = { $_.approval.steps | select @{name = 'reviewedBy'; expression = { $_.reviewedBy.userPrincipalName } }, reviewResult, reviewedDateTime, justification } }, @{name = 'RequestId'; expression = { $_.Id } }

        $appVerifiedPublisher = Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$filter=(appId%20eq%20%27$($_.appId)%27)&`$select=verifiedPublisher" -header $Header
        if ($appVerifiedPublisher | Get-Member | ? Name -EQ 'verifiedPublisher') {
            $appVerifiedPublisher = $appVerifiedPublisher.verifiedPublisher.DisplayName
        } else {
            # service principal wasn't found (new application)
            $appVerifiedPublisher = "*unknown*"
        }

        $_ | select appDisplayName, consentType, @{name = 'verifiedPublisher'; expression = { $appVerifiedPublisher } }, @{name = 'pendingScopes'; e = { $_.pendingScopes.displayName } }, @{name = 'consentRequest'; expression = { $userConsentRequests } }

        if ($openAdminConsentPage -and $userConsentRequests.status -eq 'InProgress') {
            Open-AzureADAdminConsentPage -appId $_.appId
        }
    }
}