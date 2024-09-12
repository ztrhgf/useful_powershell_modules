#requires -modules Az.Accounts
function Get-AzureAuditAggregatedSignInEvent {
    <#
    .SYNOPSIS
    Function for getting aggregated types of Azure sign-in logs.
    A.k.a. 'User sign-ins (non-interactive)', 'Service principal sign-ins', 'Managed identity sign-ins'.

    .DESCRIPTION
    Function for getting aggregated types of Azure sign-in logs.
    A.k.a. 'User sign-ins (non-interactive)', 'Service principal sign-ins', 'Managed identity sign-ins'.

    .PARAMETER type
    Type of the sign in logs:
        - summarizedUserNonInteractive ('User sign-ins (non-interactive)')
        - summarizedServicePrincipal ('Service principal sign-ins')
        - summarizedMSI ('Managed identity sign-ins')

    .PARAMETER tenantId
    Id of your tenant.

    .PARAMETER userPrincipalName
    (optional) UPN of the user whose sign-ins should be searched.

    .PARAMETER appId
    (optional) Application ID of the enterprise app whose sign-ins should be searched.

    .PARAMETER from
    (optional) Date when the search should start.

    Only 30 days old events are stored by default anyway.

    .PARAMETER to
    (optional) Date when the search should end.

    .PARAMETER aggregationWindow
    How the data should be aggregated:
        - 1h
        - 6h
        - 1d

    By default 1d.

    .EXAMPLE
    Get-AzureAuditAggregatedSignInEvent -type summarizedServicePrincipal -appId 'aca0ba6e-7b50-4aa1-af0e-327222ba584c'

    Get all 'Service principal sign-ins' events for selected enterprise app aggregated by 1 day.

    .NOTES
    Token can be created using (Get-AzAccessToken -AsSecureString -ResourceTypeName AadGraph).token.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('summarizedUserNonInteractive', 'summarizedServicePrincipal', 'summarizedMSI')]
        [string] $type,

        [ValidateNotNullOrEmpty()]
        [string] $tenantId = $_tenantId,

        [string] $userPrincipalName,

        [string] $appId,

        [ValidateScript({
                if (($_.getType().name -eq "string" -and [DateTime]::Parse($_)) -or ($_.getType().name -eq "dateTime")) {
                    $true
                } else {
                    throw "Enter in format per your culture. For cs-CZ: 15.2.2019 15:00. For en-US: 2.15.2019 15:00."
                }
            })]
        $from,

        [ValidateScript({
                if (($_.getType().name -eq "string" -and [DateTime]::Parse($_)) -or ($_.getType().name -eq "dateTime")) {
                    $true
                } else {
                    throw "Enter in format per your culture. For cs-CZ: 15.2.2019 15:00. For en-US: 2.15.2019 15:00."
                }
            })]
        $to,

        [ValidateSet('1d', '1h', '6h')]
        [string] $aggregationWindow = '1d'
    )

    if (!(Get-Command 'Get-AzAccessToken -AsSecureString' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -AsSecureString -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    $accessToken = Get-AzAccessToken -AsSecureString -ResourceUri 'https://graph.windows.net' -ErrorAction Stop

    if (!$tenantId) {
        $tenantId = $accessToken.TenantId

        if (!$tenantId) {
            throw "TenantId cannot be empty"
        }
    }

    (Get-Variable type).Attributes.Clear()
    switch ($type) {
        'summarizedUserNonInteractive' { $type = 'getSummarizedNonInteractiveSignIns' }
        'summarizedServicePrincipal' { $type = 'getSummarizedServicePrincipalSignIns' }
        'summarizedMSI' { $type = 'getSummarizedMSISignIns' }
    }

    if ($from -and $from.getType().name -eq "string") { $from = [DateTime]::Parse($from) }
    if ($to -and $to.getType().name -eq "string") { $to = [DateTime]::Parse($to) }

    if ($from -and $to -and $from -gt $to) {
        throw "From cannot be after To"
    }

    $filter = @()

    if ($userPrincipalName) {
        Write-Warning "Beware that filtering by UPN is case sensitive!"
        $filter += "UserPrincipalName eq '$userPrincipalName'"
    }
    if ($appId) {
        $filter += "(appId eq '$appId' or contains(tolower(appDisplayName), '$appId'))"
    }
    if ($from) {
        # Azure logs use UTC time
        $from = $from.ToUniversalTime()
        $filterDateTime = Get-Date -Date $from -Format "yyyy-MM-ddTHH:mm:ss"
        $filter += "CreatedDateTime ge $filterDateTime`Z"
    }
    if ($to) {
        # Azure logs use UTC time
        $to = $to.ToUniversalTime()
        $filterDateTime = Get-Date -Date $to -Format "yyyy-MM-ddTHH:mm:ss"
        $filter += "CreatedDateTime le $filterDateTime`Z"
    }

    $finalFilter = $filter -join ' and '
    Write-Verbose "filter: $finalFilter"

    $url = "https://graph.windows.net/$tenantId/activities/$type(aggregationWindow='$aggregationWindow')?`$filter=$finalFilter"
    Write-Verbose "url: $url"

    $url = $url -replace " ", "%20" -replace "'", "%27"
    Write-Verbose "escaped url: $url"

    $header = @{
        "Content-Type" = "application/json"
        Authorization  = "Bearer $($accessToken.token)"
    }

    Invoke-GraphAPIRequest -uri $url -header $header
}