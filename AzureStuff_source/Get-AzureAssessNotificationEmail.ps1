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