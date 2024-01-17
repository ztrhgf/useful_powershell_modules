function Add-AzureGuest {
    <#
    .SYNOPSIS
    Function for inviting guest user to Azure AD.

    .DESCRIPTION
    Function for inviting guest user to Azure AD.

    .PARAMETER displayName
    Display name of the user.
    Suffix (guest) will be added automatically.

    a.k.a Jan Novak

    .PARAMETER emailAddress
    Email address of the user.

    a.k.a novak@seznam.cz

    .PARAMETER parentTeamsGroup
    Optional parameter.

    Name of Teams group, where the guest should be added as member. (it can take several minutes, before this change propagates!)

    .EXAMPLE
    Add-AzureGuest -displayName "Jan Novak" -emailAddress "novak@seznam.cz"
    #>

    [CmdletBinding()]
    [Alias("New-AzureADGuest")]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript( {
                If ($_ -match "\(guest\)") {
                    throw "$_ (guest) will be added automatically."
                } else {
                    $true
                }
            })]
        [string] $displayName
        ,
        [Parameter(Mandatory = $true)]
        [ValidateScript( {
                If ($_ -match "@") {
                    $true
                } else {
                    Throw "$_ isn't email address"
                }
            })]
        [string] $emailAddress
        ,
        [ValidateScript( {
                If ($_ -notmatch "^External_") {
                    throw "$_ doesn't allow guest members (doesn't start with External_ prefix, so guests will be automatically removed)"
                } else {
                    $true
                }
            })]
        [string] $parentTeamsGroup
    )

    $null = Connect-MgGraph

    # naming conventions
    (Get-Variable displayName).Attributes.Clear()
    $displayName = $displayName.trim() + " (guest)"
    $emailAddress = $emailAddress.trim()

    "Creating Guest: $displayName EMAIL: $emailaddress"

    $null = New-MgInvitation -InvitedUserDisplayName $displayName -InvitedUserEmailAddress $emailAddress -InviteRedirectUrl "https://myapps.microsoft.com" -SendInvitationMessage:$true -InvitedUserType Guest

    if ($parentTeamsGroup) {
        $groupID = Get-MgGroup -Filter "displayName eq '$parentTeamsGroup'" | select -exp Id
        if (!$groupID) { throw "Unable to find group $parentTeamsGroup" }
        $guestId = Get-MgUser -Filter "mail eq '$emailaddress'" | select -exp Id
        New-MgGroupMember -GroupId $groupID -DirectoryObjectId $guestId
    }
}

function Disable-AzureGuest {
    <#
    .SYNOPSIS
    Function for disabling guest user in Azure AD.

    .DESCRIPTION
    Function for disabling guest user in Azure AD.

    Do NOT REMOVE the account, because lot of connected systems use UPN as identifier instead of SID.
    Therefore if someone in the future add such guest again, he would get access to all stuff, previous guest had access to.

    .PARAMETER displayName
    Display name of the user.

    If not specified, GUI with all guests will popup.

    .EXAMPLE
    Disable-AzureGuest -displayName "Jan Novak (guest)"

    Disables "Jan Novak (guest)" guest Azure AD account.

    .EXAMPLE
    Disable-AzureGuest

    Show GUI with all available guest accounts. The selected one will be disabled.
    #>

    [CmdletBinding()]
    [Alias("Remove-AzureADGuest")]
    param (
        [string[]] $displayName
    )

    $null = Connect-MgGraph -ea Stop

    $guestId = @()

    if (!$displayName) {
        # Get all the Guest Users
        $guest = Get-MgUser -All -Filter "UserType eq 'Guest' and AccountEnabled eq true" | select DisplayName, Mail, Id | Out-GridView -OutputMode Multiple -Title "Select accounts for disable"
        $guestId = $guest.id
    } else {
        $displayName | % {
            $guest = Get-MgUser -Filter "DisplayName eq '$_' and UserType eq 'Guest' and AccountEnabled eq true"
            if ($guest) {
                $guestId += $guest.Id
            } else {
                Write-Warning "$_ wasn't found or it is not guest account or is disabled already"
            }
        }
    }

    if ($guestId) {
        $guestId | % {
            "Blocking guest $_"

            # block Sign-In
            Update-MgUser -UserId $_ -AccountEnabled:$false

            # invalidate Azure AD Tokens
            $null = Revoke-MgUserSignInSession -UserId $_ -Confirm:$false
        }
    } else {
        Write-Warning "No guest to disable"
    }
}

