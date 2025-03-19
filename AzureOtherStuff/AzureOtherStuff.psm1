function Get-AzureAssessNotificationEmail {
    <#
    .SYNOPSIS
    Function returns email(s) of organization technical contact(s) and privileged roles members.

    .DESCRIPTION
    Function returns email(s) of organization technical contact(s) and privileged roles members.

    .EXAMPLE
    $authHeader = New-GraphAPIAuthHeader
    Get-AzureAssessNotificationEmail -authHeader $authHeader

    .NOTES
    Stolen from Get-AADAssessNotificationEmailsReport function (module AzureADAssessment)
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $authHeader
    )

    #region get Organization Technical Contacts
    $OrganizationData = Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/beta/organization?`$select=technicalNotificationMails" -header $authHeader
    if ($OrganizationData) {
        foreach ($technicalNotificationMail in $OrganizationData.technicalNotificationMails) {
            $result = [PSCustomObject]@{
                notificationType           = "Technical Notification"
                notificationScope          = "Tenant"
                recipientType              = "emailAddress"
                recipientEmail             = $technicalNotificationMail
                recipientEmailAlternate    = $null
                recipientId                = $null
                recipientUserPrincipalName = $null
                recipientDisplayName       = $null
            }

            $user = Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/beta/users?`$select=id,userPrincipalName,displayName,mail,otherMails,proxyAddresses&`$filter=proxyAddresses/any(c:c eq 'smtp:$technicalNotificationMail') or otherMails/any(c:c eq 'smtp:$technicalNotificationMail')" -header $authHeader | Select-Object -First 1
        }

        if ($user) {
            $result.recipientType = 'user'
            $result.recipientId = $user.id
            $result.recipientUserPrincipalName = $user.userPrincipalName
            $result.recipientDisplayName = $user.displayName
            $result.recipientEmailAlternate = $user.otherMails -join ';'
        }

        $group = Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/beta/groups?`$filter=proxyAddresses/any(c:c eq 'smtp:$technicalNotificationMail')" -header $authHeader | Select-Object -First 1
        if ($group) {
            $result.recipientType = 'group'
            $result.recipientId = $group.id
            $result.recipientDisplayName = $group.displayName
        }

        Write-Output $result
    }
    #endregion get Organization Technical Contacts

    #region get email addresses of all users with privileged roles
    $DirectoryRoleData = Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/beta/directoryRoles?`$select=id,displayName&`$expand=members" -header $authHeader

    foreach ($role in $DirectoryRoleData) {
        foreach ($roleMember in $role.members) {
            $member = $null
            if ($roleMember.'@odata.type' -eq '#microsoft.graph.user') {
                $member = Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/beta/users?`$select=id,userPrincipalName,displayName,mail,otherMails,proxyAddresses&`$filter=id eq '$($roleMember.id)'" -header $authHeader | Select-Object -First 1
            } elseif ($roleMember.'@odata.type' -eq '#microsoft.graph.group') {
                $member = Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/beta/groups?`$select=id,displayName,mail,proxyAddresses&`$filter=id eq '$($roleMember.id)'" -header $authHeader | Select-Object -First 1
            } elseif ($roleMember.'@odata.type' -eq '#microsoft.graph.servicePrincipal') {
                $member = Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$select=id,displayName&`$filter=id eq '$($roleMember.id)'" -header $authHeader | Select-Object -First 1
            } else {
                Write-Error "Undefined type $($roleMember.'@odata.type')"
            }

            [PSCustomObject]@{
                notificationType           = $role.displayName
                notificationScope          = 'Role'
                recipientType              = ($roleMember.'@odata.type') -replace '#microsoft.graph.', ''
                recipientEmail             = ($member.'mail')
                recipientEmailAlternate    = ($member.'otherMails') -join ';'
                recipientId                = ($member.'id')
                recipientUserPrincipalName = ($member.'userPrincipalName')
                recipientDisplayName       = ($member.'displayName')
            }
        }
    }
    #endregion get email addresses of all users with privileged roles
}

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

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    $accessToken = Get-AzAccessToken -ResourceUri 'https://graph.windows.net' -AsSecureString -ErrorAction Stop
    $token = [PSCredential]::New('dummy', $accessToken.Token).GetNetworkCredential().Password

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
        Authorization  = "Bearer $token"
    }

    Invoke-GraphAPIRequest -uri $url -header $header
}

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

function Get-AzureDevOpsOrganizationOverview {
    <#
    .SYNOPSIS
    Function for getting list of all Azure DevOps organizations that uses your AzureAD directory.

    .DESCRIPTION
    Function for getting list of all Azure DevOps organizations that uses your AzureAD directory.
    It is the same data as downloaded csv from https://dev.azure.com/<organizationName>/_settings/organizationAad.

    .PARAMETER tenantId
    (optional) ID of your Azure tenant.
    Of omitted, tenantId from MSAL auth. ticket will be used.

    .EXAMPLE
    Get-AzureDevOpsOrganizationOverview

    Returns all DevOps organizations in your Azure tenant.

    .NOTES
    PowerShell module AzSK.ADO > ContextHelper.ps1 > GetCurrentContext
    https://stackoverflow.com/questions/56355274/getting-oauth-tokens-for-azure-devops-api-consumption
    https://stackoverflow.com/questions/52896114/use-azure-ad-token-to-authenticate-with-azure-devops
    #>

    [CmdletBinding()]
    param (
        [string] $tenantId = $_tenantId
    )

    $header = New-AzureDevOpsAuthHeader -ErrorAction Stop

    if (!$tenantId) {
        throw "'tenantId' parameter cannot be empty"
    }

    # URL retrieved thanks to developer mod at page https://dev.azure.com/<organizationName>/_settings/organizationAad
    Invoke-WebRequest -Uri "https://aexprodweu1.vsaex.visualstudio.com/_apis/EnterpriseCatalog/Organizations?tenantId=$tenantId" -Method get -ContentType "application/json" -Headers $header | select -ExpandProperty content | ConvertFrom-Csv | select @{name = 'OrganizationName'; expression = { $_.'Organization Name' } }, @{name = 'OrganizationId'; expression = { $_.'Organization Id' } }, Url, Owner, @{name = 'ExceptionType'; expression = { $_.'Exception Type' } }, @{name = 'ErrorMessage'; expression = { $_.'Error Message' } } -ExcludeProperty 'Organization Name', 'Organization Id', 'Exception Type', 'Error Message'
}

function Open-AzureAdminConsentPage {
    <#
    .SYNOPSIS
    Function for opening web page with admin consent to requested/selected permissions to selected application.

    .DESCRIPTION
    Function for opening web page with admin consent to requested/selected permissions to selected application.

    .PARAMETER appId
    Application (client) ID.

    .PARAMETER tenantId
    Your Azure tenant ID.

    .EXAMPLE
    Open-AzureAdminConsentPage -appId 123412341234 -scope openid, profile, email, user.read, Mail.Send

    Grant admin consent for selected permissions to app with client ID 123412341234.

    .EXAMPLE
    Open-AzureAdminConsentPage -appId 123412341234

    Grant admin consent for requested permissions to app with client ID 123412341234.

    .NOTES
    https://docs.microsoft.com/en-us/azure/active-directory/manage-apps/grant-admin-consent
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $appId,

        [string] $tenantId = $_tenantId,

        [string[]] $scope,

        [switch] $justURL
    )

    if ($scope) {
        # grant custom permission
        $scope = $scope.trim() -join "%20"
        $URL = "https://login.microsoftonline.com/$tenantId/v2.0/adminconsent?client_id=$appId&scope=$scope"

        if ($justURL) {
            return $URL
        } else {
            Start-Process $URL
        }
    } else {
        # grant requested permissions
        $URL = "https://login.microsoftonline.com/$tenantId/adminconsent?client_id=$appId"
        if ($justURL) {
            return $URL
        } else {
            Start-Process $URL
        }
    }
}

Export-ModuleMember -function Get-AzureAssessNotificationEmail, Get-AzureAuditAggregatedSignInEvent, Get-AzureAuditSignInEvent, Get-AzureDevOpsOrganizationOverview, Open-AzureAdminConsentPage

