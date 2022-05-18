function Remove-AzureADAccountOccurrence {
    <#
    .SYNOPSIS
    Function for removal of selected AAD account occurrences in various parts of AAD.

    .DESCRIPTION
    Function for removal of selected AAD account occurrences in various parts of AAD.

    .PARAMETER inputObject
    PSCustomObject that is outputted by Get-AzureADAccountOccurrence function.
    Contains information about account and its occurrences i.e. is used in this function as information about what to remove and from where.

    Object (as a output of Get-AzureADAccountOccurrence) should have these properties:
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
    Get-AzureADAccountOccurrence -userPrincipalName pavel@contoso.com | Remove-AzureADAccountOccurrence -whatIf

    Get all occurrences of specified user and just output what would be done with them.

    .EXAMPLE
    Get-AzureADAccountOccurrence -userPrincipalName pavel@contoso.com | Remove-AzureADAccountOccurrence

    Get all occurrences of specified user and remove them.
    In case user has registered some devices, they stay intact.

    .EXAMPLE
    Get-AzureADAccountOccurrence -userPrincipalName pavel@contoso.com | Remove-AzureADAccountOccurrence -removeRegisteredDevice

    Get all occurrences of specified user and remove them.
    In case user has registered some devices, they will be deleted.

    .EXAMPLE
    Get-AzureADAccountOccurrence -userPrincipalName pavel@contoso.com | Remove-AzureADAccountOccurrence -replaceByUser 1234-1234-1234-1234

    Get all occurrences of specified user and remove them.
    In case user is owner or manager on some object(s) he will be replaced there by specified user (for ownerships this apply only if removed user is last owner).
    In case user has registered some devices, they stay intact.

    .EXAMPLE
    Get-AzureADAccountOccurrence -userPrincipalName pavel@contoso.com | Remove-AzureADAccountOccurrence -replaceByManager

    Get all occurrences of specified user and remove them.
    In case user is owner or manager on some object(s) he will be replaced there by his manager (for ownerships this apply only if removed user is last owner).
    In case user has registered some devices, they stay intact.
    #>

    [CmdletBinding()]
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
        $null = Connect-AzureAD2 -asYourself -ea Stop

        Write-Verbose "Connecting to AzAccount"
        $null = Connect-AzAccount2 -ea Stop

        # connect sharepoint online
        if ($inputObject.SharepointSiteOwner) {
            Write-Verbose "Connecting to Sharepoint"
            Connect-PnPOnline2 -asMFAUser -ea Stop
        }
        #endregion connect

        if ($informNewManOwn) {
            $newManOwnReport = @()
        }
    }

    process {
        # check replacement user account
        if ($replaceByUser) {
            $replacementAADAccountObj = Get-AzureADUser -ObjectId $replaceByUser
            if (!$replacementAADAccountObj) {
                throw "Replacement account $replaceByUser was not found in AAD"
            } else {
                Write-Warning "'$($replacementAADAccountObj.DisplayName)' will be new manager/owner instead of account that is being removed"
            }
        }

        $inputObject | % {
            <#
            Object (as a output of Get-AzureADAccountOccurrence) should have these properties:
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
            #>

            $accountId = $_.ObjectId
            $accountDisplayName = $_.DisplayName

            "Processing cleanup on account '$accountDisplayName' ($accountId)"

            $AADAccountObj = Get-AzureADObjectByObjectId -ObjectId $accountId
            if (!$AADAccountObj) {
                Write-Error "Account $accountId was not found in AAD"
            }

            if ($replaceByManager) {
                if ($_.ObjectType -eq 'user') {
                    $replacementAADAccountObj = Get-AzureADUserManager -ObjectId $accountId
                    if (!$replacementAADAccountObj) {
                        throw "Account '$accountDisplayName' doesn't have a manager. Specify replacement account via 'replaceByUser' parameter?"
                    } else {
                        Write-Warning "User's manager '$($replacementAADAccountObj.DisplayName)' will be new manager/owner instead of account that is being removed"
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
                    newUserName          = $replacementAADAccountObj.DisplayName
                    newUserObjectId      = $replacementAADAccountObj.ObjectId
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
                        Remove-AzRoleAssignment -ObjectId $_.ObjectId -Scope $_.AssignmentScope -RoleDefinitionName $_.RoleDefinitionName
                    }
                }
            }
            #endregion IAM

            #region group membership
            if ($_.MemberOfGroup) {
                $_.MemberOfGroup | % {
                    "Removing from group '$($_.displayName)' ($($_.id))"
                    if (!$whatIf) {
                        Remove-AzureADGroupMember -ObjectId $_.id -MemberId $accountId
                    }
                }
            }
            #endregion group membership

            #region membership directory role
            if ($_.MemberOfDirectoryRole) {
                $_.MemberOfDirectoryRole | % {
                    "Removing from directory role '$($_.displayName)' ($($_.id))"
                    if (!$whatIf) {
                        Remove-AzureADDirectoryRoleMember -ObjectId $_.id -MemberId $accountId
                    }
                }
            }
            #endregion membership directory role

            #region user perm consents
            if ($_.PermissionConsent) {
                $_.PermissionConsent | % {
                    "Removing user consent from app '$($_.AppName)', permission '$($_.scope)' to '$($_.ResourceDisplayName)'"
                    if (!$whatIf) {
                        Remove-AzureADOAuth2PermissionGrant -ObjectId $_.ObjectId
                    }
                }
            }
            #endregion user perm consents

            #region manager
            if ($_.Manager) {
                $_.Manager | % {
                    $manager = $_
                    $managerObjectType = $_.ObjectType
                    $managerDisplayName = $_.DisplayName
                    $managerObjectId = $_.ObjectId

                    switch ($manager.ObjectType) {
                        User {
                            "Removing as a manager of the $managerObjectType '$managerDisplayName' ($managerObjectId)"
                            if (!$whatIf) {
                                Remove-AzureADUserManager -ObjectId $managerObjectId
                            }
                            if ($replacementAADAccountObj) {
                                "Adding '$($replacementAADAccountObj.DisplayName)' as a manager of the $managerObjectType '$managerDisplayName' ($managerObjectId)"
                                if (!$whatIf) {
                                    Set-AzureADUserManager -ObjectId $managerObjectId -RefObjectId $replacementAADAccountObj.ObjectId

                                    if ($informNewManOwn) {
                                        $newManOwnObj.message += @("new manager of the $managerObjectType '$managerDisplayName' ($managerObjectId)")
                                    }
                                }
                            }
                        }

                        Contact {
                            "Removing as a manager of the $managerObjectType '$managerDisplayName' ($managerObjectId)"
                            if (!$whatIf) {
                                Remove-AzureADContactManager -ObjectId $managerObjectId
                            }
                            if ($replacementAADAccountObj) {
                                Write-Warning "Add '$($replacementAADAccountObj.DisplayName)' as a manager of the $managerObjectType '$managerDisplayName' ($managerObjectId) manually!"
                            }
                        }

                        default {
                            Write-Error "Not defined action for object type $managerObjectType. User won't be removed as a manager of this object."
                        }
                    }
                }
            }
            #endregion manager

            #region ownership
            # application, group, .. owner
            if ($_.Owner) {
                $_.Owner | % {
                    $owner = $_
                    $ownerDisplayName = $_.DisplayName
                    $ownerObjectId = $_.ObjectId

                    switch ($owner.ObjectType) {
                        Application {
                            # app registration
                            "Removing owner from app registration '$ownerDisplayName'"
                            if (!$whatIf) {
                                Remove-AzureADApplicationOwner -ObjectId $ownerObjectId -OwnerId $accountId
                            }

                            if ($replacementAADAccountObj) {
                                $recentObjOwner = Get-AzureADApplicationOwner -ObjectId $ownerObjectId -All:$true | ? ObjectId -NE $accountId
                                if (!$recentObjOwner) {
                                    "Adding '$($replacementAADAccountObj.DisplayName)' as owner of the '$ownerDisplayName' application"
                                    if (!$whatIf) {
                                        Add-AzureADApplicationOwner -ObjectId $ownerObjectId -RefObjectId $replacementAADAccountObj.ObjectId

                                        if ($informNewManOwn) {
                                            $newManOwnObj.message += @("new owner of the '$ownerDisplayName' application ($ownerObjectId)")
                                        }
                                    }
                                } else {
                                    Write-Warning "App registration has some owners left. '$($replacementAADAccountObj.DisplayName)' won't be added."
                                }
                            }
                        }

                        ServicePrincipal {
                            # enterprise apps owner
                            "Removing owner from service principal '$ownerDisplayName'"
                            if (!$whatIf) {
                                Remove-AzureADServicePrincipalOwner -ObjectId $ownerObjectId -OwnerId $accountId
                            }

                            if ($replacementAADAccountObj) {
                                $recentObjOwner = Get-AzureADServicePrincipalOwner -ObjectId $ownerObjectId -All:$true | ? ObjectId -NE $accountId
                                if (!$recentObjOwner) {
                                    "Adding '$($replacementAADAccountObj.DisplayName)' as owner of the '$ownerDisplayName' service principal"
                                    if (!$whatIf) {
                                        Add-AzureADServicePrincipalOwner -ObjectId $ownerObjectId -RefObjectId $replacementAADAccountObj.ObjectId

                                        if ($informNewManOwn) {
                                            $newManOwnObj.message += @("new owner of the '$ownerDisplayName' service principal ($ownerObjectId)")
                                        }
                                    }
                                } else {
                                    Write-Warning "Service principal has some owners left. '$($replacementAADAccountObj.DisplayName)' won't be added."
                                }
                            }
                        }

                        Group {
                            # adding new owner before removing the old one because group won't let you remove last owner
                            if ($replacementAADAccountObj) {
                                $recentObjOwner = Get-AzureADGroupOwner -ObjectId $ownerObjectId -All:$true | ? ObjectId -NE $accountId
                                if (!$recentObjOwner) {
                                    "Adding '$($replacementAADAccountObj.DisplayName)' as owner of the '$ownerDisplayName' group"
                                    if (!$whatIf) {
                                        Add-AzureADGroupOwner -ObjectId $ownerObjectId -RefObjectId $replacementAADAccountObj.ObjectId

                                        if ($informNewManOwn) {
                                            $newManOwnObj.message += @("new owner of the '$ownerDisplayName' group ($ownerObjectId)")
                                        }
                                    }
                                } else {
                                    Write-Warning "Group has some owners left. '$($replacementAADAccountObj.DisplayName)' won't be added."
                                }
                            }

                            "Removing owner from group '$ownerDisplayName'"
                            if (!$whatIf) {
                                Remove-AzureADGroupOwner -ObjectId $ownerObjectId -OwnerId $accountId
                            }
                        }

                        Device {
                            if ($owner.DeviceTrustType -eq 'Workplace') {
                                # registered device
                                if ($removeRegisteredDevice) {
                                    "Removing registered device '$ownerDisplayName' ($ownerObjectId)"
                                    if (!$whatIf) {
                                        Remove-AzureADDevice -ObjectId $ownerObjectId
                                    }
                                } else {
                                    Write-Warning "Registered device '$ownerDisplayName' won't be deleted nor owner of this device will be removed"
                                }
                            } else {
                                # joined device
                                "Removing owner from device '$ownerDisplayName' ($ownerObjectId)"
                                if (!$whatIf) {
                                    Remove-AzureADDeviceRegisteredOwner -ObjectId $ownerObjectId -OwnerId $accountId
                                }
                            }

                            if ($replacementAADAccountObj) {
                                Write-Verbose "Device owner won't be replaced by '$($replacementAADAccountObj.DisplayName)' because I don't want to"
                            }
                        }

                        default {
                            Write-Error "Not defined action for object type $($owner.ObjectType). User won't be removed as a owner of this object."
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
                                "Adding '$($replacementAADAccountObj.DisplayName)' as owner of the '$($_.Title)' group"
                                if (!$whatIf) {
                                    Add-PnPMicrosoft365GroupOwner -Identity $_.GroupId -Users $replacementAADAccountObj.UserPrincipalName

                                    if ($informNewManOwn) {
                                        $newManOwnObj.message += @("new owner of the '$($_.Title)' group ($($_.GroupId))")
                                    }
                                }
                            } else {
                                Write-Warning "Sharepoint site has some owners left. '$($replacementAADAccountObj.DisplayName)' won't be added."
                            }
                        }
                    } else {
                        # it is common sharepoint site
                        Write-Warning "Remove owner from Sharepoint site '$($_.url)' manually"
                        # "Removing from sharepoint site '$($_.url)'"
                        # https://www.sharepointdiary.com/2018/02/change-site-owner-in-sharepoint-online-using-powershell.html
                        # https://www.sharepointdiary.com/2020/05/sharepoint-online-grant-site-owner-permission-to-user-with-powershell.html

                        if ($replacementAADAccountObj) {
                            Write-Warning "Add '$($replacementAADAccountObj.UserPrincipalName)' as new owner at Sharepoint site '$($_.url)' manually"
                            # "Adding '$($replacementAADAccountObj.DisplayName)' as owner of the '$($_.url)' sharepoint site"
                            # Set-PnPSite -Identity $_.url -Owners $replacementAADAccountObj.UserPrincipalName # prida jen jako admina..ne primary admina (ownera)
                            # Set-PnPTenantSite -Identity $_.url -Owners $replacementAADAccountObj.UserPrincipalName # prida jen jako admina..ne primary admina (ownera)
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
                        Remove-AzureADServiceAppRoleAssignment -ObjectId $_.ResourceId -AppRoleAssignmentId $_.ObjectId
                    }
                }
            }
            #endregion app Users and groups role assignments

            #region devops
            if ($_.DevOpsOrganizationOwner) {
                $_.DevOpsOrganizationOwner | % {
                    Write-Warning "Remove owner of DevOps organization '$($_.OrganizationName))' manually"
                    if ($replacementAADAccountObj) {
                        Write-Warning "Add '$($replacementAADAccountObj.UserPrincipalName)' as new owner of the DevOps organization '$($_.OrganizationName))' manually"
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
                                Write-Error "Removal of account '$accountDisplayName' in DevOps organization '$organizationName' from group '$($_.displayName)' wasn't successful. Do it manually."
                            }
                        }
                    }
                }
            }
            #endregion devops

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
                        $newUserRole = "as chosen successor"
                        if ($replaceByManager -or ((Get-AzureADUserManager -ObjectId $_.replacedUserObjectId).ObjectId -eq $_.newUserObjectId)) {
                            $newUserRole = "as his/her manager"
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