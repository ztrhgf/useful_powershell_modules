function Get-AzureADAppVerificationStatus {
    param (
        [Parameter(Mandatory = $false, ParameterSetName = "entApp")]
        [string] $servicePrincipalObjectId,

        [Parameter(Mandatory = $false, ParameterSetName = "appReg")]
        [string] $appRegObjectId,

        $header
    )

    if (!$header) {
        try {
            $header = New-GraphAPIAuthHeader -reuseExistingAzureADSession -ErrorAction Stop
        } catch {
            throw "Unable to retrieve authentication header for graph api. Create it using New-GraphAPIAuthHeader and pass it using header parameter"
        }
    }

    if ($appRegObjectId) {
        $URL = "https://graph.microsoft.com/v1.0/applications/$appRegObjectId`?`$select=displayName,verifiedPublisher"
    } elseif ($servicePrincipalObjectId) {
        $URL = "https://graph.microsoft.com/v1.0/servicePrincipals/$servicePrincipalObjectId`?`$select=displayName,verifiedPublisher"
    } else {
        $URL = "https://graph.microsoft.com/v1.0/servicePrincipals?`$select=displayName,verifiedPublisher"
    }

    Invoke-GraphAPIRequest -uri $URL -header $header | select displayName, @{name = 'publisherName'; expression = { $_.verifiedPublisher.displayName } }, @{name = 'publisherId'; expression = { $_.verifiedPublisher.verifiedPublisherId } }, @{name = 'publisherAdded'; expression = { Get-Date $_.verifiedPublisher.addedDateTime } }
}