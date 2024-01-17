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

function Get-AzureDevOpsOrganizationOverview {
    <#
    .SYNOPSIS
    Function for getting list of all Azure DevOps organizations that uses your AzureAD directory.

    .DESCRIPTION
    Function for getting list of all Azure DevOps organizations that uses your AzureAD directory.
    It is the same data as downloaded csv from https://dev.azure.com/<organizationName>/_settings/organizationAad.

    Function uses MSAL to authenticate (requires MSAL.PS module).

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
        $tenantId = $msalToken.tenantId
        Write-Verbose "Set TenantId to $tenantId (retrieved from MSAL token)"
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

Export-ModuleMember -function Get-AzureAssessNotificationEmail, Get-AzureDevOpsOrganizationOverview, Open-AzureAdminConsentPage