function Get-AzureAuthenticatorLastUsedDate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$upnList
    )

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-MgGraph."
    }

    foreach ($upn in $upnList) {
        # filter is case sensitive in Get-MgAuditLogSignIn and UPNs seems to be always in lower case
        $upn = $upn.tolower()

        Write-Warning "Processing $upn"

        $mfaMethod = Get-MgBetaUserAuthenticationMethod -UserId $upn | Expand-MgAdditionalProperties

        $mobileAuthenticatorList = $mfaMethod | ? ObjectType -EQ "microsoftAuthenticatorAuthenticationMethod"

        if (!$mobileAuthenticatorList) {
            Write-Warning "$upn doesn't have an authenticator app set"
            continue
        }

        if ($mobileAuthenticatorList.count -lt 2) {
            Write-Warning "$upn doesn't have more than one authenticator set"
            continue
        }

        $mobileAuthenticatorList = $mobileAuthenticatorList | select *, @{n = 'LastTimeUsedUTC'; e = { $null } }, @{n = 'OperatingSystem'; e = { $null } } -ExcludeProperty '@odata.type', 'ObjectType'

        # get all successfully completed MFA prompts
        # 0 = Success
        # 50140 = "This occurred due to 'Keep me signed in' interrupt when the user was signing in."
        $successfulMFAPrompt = Get-MgBetaAuditLogSignIn -all -Filter "UserPrincipalName eq '$upn' and AuthenticationRequirement eq 'multiFactorAuthentication' and conditionalAccessStatus eq 'success'" -Property * | ? { $_.Status.ErrorCode -in 0, 50140 -and ($_.AuthenticationDetails.AuthenticationStepResultDetail | % { if ($_ -in 'MFA successfully completed', 'MFA completed in Azure AD', 'User approved', 'MFA required in Azure AD', 'MFA requirement satisfied by strong authentication') { $true } }) }

        if (!$successfulMFAPrompt) {
            Write-Warning "No completed MFA prompts found (in last 30 days?)"
        } else {
            foreach ($mfaPrompt in $successfulMFAPrompt) {
                if ($mobileAuthenticatorList.count -eq ($mobileAuthenticatorList.LastTimeUsedUTC | ? { $_ }).count) {
                    # I have last used date for each registered authenticator
                    Write-Verbose "I have LastTimeUsedUTC for each authenticator app"
                    break
                }
                # "### $($mfaPrompt.AppDisplayName)"
                $mobileAuthenticatorId = $mfaPrompt.AuthenticationAppDeviceDetails.DeviceId # je ve skutecnosti ID z Get-MgUserAuthenticationMethod
                if (!$mobileAuthenticatorId) {
                    Write-Verbose "This isn't event where authenticator was used, skipping"
                    continue
                }

                $correspondingAuthenticator = $mobileAuthenticatorList | ? Id -EQ $mobileAuthenticatorId

                if (!$correspondingAuthenticator) {
                    Write-Verbose "Authenticator with ID $mobileAuthenticatorId doesn't exist anymore"
                } else {
                    if ($correspondingAuthenticator.LastTimeUsedUTC) {
                        Write-Verbose "$mobileAuthenticatorId was already processed"
                        continue
                    } else {
                        Write-Verbose "$mobileAuthenticatorId setting LastTimeUsedUTC $($mfaPrompt.CreatedDateTime) OperatingSystem $($mfaPrompt.AuthenticationAppDeviceDetails.OperatingSystem)"
                        $correspondingAuthenticator.LastTimeUsedUTC = $mfaPrompt.CreatedDateTime
                        $correspondingAuthenticator.OperatingSystem = $mfaPrompt.AuthenticationAppDeviceDetails.OperatingSystem
                    }
                }
            }
        }

        #TODO u authenticatoru bez udaju zjistit kdy se zaregistroval, mozna je novy a jeste ho nepouzil

        [PSCustomObject]@{
            UPN                 = $upn
            MobileAuthenticator = $mobileAuthenticatorList
        }
    }
}

