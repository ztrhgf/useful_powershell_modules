#requires -modules Microsoft.Graph.Beta.Reports, Microsoft.Graph.Beta.Users
function Get-AzureUserAuthMethodChanges {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$upnList,

        [ValidateSet('StrongAuthenticationMethod', 'StrongAuthenticationPhoneAppDetail')]
        # SearchableDeviceKey == FIDO, 'passwordless phone sign-in'
        # StrongAuthenticationPhoneAppDetail == mobile authenticator app
        [string[]] $methodType = ('SearchableDeviceKey', 'StrongAuthenticationPhoneAppDetail')
    )

    # unfortunately I don't know how to directly get events just for specific user :(
    $allMFAMethodRegistration = Get-MgBetaAuditLogDirectoryAudit -All -Property * -Filter "Category eq 'UserManagement' and ActivityDisplayName eq 'Update user' and LoggedByService eq 'Core Directory' and InitiatedBy/App/DisplayName eq 'Azure MFA StrongAuthenticationService'"

    $allFIDOMFAMethodRegistration = Get-MgBetaAuditLogDirectoryAudit -All -Property * -Filter "Category eq 'UserManagement' and ActivityDisplayName eq 'Update user' and LoggedByService eq 'Core Directory' and InitiatedBy/App/DisplayName eq 'Device Registration Service'"



    #FIXME to vypada ze jde brat primo ty user eventy pres LoggedByService eq 'Device Registration Service' ?? (jen bych ignoroval 'Register device')
    ale asi neobsahuje ciste phone app??
    $userMFAMethodRegistration = Get-MgBetaAuditLogDirectoryAudit -All -Property * -Filter "Category eq 'UserManagement' and LoggedByService eq 'Device Registration Service' and InitiatedBy/User/Id eq '$userId'"


    foreach ($upn in $upnList) {
        $userId = Get-MgBetaUser -UserId $upn -Property Id -ErrorAction Stop | select -ExpandProperty Id

        # rozsekat dle typu pridavane metody, $allMFAMethodRegistration ted NEOBSAHUJE vsechny
        # keyIdentifier u FIDO je vlastne ID
        $userMFAMethodRegistration = $allMFAMethodRegistration | ? { $_.TargetResources.Id -eq $userId }

        $userMFAMethodRegistration | % {
            $event = $_
            $userAuthenticatorMFAMethodRegistrationOldValue = $event.TargetResources.ModifiedProperties | ? { $_.DisplayName -in $methodType -and $_.OldValue } | select -ExpandProperty OldValue | ConvertFrom-Json
            $userAuthenticatorMFAMethodRegistrationNewValue = $event.TargetResources.ModifiedProperties | ? { $_.DisplayName -in $methodType -and $_.NewValue } | select -ExpandProperty NewValue | ConvertFrom-Json

            $addedMethod = $userAuthenticatorMFAMethodRegistrationNewValue | ? { $_.Id -notin $userAuthenticatorMFAMethodRegistrationOldValue.Id }

            if ($addedMethod) {
                $addedMethod | select @{n = 'UPN'; e = { $upn } }, @{n = 'Action'; e = { 'Added' } }, @{n = 'DateTimeUTC'; e = { $event.ActivityDateTime } }, *
            }

            $removedMethod = $userAuthenticatorMFAMethodRegistrationOldValue | ? { $_.Id -notin $userAuthenticatorMFAMethodRegistrationNewValue.Id }

            if ($removedMethod) {
                $removedMethod | select @{n = 'UPN'; e = { $upn } }, @{n = 'Action'; e = { 'Removed' } }, @{n = 'DateTimeUTC'; e = { $event.ActivityDateTime } }, *
            }
        }

        $userMFAMethodRegistration = $allFIDOMFAMethodRegistration | ? { $_.TargetResources.Id -eq $userId }

        $userMFAMethodRegistration | % {
            $event = $_
            $userAuthenticatorMFAMethodRegistrationOldValue = $event.TargetResources.ModifiedProperties | ? { $_.DisplayName -in $methodType -and $_.OldValue } | select -ExpandProperty OldValue | ConvertFrom-Json
            $userAuthenticatorMFAMethodRegistrationNewValue = $event.TargetResources.ModifiedProperties | ? { $_.DisplayName -in $methodType -and $_.NewValue } | select -ExpandProperty NewValue | ConvertFrom-Json

            $addedMethod = $userAuthenticatorMFAMethodRegistrationNewValue | ? { $_.Id -notin $userAuthenticatorMFAMethodRegistrationOldValue.Id }

            if ($addedMethod) {
                $addedMethod | select @{n = 'UPN'; e = { $upn } }, @{n = 'Action'; e = { 'Added' } }, @{n = 'DateTimeUTC'; e = { $event.ActivityDateTime } }, *
            }

            $removedMethod = $userAuthenticatorMFAMethodRegistrationOldValue | ? { $_.Id -notin $userAuthenticatorMFAMethodRegistrationNewValue.Id }

            if ($removedMethod) {
                $removedMethod | select @{n = 'UPN'; e = { $upn } }, @{n = 'Action'; e = { 'Removed' } }, @{n = 'DateTimeUTC'; e = { $event.ActivityDateTime } }, *
            }
        }
    }
}