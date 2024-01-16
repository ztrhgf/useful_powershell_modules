#Requires -Module Microsoft.Graph.Authentication, Microsoft.Graph.Applications, Microsoft.Graph.DeviceManagement.Enrollment, Microsoft.Graph.DirectoryObjects, Microsoft.Graph.Users, Microsoft.Graph.Identity.SignIns, Microsoft.Graph.Identity.Governance
#Requires -Module Az.Accounts
#Requires -Module Pnp.PowerShell
#Requires -Module MSAL.PS
#Requires -Module ExchangeOnlineManagement
function Remove-AzureAccountOccurrence {
    <#
    .SYNOPSIS
    Function for removal of selected AAD account occurrences in various parts of AAD.

    .DESCRIPTION
    Function for removal of selected AAD account occurrences in various parts of AAD.

    .PARAMETER inputObject
    PSCustomObject that is outputted by Get-AzureAccountOccurrence function.
    Contains information about account and its occurrences i.e. is used in this function as information about what to remove and from where.

    Object (as a output of Get-AzureAccountOccurrence) should have these properties:
        UPN
        DisplayName
        ObjectType
        ObjectId
        IAM
        MemberOfDirectoryRole
        MemberOfGroup
        PermissionConsent
        Owner
        SharepointSiteOwner
        AppUsersAndGroupsRoleAssignment
        KeyVaultAccessPolicy
        ExchangeRole

    .PARAMETER replaceByUser
    (optional) ObjectId or UPN of the AAD user that will replace processed user as a new owner/manager.
    But if there are other owners, the one being removed won't be replaced, just deleted!

    Cannot be used with replaceByManager.

    .PARAMETER replaceByManager
    Switch for using user's manager as a new owner/manager.
    Applies ONLY for processed USERS (because only users have managers) and not other object types!

    If there are other owners, the one being removed won't be replaced, just deleted!

    Cannot be used with replaceByUser.

    .PARAMETER whatIf
    Switch for omitting any changes, just output what would be done.

    .PARAMETER removeRegisteredDevice
    Switch for removal of registered devices. Otherwise registered devices stays intact.

    This doesn't apply to joined device.

    .PARAMETER informNewManOwn
    Switch for sending email notification to new owners/managers about what and why was transferred to them.

    .EXAMPLE
    Get-AzureAccountOccurrence -userPrincipalName pavel@contoso.com | Remove-AzureAccountOccurrence -whatIf

    Get all occurrences of specified user and just output what would be done with them.

    .EXAMPLE
    Get-AzureAccountOccurrence -userPrincipalName pavel@contoso.com | Remove-AzureAccountOccurrence

    Get all occurrences of specified user and remove them.
    In case user has registered some devices, they stay intact.

    .EXAMPLE
    Get-AzureAccountOccurrence -userPrincipalName pavel@contoso.com | Remove-AzureAccountOccurrence -removeRegisteredDevice

    Get all occurrences of specified user and remove them.
    In case user has registered some devices, they will be deleted.

    .EXAMPLE
    Get-AzureAccountOccurrence -userPrincipalName pavel@contoso.com | Remove-AzureAccountOccurrence -replaceByUser 1234-1234-1234-1234

    Get all occurrences of specified user and remove them.
    In case user is owner or manager on some object(s) he will be replaced there by specified user (for ownerships this apply only if removed user is last owner).
    In case user has registered some devices, they stay intact.

    .EXAMPLE
    Get-AzureAccountOccurrence -userPrincipalName pavel@contoso.com | Remove-AzureAccountOccurrence -replaceByManager

    Get all occurrences of specified user and remove them.
    In case user is owner or manager on some object(s) he will be replaced there by his manager (for ownerships this apply only if removed user is last owner).
    In case user has registered some devices, they stay intact.
    #>

    [CmdletBinding()]
    [Alias("Remove-AzureADAccountOccurrence")]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSCustomObject] $inputObject,

        [string] $replaceByUser,

        [switch] $replaceByManager,

        [switch] $whatIf,

        [switch] $removeRegisteredDevice,

        [switch] $informNewManOwn
    )

    begin {
        if ($replaceByUser -and $replaceByManager) {
            throw "replaceByUser and replaceByManager cannot be used together. Choose one of them."
        }

        if ($informNewManOwn -and (!$replaceByUser -and !$replaceByManager)) {
            Write-Warning "Parameter 'informNewManOwn' will be ignored because no replacements will be made."
            $informNewManOwn = $false
        }

        #region connect
        # connect to AzureAD
        Write-Verbose "Connecting to AzureAD"
        $null = Connect-MgGraph -ea Stop -Scopes Directory.AccessAsUser.All, GroupMember.ReadWrite.All, User.Read.All, GroupMember.ReadWrite.All, DelegatedPermissionGrant.ReadWrite.All, Application.ReadWrite.All, AppRoleAssignment.ReadWrite.All

        Write-Verbose "Connecting to AzAccount"
        $null = Connect-AzAccount2 -ea Stop

        # connect sharepoint online
        if ($inputObject.SharepointSiteOwner) {
            Write-Verbose "Connecting to Sharepoint"
            Connect-PnPOnline2 -asMFAUser -ea Stop
        }

        if ($inputObject.ExchangeRole -or $inputObject.MemberOfGroup.MailEnabled) {
            Write-Verbose "Connecting to Exchange"
            Connect-O365 -service exchange -ea Stop
        }
        #endregion connect

        if ($informNewManOwn) {
            $newManOwnReport = @()
        }
    }

    process {
        # check replacement user account
        if ($replaceByUser) {
            $replacementAADAccountObj = Get-MgUser -UserId $replaceByUser
            if (!$replacementAADAccountObj) {
                throw "Replacement account $replaceByUser was not found in AAD"
            } else {
                $replacementAADAccountId = $replacementAADAccountObj.Id
                $replacementAADAccountDisplayName = $replacementAADAccountObj.DisplayName

                Write-Warning "'$replacementAADAccountDisplayName' will be new manager/owner instead of account that is being removed"
            }
        }

        $inputObject | % {
            <#
            Object (as a output of Get-AzureAccountOccurrence) should have these properties:
                UPN
                DisplayName
                ObjectType
                ObjectId
                IAM
                MemberOfDirectoryRole
                MemberOfGroup
                PermissionConsent
                Owner
                SharepointSiteOwner
                AppUsersAndGroupsRoleAssignment
                KeyVaultAccessPolicy
                ExchangeRole
            #>

            $accountId = $_.ObjectId
            $accountDisplayName = $_.DisplayName

            "Processing cleanup on account '$accountDisplayName' ($accountId)"

            $AADAccountObj = Get-MgDirectoryObjectById -Ids $accountId
            if (!$AADAccountObj) {
                Write-Error "Account $accountId was not found in AAD"
            }

            if ($replaceByManager) {
                if ($_.ObjectType -eq 'user') {
                    $replacementAADAccountObj = Get-MgUserManager -UserId $accountId | Expand-MgAdditionalProperties # so the $replacementAADAccountObj have user properties at root level therefore looks same as when Get-MgUser is used (because of $replaceByUser)
                    if (!$replacementAADAccountObj) {
                        throw "Account '$accountDisplayName' doesn't have a manager. Specify replacement account via 'replaceByUser' parameter?"
                    } else {
                        $replacementAADAccountId = $replacementAADAccountObj.Id
                        $replacementAADAccountDisplayName = $replacementAADAccountObj.DisplayName

                        Write-Warning "User's manager '$replacementAADAccountDisplayName' will be new manager/owner instead of account that is being removed"
                    }
                } else {
                    Write-Warning "Account $accountId isn't a user ($($_.ObjectType)). Parameter 'replaceByManager' will be ignored."
                }
            }


            # prepare base object for storing data for later email notification
            if ($informNewManOwn -and $replacementAADAccountObj) {
                $newManOwnObj = [PSCustomObject]@{
                    replacedUserObjectId = $accountId
                    replacedUserName     = $accountDisplayName
                    newUserEmail         = $replacementAADAccountObj.mail
                    newUserName          = $replacementAADAccountDisplayName
                    newUserObjectId      = $replacementAADAccountId
                    message              = @()
                }
            }

            #region remove AAD account occurrences

            #region IAM
            if ($_.IAM) {
                Write-Verbose "Removing IAM assignments"
                $tenantId = (Get-AzContext).tenant.id

                $_.IAM | select ObjectId, AssignmentScope, RoleDefinitionName -Unique | % {
                    # $Context = Set-AzContext -TenantId $tenantId -SubscriptionId $_.SubscriptionId -Force
                    "Removing IAM role '$($_.RoleDefinitionName)' at scope '$($_.AssignmentScope)'"
                    if (!$whatIf) {
                        $lock = Get-AzResourceLock -Scope $_.AssignmentScope
                        if ($lock) {
                            Write-Warning "Unable to delete IAM role, because resource is LOCKED via '$($lock.name)' lock"
                        } else {
                            Remove-AzRoleAssignment -ObjectId $_.ObjectId -Scope $_.AssignmentScope -RoleDefinitionName $_.RoleDefinitionName
                        }
                    }
                }
            }
            #endregion IAM

            #region group membership
            if ($_.MemberOfGroup) {
                $_.MemberOfGroup | % {
                    if ($_.onPremisesSyncEnabled) {
                        Write-Warning "Skipping removal from group '$($_.displayName)' ($($_.id)), because it is synced from on-premises AD"
                    } elseif ($_.membershipRule) {
                        Write-Warning "Skipping removal from group '$($_.displayName)' ($($_.id)), because it has rule-based membership"
                    } else {
                        "Removing from group '$($_.displayName)' ($($_.id))"
                        if (!$whatIf) {
                            if ($_.mailEnabled -and !$_.groupTypes) {
                                # distribution group
                                Remove-DistributionGroupMember -Identity $_.id -Member $accountId -BypassSecurityGroupManagerCheck -Confirm:$false
                            } else {
                                # Microsoft 365 group
                                Remove-MgGroupMemberByRef -GroupId $_.id -DirectoryObjectId $accountId
                            }
                        }
                    }
                }
            }
            #endregion group membership

            #region membership directory role
            if ($_.MemberOfDirectoryRole) {
                $_.MemberOfDirectoryRole | % {
                    "Removing from directory role '$($_.displayName)' ($($_.id))"
                    if (!$whatIf) {
                        Remove-MgDirectoryRoleScopedMember -DirectoryRoleId $_.id -ScopedRoleMembershipId $accountId
                    }
                }
            }
            #endregion membership directory role

            #region user perm consents
            if ($_.PermissionConsent) {
                $_.PermissionConsent | % {
                    "Removing user consent from app '$($_.AppName)', permission '$($_.scope)' to '$($_.ResourceDisplayName)'"
                    if (!$whatIf) {
                        Remove-MgOauth2PermissionGrant -OAuth2PermissionGrantId $_.Id
                    }
                }
            }
            #endregion user perm consents

            #region manager
            if ($_.Manager) {
                $_.Manager | % {
                    $managerOf = $_
                    $managerOfObjectType = $managerOf.ObjectType
                    $managerOfDisplayName = $managerOf.DisplayName
                    $managerOfObjectId = $managerOf.Id

                    switch ($managerOfObjectType) {
                        User {
                            "Removing as a manager of the $managerOfObjectType '$managerOfDisplayName' ($managerOfObjectId)"
                            if (!$whatIf) {
                                Remove-MgUserManagerByRef -UserId $managerOfObjectId
                            }
                            if ($replacementAADAccountObj) {
                                "Adding '$replacementAADAccountDisplayName' as a manager of the $managerOfObjectType '$managerOfDisplayName' ($managerOfObjectId)"
                                if (!$whatIf) {
                                    $newManager = @{
                                        "@odata.id" = "https://graph.microsoft.com/v1.0/users/$replacementAADAccountId"
                                    }

                                    Set-MgUserManagerByRef -UserId $managerOfObjectId -BodyParameter $newManager

                                    if ($informNewManOwn) {
                                        $newManOwnObj.message += @("new manager of the $managerOfObjectType '$managerOfDisplayName' ($managerOfObjectId)")
                                    }
                                }
                            }
                        }

                        Contact {
                            "Removing as a manager of the $managerOfObjectType '$managerOfDisplayName' ($managerOfObjectId)"
                            if (!$whatIf) {
                                Write-Warning "Remove manager of the $managerOfObjectType '$managerOfDisplayName' ($managerOfObjectId) manually!"
                            }
                            if ($replacementAADAccountObj) {
                                Write-Warning "Add '$replacementAADAccountDisplayName' as a manager of the $managerOfObjectType '$managerOfDisplayName' ($managerOfObjectId) manually!"
                            }
                        }

                        default {
                            Write-Error "Not defined action for object type $managerOfObjectType. User won't be removed as a manager of this object."
                        }
                    }
                }
            }
            #endregion manager

            #region ownership
            # application, group, .. owner
            if ($_.Owner) {
                $_.Owner | % {
                    $ownerOf = $_
                    $ownerOfObjectType = $ownerOf.ObjectType
                    $ownerOfDisplayName = $ownerOf.DisplayName
                    $ownerOfObjectId = $ownerOf.Id

                    switch ($ownerOfObjectType) {
                        Application {
                            # app registration
                            "Removing owner from app registration '$ownerOfDisplayName'"
                            if (!$whatIf) {
                                $null = Remove-MgApplicationOwnerByRef -ApplicationId $ownerOfObjectId -DirectoryObjectId $accountId
                            }

                            if ($replacementAADAccountObj) {
                                $recentObjOwner = Get-MgApplicationOwner -ApplicationId $ownerOfObjectId -All | ? Id -NE $accountId
                                if (!$recentObjOwner) {
                                    "Adding '$replacementAADAccountDisplayName' as owner of the '$ownerOfDisplayName' application"
                                    if (!$whatIf) {
                                        $newOwner = @{
                                            "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$replacementAADAccountId"
                                        }
                                        New-MgApplicationOwnerByRef -ApplicationId $ownerOfObjectId -BodyParameter $NewOwner

                                        if ($informNewManOwn) {
                                            $appId = Get-MgApplication -ApplicationId $ownerOfObjectId | select -ExpandProperty AppId
                                            $url = "https://portal.azure.com/#blade/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/Overview/appId/$appId"
                                            $newManOwnObj.message += @("new owner of the '$ownerOfDisplayName' application ($url)")
                                        }
                                    }
                                } else {
                                    Write-Warning "App registration has some owners left. '$replacementAADAccountDisplayName' won't be added."
                                }
                            }
                        }

                        ServicePrincipal {
                            # enterprise apps owner
                            "Removing owner from service principal '$ownerOfDisplayName'"
                            if (!$whatIf) {
                                Remove-MgServicePrincipalOwnerByRef -ServicePrincipalId $ownerOfObjectId -DirectoryObjectId $accountId
                            }

                            if ($replacementAADAccountObj) {
                                $recentObjOwner = Get-MgServicePrincipalOwner -ServicePrincipalId $ownerOfObjectId -All | ? Id -NE $accountId
                                if (!$recentObjOwner) {
                                    "Adding '$replacementAADAccountDisplayName' as owner of the '$ownerOfDisplayName' service principal"
                                    if (!$whatIf) {
                                        $newOwner = @{
                                            "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/{$replacementAADAccountId}"
                                        }
                                        New-MgServicePrincipalOwnerByRef -ServicePrincipalId $ownerOfObjectId -BodyParameter $newOwner

                                        if ($informNewManOwn) {
                                            $appId = Get-MgServicePrincipal -ServicePrincipalId $ownerOfObjectId | select -ExpandProperty AppId
                                            $url = "https://portal.azure.com/#blade/Microsoft_AAD_IAM/ManagedAppMenuBlade/Overview/objectId/$ownerOfObjectId/appId/$appId"
                                            $newManOwnObj.message += @("new owner of the '$ownerOfDisplayName' service principal ($url)")
                                        }
                                    }
                                } else {
                                    Write-Warning "Service principal has some owners left. '$replacementAADAccountDisplayName' won't be added."
                                }
                            }
                        }

                        Group {
                            # adding new owner before removing the old one because group won't let you remove last owner
                            if ($replacementAADAccountObj) {
                                $recentObjOwner = Get-MgGroupOwner -GroupId $ownerOfObjectId -All | ? Id -NE $accountId
                                if (!$recentObjOwner) {
                                    "Adding '$replacementAADAccountDisplayName' as owner of the '$ownerOfDisplayName' group"
                                    if (!$whatIf) {
                                        $newOwner = @{
                                            "@odata.id" = "https://graph.microsoft.com/v1.0/users/{$replacementAADAccountId}"
                                        }
                                        New-MgGroupOwnerByRef -GroupId $ownerOfObjectId -BodyParameter $newOwner

                                        if ($informNewManOwn) {
                                            $url = "https://portal.azure.com/#blade/Microsoft_AAD_IAM/GroupDetailsMenuBlade/Overview/groupId/$ownerOfObjectId"
                                            $newManOwnObj.message += @("new owner of the '$ownerOfDisplayName' group ($url)")
                                        }
                                    }
                                } else {
                                    Write-Warning "Group has some owners left. '$replacementAADAccountDisplayName' won't be added."
                                }
                            }

                            "Removing owner from group '$ownerOfDisplayName'"
                            if (!$whatIf) {
                                Remove-MgGroupOwnerByRef -GroupId $ownerOfObjectId -DirectoryObjectId $accountId
                            }
                        }

                        Device {
                            if ($ownerOf.DeviceTrustType -eq 'Workplace') {
                                # registered device
                                if ($removeRegisteredDevice) {
                                    "Removing registered device '$ownerOfDisplayName' ($ownerOfObjectId)"
                                    if (!$whatIf) {
                                        Remove-MgDevice -DeviceId $ownerOfObjectId
                                    }
                                } else {
                                    Write-Warning "Registered device '$ownerOfDisplayName' won't be deleted nor owner of this device will be removed"
                                }
                            } else {
                                # joined device
                                "Removing owner from device '$ownerOfDisplayName' ($ownerOfObjectId)"
                                if (!$whatIf) {
                                    Remove-MgDeviceRegisteredOwnerByRef -DeviceId $ownerOfObjectId -DirectoryObjectId $accountId
                                }
                            }

                            if ($replacementAADAccountObj) {
                                Write-Verbose "Device owner won't be replaced by '$replacementAADAccountDisplayName' because I don't want to"
                            }
                        }

                        default {
                            Write-Error "Not defined action for object type $ownerOfObjectType. User won't be removed as a owner of this object."
                        }
                    }
                }
            }

            # sharepoint sites owner
            if ($_.SharepointSiteOwner) {
                $_.SharepointSiteOwner | % {
                    if ($_.template -like 'GROUP*') {
                        # it is sharepoint site based on group (owners are group members)
                        "Removing from group '$($_.Title)' that has owner rights on Sharepoint site '$($_.Site)'"
                        if (!$whatIf) {
                            Remove-PnPMicrosoft365GroupOwner -Identity $_.GroupId -Users $userPrincipalName
                        }

                        if ($replacementAADAccountObj) {
                            $recentObjOwner = Get-PnPMicrosoft365GroupOwner -Identity $_.GroupId -All:$true | ? Id -NE $accountId
                            if (!$recentObjOwner) {
                                "Adding '$replacementAADAccountDisplayName' as owner of the '$($_.Title)' group"
                                if (!$whatIf) {
                                    Add-PnPMicrosoft365GroupOwner -Identity $_.GroupId -Users $replacementAADAccountObj.UserPrincipalName

                                    if ($informNewManOwn) {
                                        $url = "https://portal.azure.com/#blade/Microsoft_AAD_IAM/GroupDetailsMenuBlade/Overview/groupId/$($_.GroupId)"
                                        $newManOwnObj.message += @("new owner of the '$($_.Title)' group ($url)")
                                    }
                                }
                            } else {
                                Write-Warning "Sharepoint site has some owners left. '$replacementAADAccountDisplayName' won't be added."
                            }
                        }
                    } else {
                        # it is common sharepoint site
                        Write-Warning "Remove owner from Sharepoint site '$($_.site)' manually!"
                        # "Removing from sharepoint site '$($_.site)'"
                        # https://www.sharepointdiary.com/2018/02/change-site-owner-in-sharepoint-online-using-powershell.html
                        # https://www.sharepointdiary.com/2020/05/sharepoint-online-grant-site-owner-permission-to-user-with-powershell.html

                        if ($replacementAADAccountObj) {
                            Write-Warning "Add '$($replacementAADAccountObj.UserPrincipalName)' as new owner at Sharepoint site '$($_.site)' manually!"
                            # "Adding '$replacementAADAccountDisplayName' as owner of the '$($_.site)' sharepoint site"
                            # Set-SPOSite https://contoso.sharepoint.com/sites/otest_communitysite_test_smazani -Owner admin@contoso.com # zda se ze funguje, ale vyzaduje Connect-SPOService -Url $_SPOConnectionUri
                            # Set-PnPSite -Identity $_.site -Owners $replacementAADAccountObj.UserPrincipalName # prida jen jako admina..ne primary admina (ownera)
                            # Set-PnPTenantSite -Identity $_.site -Owners $replacementAADAccountObj.UserPrincipalName # prida jen jako admina..ne primary admina (ownera)
                        }
                    }
                }
            }
            #endregion ownership

            #region app Users and groups role assignments
            if ($_.AppUsersAndGroupsRoleAssignment) {
                $_.AppUsersAndGroupsRoleAssignment | % {
                    "Removing $($_.PrincipalType) from app's '$($_.ResourceDisplayName)' role '$($_.AppRoleDisplayName)'"
                    if (!$whatIf) {
                        Remove-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $_.ResourceId -AppRoleAssignmentId $_.Id
                    }
                }
            }
            #endregion app Users and groups role assignments

            #region devops
            if ($_.DevOpsOrganizationOwner) {
                $_.DevOpsOrganizationOwner | % {
                    Write-Warning "Remove owner of DevOps organization '$($_.OrganizationName))' manually!"
                    if ($replacementAADAccountObj) {
                        Write-Warning "Add '$($replacementAADAccountObj.UserPrincipalName)' as new owner of the DevOps organization '$($_.OrganizationName))' manually!"
                    }
                }
            }

            if ($_.DevOpsMemberOf) {
                $header = New-AzureDevOpsAuthHeader

                $_.DevOpsMemberOf | % {
                    $accountDescriptor = $_.Descriptor
                    $organizationName = $_.OrganizationName
                    $_.memberOf | % {
                        $groupDescriptor = $_.descriptor
                        "Removing from DevOps organization's '$organizationName' group '$($_.principalName)'"

                        if (!$whatIf) {
                            $result = Invoke-WebRequest -Uri "https://vssps.dev.azure.com/$organizationName/_apis/graph/memberships/$accountDescriptor/$($groupDescriptor)?api-version=7.1-preview.1" -Method delete -ContentType "application/json" -Headers $header
                            if ($result.StatusCode -ne 200) {
                                Write-Error "Removal of account '$accountDisplayName' in DevOps organization '$organizationName' from group '$($_.displayName)' wasn't successful. Do it manually!"
                            }
                        }
                    }
                }
            }
            #endregion devops

            #region keyVaultAccessPolicy
            if ($_.KeyVaultAccessPolicy) {
                $_.KeyVaultAccessPolicy | % {
                    $vaultName = $_.VaultName
                    $removedObjectId = $_.AccessPolicies.ObjectId | select -Unique
                    "Removing Access from KeyVault $vaultName for '$removedObjectId'"

                    if (!$whatIf) {
                        Remove-AzKeyVaultAccessPolicy -VaultName $vaultName -ObjectId $removedObjectId -WarningAction SilentlyContinue
                    }
                }
            }
            #endregion keyVaultAccessPolicy

            #region exchangeRole
            if ($_.ExchangeRole) {
                $_.ExchangeRole | % {
                    $roleName = $_.name
                    $roleDN = $_.RoleDisplayName
                    if ($_.capabilities -eq 'Partner_Managed') {
                        Write-Warning "Skipping removal of account '$($_.Identity)' from Exchange role $roleName. Role is not managed by Exchange, but via some external entity"
                    } else {
                        "Removing account '$($_.Identity)' from Exchange role '$roleName' ($roleDN)"

                        if (!$whatIf) {
                            Remove-RoleGroupMember -Confirm:$false -Identity $roleName -Member $_.Identity -BypassSecurityGroupManage
                            rCheck
                        }
                    }
                }
            }
            #endregion exchangeRole

            #endregion remove AAD account occurrences

            # save object with made changes for later email notification
            if ($informNewManOwn -and $replacementAADAccountObj) {
                $newManOwnReport += $newManOwnObj
            }
        }
    }

    end {
        if ($informNewManOwn -and $newManOwnReport.count) {
            $newManOwnReport | % {
                if ($_.message) {
                    # there were some changes in ownership
                    if ($_.newUserEmail) {
                        # new owner/manager has email address defined
                        if ($replaceByManager) {
                            $newUserRole = "as his/her manager"
                        } else {
                            $newUserRole = "as chosen successor"
                        }

                        $body = "Hi,`nemployee '$($_.replacedUserName)' left the company and you $newUserRole are now:`n`n$(($_.message | % {" - $_"}) -join "`n")`n`nThese changes are related to Azure environment.`n`n`Sincerely your IT"

                        Write-Warning "Sending email to: $($_.newUserEmail) body:`n`n$body"
                        Send-Email -to $_.newUserEmail -subject "Notification of new Azure assets responsibility" -body $body
                    } else {
                        Write-Warning "Cannot inform new owner/manager '$($_.newUserName)' about transfer of Azure asset from '$($_.replacedUserName)'. Email address is missing.`n`n$($_.message -join "`n")"
                    }
                } else {
                    Write-Verbose "No asset was transferred to the '$($_.newUserName)' from the '$($_.replacedUserName)'"
                }
            }
        }
    }
}