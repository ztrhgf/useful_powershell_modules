function Get-AzureAuditSignInEvent {
    <#
    .SYNOPSIS
    Proxy function for Get-MgBetaAuditLogSignIn that simplifies some basic filtering.

    .DESCRIPTION
    Proxy function for Get-MgBetaAuditLogSignIn that simplifies some basic filtering.

    .PARAMETER userPrincipalName
    UPN of the user you want to get sign-in logs for.
    It is CasE SENSitivE!

    .PARAMETER appId
    AppId of the app(s) you want to get sign-in logs for.

    .PARAMETER from
    Date when the search should start.

    .PARAMETER to
    Date when the search should end.

    .PARAMETER type
    Type of the sign-in events you want to search for.

    Possible values: 'any', 'interactiveUser', 'nonInteractiveUser', 'servicePrincipal', 'managedIdentity'

    By default 'any'.

    .EXAMPLE
    An example
    Get-AzureAuditSignInEvent -userPrincipalName johnd@contoso.com -from (get-date).AddDays(-3) -Verbose

    .EXAMPLE
    Get-AzureAuditSignInEvent -appId 75b6afef-74ef-42a3-ab65-c9aa08a1d38b -from (get-date).AddDays(-7) -Verbose

    .EXAMPLE
    Get-AzureAuditSignInEvent -type managedIdentity

    Get all managed identity sign-in events.

    .NOTES
    Requires following scopes: AuditLog.Read.All
    #>

    [CmdletBinding()]
    param (
        [string] $userPrincipalName,

        [string[]] $appId,

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

        [ValidateSet('any', 'interactiveUser', 'nonInteractiveUser', 'servicePrincipal', 'managedIdentity')]
        [string] $type = "any"
    )

    if ($from -and $from.getType().name -eq "string") { $from = [DateTime]::Parse($from) }
    if ($to -and $to.getType().name -eq "string") { $to = [DateTime]::Parse($to) }

    if ($from -and $to -and $from -gt $to) {
        throw "From cannot be after To"
    }

    if ([datetime]::Now.AddDays(-30) -gt $from) {
        Write-Warning "By default Azure logs are only 30 days old"
    }

    $filter = @()

    if ($userPrincipalName) {
        Write-Warning "Beware that filtering by UPN is case sensitive!"
        $filter += "UserPrincipalName eq '$userPrincipalName'"
    }
    if ($appId) {
        $appIdFilter = ""
        $appId | % {
            if ($appIdFilter) {
                $appIdFilter += " or "
            }
            $appIdFilter += "AppId eq '$_'"
        }
        $filter += "($appIdFilter)"
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
    if ($type -ne "interactiveUser") {
        if ($type -eq "any") {
            (Get-Variable type).Attributes.Clear()
            $type = 'interactiveUser', 'nonInteractiveUser', 'servicePrincipal', 'managedIdentity'
        }

        $typeFilter = ""
        $type | % {
            if ($typeFilter) {
                $typeFilter += " or "
            }
            $typeFilter += "t eq '$_'"
        }
        $filter += "(signInEventTypes/any(t: $typeFilter))"
    }

    $finalFilter = $filter -join ' and '
    Write-Verbose "filter: $finalFilter"
    Get-MgBetaAuditLogSignIn -All -Filter $finalFilter
}