function Get-AzureCompletedMFAPrompt {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$upnList
    )

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-MgGraph."
    }

    foreach ($upn in $upnList) {
        # filter is case sensitive in Get-MgAuditLogSignIn
        $upn = $upn.tolower()

        Write-Warning "Processing $upn"

        $mfaMethod = Get-MgBetaUserAuthenticationMethod -UserId $upn | Expand-MgAdditionalProperties

        # get all successfully completed MFA prompts
        # 0 = Success
        # 50140 = "This occurred due to 'Keep me signed in' interrupt when the user was signing in."
        $successfulMFAPrompt = Get-MgBetaAuditLogSignIn -all -Filter "UserPrincipalName eq '$upn' and AuthenticationRequirement eq 'multiFactorAuthentication' and conditionalAccessStatus eq 'success'" -Property * | ? { $_.Status.ErrorCode -in 0, 50140 -and ($_.AuthenticationDetails.AuthenticationStepResultDetail | % { if ($_ -in 'MFA successfully completed', 'MFA completed in Azure AD', 'User approved', 'MFA required in Azure AD', 'MFA requirement satisfied by strong authentication') { $true } }) }

        if (!$successfulMFAPrompt) {
            Write-Warning "No completed MFA prompts found"
            continue
        }

        foreach ($mfaPrompt in $successfulMFAPrompt) {
            $authenticationMethod = $mfaPrompt.AuthenticationDetails | ? { $_.AuthenticationMethod -notin "Previously satisfied", "Password" -and $_.Succeeded -eq $true }
            if ($authenticationMethod) {
                $authMethod = $authenticationMethod.AuthenticationMethod
                if (!$authMethod) {
                    # sometimes AuthenticationMethod is empty, but AuthenticationStepResultDetail contains 'MFA completed in Azure AD'
                    $authMethod = $authenticationMethod.AuthenticationStepResultDetail
                }
                $authDetail = $authenticationMethod.AuthenticationMethodDetail
                if (!$authDetail -and $mfaPrompt.AuthenticationAppDeviceDetails.DeviceId) {
                    $authDetail = $mfaPrompt.AuthenticationAppDeviceDetails
                }
            } else {
                $authMethod = $mfaPrompt.MfaDetail.AuthMethod
                $authDetail = $mfaPrompt.MfaDetail.AuthDetail
            }

            [PSCustomObject]@{
                UPN                = $upn
                CreatedDateTimeUTC = $mfaPrompt.CreatedDateTime
                AuthMethod         = $authMethod
                AuthDetail         = $authDetail
                AuthDeviceId       = $mfaPrompt.AuthenticationAppDeviceDetails.DeviceId
                AuditEvent         = $mfaPrompt
            }
        }
    }
}

function Get-AzureSkuAssignment {
    <#
    .SYNOPSIS
    Function returns users with selected Sku license.

    .DESCRIPTION
    Function returns users with selected Sku license.

    .PARAMETER sku
    SkuId or SkuPartNumber of the O365 license Sku.
    If not provided, all users and their Skus will be outputted.

    SkuId/SkuPartNumber can be found via: Get-MgSubscribedSku -All

    .PARAMETER assignmentType
    Limit what kind of license assignment the user needs to have.

    Possible values are: 'direct', 'inherited'

    By default users with both types are displayed.

    .EXAMPLE
    Get-AzureSkuAssignment -sku "f8a1db68-be16-40ed-86d5-cb42ce701560"

    Get all users with selected sku (defined by id).

    .EXAMPLE
    Get-AzureSkuAssignment -sku "POWER_BI_PRO"

    Get all users with selected sku.

    .EXAMPLE
    Get-AzureSkuAssignment

    Get all users and their skus.

    .EXAMPLE
    Get-AzureSkuAssignment -assignmentType direct

    Get all users which have some sku assigned directly.

    .EXAMPLE
    Get-AzureSkuAssignment -sku "POWER_BI_PRO" -assignmentType inherited

    Get all users with selected sku if it is inherited.
    #>

    [CmdletBinding()]
    param (
        [ArgumentCompleter( {
                param ($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams)

                Get-MgSubscribedSku -Property SkuPartNumber, SkuId -All | ? SkuPartNumber -Like "*$WordToComplete*" | select -ExpandProperty SkuPartNumber
            })]
        [string] $sku,

        [ValidateSet('direct', 'inherited')]
        [string[]] $assignmentType = ('direct', 'inherited'),

        [string[]] $userProperty = ('id', 'userprincipalname', 'assignedLicenses', 'LicenseAssignmentStates')
    )

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): The context is invalid. Please login using Connect-MgGraph."
    }

    # add mandatory property
    if ($userProperty -notcontains 'assignedLicenses') { $userProperty += 'assignedLicenses' }
    if ($userProperty -notcontains 'LicenseAssignmentStates') { $userProperty += 'LicenseAssignmentStates' }

    $param = @{
        Select = $userProperty
        All    = $true
    }

    if ($sku) {
        $skuId = Get-MgSubscribedSku -Property SkuPartNumber, SkuId -All | ? { $_.SkuId -eq $sku -or $_.SkuPartNumber -eq $sku } | select -ExpandProperty SkuId
        if (!$skuId) {
            throw "Sku with id $skuId doesn't exist"
        }
        $param.Filter = "assignedLicenses/any(u:u/skuId eq $skuId)"
    }

    if ($assignmentType.count -eq 2) {
        # has some license
        $whereFilter = { $_.assignedLicenses }
    } elseif ($assignmentType -contains 'direct') {
        # direct assignment
        if ($sku) {
            $whereFilter = { $_.assignedLicenses -and ($_.LicenseAssignmentStates | ? { $_.SkuId -eq $skuId -and $_.AssignedByGroup -eq $null }) }
        } else {
            $whereFilter = { $_.assignedLicenses -and ($_.LicenseAssignmentStates.AssignedByGroup -eq $null).count -ge 1 }
        }
    } else {
        # inherited assignment
        if ($sku) {
            $whereFilter = { $_.assignedLicenses -and ($_.LicenseAssignmentStates | ? { $_.SkuId -eq $skuId -and $_.AssignedByGroup -ne $null }) }
        } else {
            $whereFilter = { $_.assignedLicenses -and $_.LicenseAssignmentStates.AssignedByGroup -ne $null }
        }
    }

    Get-MgUser @param | select $userProperty | ? $whereFilter
}

function Get-AzureSkuAssignmentError {
    <#
    .SYNOPSIS
    Function returns users that have problems with licenses assignment.

    .DESCRIPTION
    Function returns users that have problems with licenses assignment.
    #>

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): The context is invalid. Please login using Connect-MgGraph."
    }

    function _getGroupName {
        if ($license.AssignedByGroup) {
            (Get-MgGroup -GroupId $license.AssignedByGroup -Property DisplayName -ea silent).DisplayName
        }
    }

    $userWithLicenseProblem = Get-MgUser -Property UserPrincipalName, Id, LicenseAssignmentStates -All | ? { $_.LicenseAssignmentStates.state -eq 'error' }

    foreach ($user in $userWithLicenseProblem) {
        $errorLicense = $user.LicenseAssignmentStates | ? State -EQ "Error"

        foreach ($license in $errorLicense) {
            [PSCustomObject]@{
                UserPrincipalName   = $user.UserPrincipalName
                UserId              = $user.Id
                LicError            = $license.Error
                AssignedByGroup     = $license.AssignedByGroup
                AssignedByGroupName = _getGroupName
                LastUpdatedDateTime = $license.LastUpdatedDateTime
                SkuId               = $license.SkuId
                SkuName             = (Get-MgSubscribedSku -Property SkuPartNumber, SkuId -All | ? { $_.SkuId -eq $license.SkuId } | select -ExpandProperty SkuPartNumber)
            }
        }
    }

    <# logictejsi by bylo jit shora dolu (group > user), ale tam je problem s vracenim potrebnych dat
    Get-MgGroup -Property Id, DisplayName, AssignedLicenses, LicenseProcessingState, MembersWithLicenseErrors -Filter "HasMembersWithLicenseErrors eq true" | % {
        $groupId = $_.Id
        # kvuli bugu je potreba delat primy api call namisto pouziti property MembersWithLicenseErrors (je prazdna)
        Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId/membersWithLicenseErrors" -OutputType PSObject | select -ExpandProperty value
    }
    #>
}

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

Export-ModuleMember -function Add-AzureGuest, Disable-AzureGuest, Get-AzureAuthenticatorLastUsedDate, Get-AzureCompletedMFAPrompt, Get-AzureSkuAssignment, Get-AzureSkuAssignmentError, Get-AzureUserAuthMethodChanges

Export-ModuleMember -alias New-AzureADGuest, Remove-AzureADGuest
