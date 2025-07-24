function Get-PIMAccountEligibleMemberOf {
    <#
    .SYNOPSIS
    Function returns groups where selected account(s) is eligible (via PIM) as a member.

    .DESCRIPTION
    Function returns groups where selected account(s) is eligible (via PIM) as a member.

    .PARAMETER id
    Object ID of the account(s) you want to process.

    .PARAMETER transitive
    Switch to return not just direct PIM groups where processed account is member of, but also do the same for the PIM groups recursively.

    .PARAMETER onlyMembers
    Switch to return just list of groups processed account is member of.
    Not the object with 'Id', 'MemberOf' properties.

    .PARAMETER PIMGroupList
    List of PIM groups and their eligible assignments.
    Can be retrieved via Get-PIMGroup.
    Used internally for recursive function calls.

    .PARAMETER includePermanentMembership
    Switch to include non-PIM groups in the output.
    Account can be eligible member of PIM group A, and such group can be permanent member of ordinary group B and eligible member of PIM group C. With this switch A, B and C will be returned instead of just A and C.

    .EXAMPLE
    Get-PIMAccountEligibleMemberOf -id 877f3913-cb92-4a2d-af33-4b20efb50e54, 9048d9ba-59d1-451b-8764-88b034612fd9

    Get PIM groups where selected accounts are direct members.

    .EXAMPLE
    Get-PIMAccountEligibleMemberOf -id 877f3913-cb92-4a2d-af33-4b20efb50e54, 9048d9ba-59d1-451b-8764-88b034612fd9 -transitive

    Get PIM groups where selected accounts are members (direct or indirect via another PIM group).
    #>

    [Alias("Get-AzureAccountEligibleMemberOf")]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [guid[]] $id,

        [switch] $transitive,

        [switch] $onlyMembers,

        [switch] $includePermanentMembership,

        $PIMGroupList
    )

    #region checks
    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-MgGraph."
    }

    if ($id.count -gt 1 -and $onlyMembers) {
        Write-Warning "All groups given accounts are member of will be outputted at once"
    }

    if ($includePermanentMembership -and !$transitive) {
        Write-Error "'includePermanentMembership' can be used only with the 'transitive'"
    }
    #endregion checks

    if (!$PIMGroupList) {
        $PIMGroupList = Get-PIMGroup
    }

    # no PIM group exist, exit
    if (!$PIMGroupList) {
        if ($onlyMembers) {
            return
        } else {
            $id | % {
                [PSCustomObject]@{
                    Id       = $_
                    MemberOf = $null
                }
            }

            return
        }
    }

    foreach ($accountId in $id) {
        [System.Collections.Generic.List[object]] $memberOf = @()

        # get PIM groups where account in question is eligible as a member
        $PIMGroupList | ? { $_.EligibleAssignment.AccessId -eq 'member' -and $_.EligibleAssignment.PrincipalId -eq $accountId } | % {
            Write-Verbose "Account $accountId is eligible member of the group $($_.Id)"
            $memberOf.Add($_)
        }

        # get PIM groups where groups account in question is eligible as a member are also eligible as members for other PIM groups
        if ($transitive -and $memberOf.Id) {
            Write-Verbose "Getting eligible memberof recursively for group(s): $($memberOf.Id -join ', ')"

            Get-PIMAccountEligibleMemberOf -id $memberOf.Id -transitive -onlyMembers -PIMGroupList $PIMGroupList -includePermanentMembership:$includePermanentMembership -Verbose:$VerbosePreference | % {
                $memberOf.Add($_)
            }

            if ($includePermanentMembership) {
                Write-Verbose "Getting permanent memberof recursively for group(s): $($memberOf.Id -join ', ')"

                Get-AzureDirectoryObjectMemberOf -id $memberOf.Id -Verbose:$VerbosePreference | % {
                    $memberOf.Add($_.MemberOf)
                }
            }
        }

        if ($onlyMembers) {
            $memberOf
        } else {
            [PSCustomObject]@{
                Id       = $accountId
                MemberOf = $memberOf
            }
        }
    }
}

function Get-PIMDirectoryRoleAssignmentSetting {
    <#
    .SYNOPSIS
    Gets PIM assignment settings for a given Azure AD directory role.

    .DESCRIPTION
    This function retrieves Privileged Identity Management (PIM) policy assignment settings for a specified Azure AD directory role, including activation duration, enablement rules, approval requirements, notification settings, and more. You can specify the role by name or ID.

    .PARAMETER roleName
    The display name of the Azure AD directory role to query. Mandatory if using the roleName parameter set.

    .PARAMETER roleId
    The object ID of the Azure AD directory role to query. Mandatory if using the roleId parameter set.

    .EXAMPLE
    Get-PIMDirectoryRoleAssignmentSetting -roleName "Global Administrator"
    Retrieves PIM assignment settings for the Global Administrator role.

    .EXAMPLE
    Get-PIMDirectoryRoleAssignmentSetting -roleId "12345678-aaaa-bbbb-cccc-1234567890ab"
    Retrieves PIM assignment settings for the specified role ID.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "roleName")]
        [string] $roleName,

        [Parameter(Mandatory = $true, ParameterSetName = "roleId")]
        [string] $roleId
    )

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-MgGraph."
    }

    if ($roleName) {
        $response = Invoke-MgGraphRequest -Uri "v1.0/roleManagement/directory/roleDefinitions?`$filter=displayname eq '$roleName'" | Get-MgGraphAllPages
        $roleID = $response.Id
        Write-Verbose "roleID = $roleID"
        if (!$roleID) {
            throw "Role $roleName not found. Search is CASE SENSITIVE!"
        }
    }

    # get PIM policyID for that role
    $response = Invoke-MgGraphRequest -Uri "v1.0/policies/roleManagementPolicyAssignments?`$filter=scopeType eq 'DirectoryRole' and roleDefinitionId eq '$roleID' and scopeId eq '/' " | Get-MgGraphAllPages
    $policyID = $response.policyID
    Write-Verbose "policyID = $policyID"

    # get the rules
    $response = Invoke-MgGraphRequest -Uri "v1.0/policies/roleManagementPolicies/$policyID/rules" | Get-MgGraphAllPages

    # Maximum end user activation duration in Hour (PT24H) // Max 24H in portal but can be greater
    $_activationDuration = $($response | Where-Object { $_.id -eq "Expiration_EndUser_Assignment" }).maximumDuration # | Select-Object -ExpandProperty maximumduration
    # End user enablement rule (MultiFactorAuthentication, Justification, Ticketing)
    $_enablementRules = $($response | Where-Object { $_.id -eq "Enablement_EndUser_Assignment" }).enabledRules
    # Active assignment requirement
    $_activeAssignmentRequirement = $($response | Where-Object { $_.id -eq "Enablement_Admin_Assignment" }).enabledRules
    # Authentication context
    $_authenticationContext_Enabled = $($response | Where-Object { $_.id -eq "AuthenticationContext_EndUser_Assignment" }).isEnabled
    $_authenticationContext_value = $($response | Where-Object { $_.id -eq "AuthenticationContext_EndUser_Assignment" }).claimValue

    # approval required
    $_approvalrequired = $($response | Where-Object { $_.id -eq "Approval_EndUser_Assignment" }).setting.isapprovalrequired
    # approvers
    $approvers = $($response | Where-Object { $_.id -eq "Approval_EndUser_Assignment" }).setting.approvalStages.primaryApprovers
    if (( $approvers | Measure-Object | Select-Object -ExpandProperty Count) -gt 0) {
        $approvers | ForEach-Object {
            if ($_."@odata.type" -eq "#microsoft.graph.groupMembers") {
                $_.userType = "group"
                $_.id = $_.groupID
            } else {
                #"@odata.type": "#microsoft.graph.singleUser",
                $_.userType = "user"
                $_.id = $_.userID
            }

            $_approvers += '@{"id"="' + $_.id + '";"description"="' + $_.description + '";"userType"="' + $_.userType + '"},'
        }
    }

    # permanent assignmnent eligibility
    $_eligibilityExpirationRequired = $($response | Where-Object { $_.id -eq "Expiration_Admin_Eligibility" }).isExpirationRequired
    if ($_eligibilityExpirationRequired -eq "true") {
        $_permanentEligibility = "false"
    } else {
        $_permanentEligibility = "true"
    }
    # maximum assignment eligibility duration
    $_maxAssignmentDuration = $($response | Where-Object { $_.id -eq "Expiration_Admin_Eligibility" }).maximumDuration

    # permanent activation
    $_activeExpirationRequired = $($response | Where-Object { $_.id -eq "Expiration_Admin_Assignment" }).isExpirationRequired
    if ($_activeExpirationRequired -eq "true") {
        $_permanentActiveAssignment = "false"
    } else {
        $_permanentActiveAssignment = "true"
    }
    # maximum activation duration
    $_maxActiveAssignmentDuration = $($response | Where-Object { $_.id -eq "Expiration_Admin_Assignment" }).maximumDuration

    # Notification Eligibility Alert (Send notifications when members are assigned as eligible to this role)
    $_Notification_Admin_Admin_Eligibility = $response | Where-Object { $_.id -eq "Notification_Admin_Admin_Eligibility" }
    # Notification Eligibility Assignee (Send notifications when members are assigned as eligible to this role: Notification to the assigned user (assignee))
    $_Notification_Eligibility_Assignee = $response | Where-Object { $_.id -eq "Notification_Requestor_Admin_Eligibility" }
    # Notification Eligibility Approvers (Send notifications when members are assigned as eligible to this role: request to approve a role assignment renewal/extension)
    $_Notification_Eligibility_Approvers = $response | Where-Object { $_.id -eq "Notification_Approver_Admin_Eligibility" }

    # Notification Active Assignment Alert (Send notifications when members are assigned as active to this role)
    $_Notification_Active_Alert = $response | Where-Object { $_.id -eq "Notification_Admin_Admin_Assignment" }
    # Notification Active Assignment Assignee (Send notifications when members are assigned as active to this role: Notification to the assigned user (assignee))
    $_Notification_Active_Assignee = $response | Where-Object { $_.id -eq "Notification_Requestor_Admin_Assignment" }
    # Notification Active Assignment Approvers (Send notifications when members are assigned as active to this role: Request to approve a role assignment renewal/extension)
    $_Notification_Active_Approvers = $response | Where-Object { $_.id -eq "Notification_Approver_Admin_Assignment" }

    # Notification Role Activation Alert (Send notifications when eligible members activate this role: Role activation alert)
    $_Notification_Activation_Alert = $response | Where-Object { $_.id -eq "Notification_Admin_EndUser_Assignment" }
    # Notification Role Activation Assignee (Send notifications when eligible members activate this role: Notification to activated user (requestor))
    $_Notification_Activation_Assignee = $response | Where-Object { $_.id -eq "Notification_Requestor_EndUser_Assignment" }
    # Notification Role Activation Approvers (Send notifications when eligible members activate this role: Request to approve an activation)
    $_Notification_Activation_Approver = $response | Where-Object { $_.id -eq "Notification_Approver_EndUser_Assignment" }


    [PSCustomObject]@{
        RoleName                                                     = $roleName
        RoleID                                                       = $roleID
        PolicyID                                                     = $policyId
        ActivationDuration                                           = $_activationDuration
        EnablementRules                                              = $_enablementRules -join ','
        ActiveAssignmentRequirement                                  = $_activeAssignmentRequirement -join ','
        AuthenticationContext_Enabled                                = $_authenticationContext_Enabled
        AuthenticationContext_Value                                  = $_authenticationContext_value
        ApprovalRequired                                             = $_approvalrequired
        Approvers                                                    = $_approvers -join ','
        AllowPermanentEligibleAssignment                             = $_permanentEligibility
        MaximumEligibleAssignmentDuration                            = $_maxAssignmentDuration
        AllowPermanentActiveAssignment                               = $_permanentActiveAssignment
        MaximumActiveAssignmentDuration                              = $_maxActiveAssignmentDuration
        Notification_Eligibility_Alert_isDefaultRecipientEnabled     = $($_Notification_Admin_Admin_Eligibility.isDefaultRecipientsEnabled)
        Notification_Eligibility_Alert_NotificationLevel             = $($_Notification_Admin_Admin_Eligibility.notificationLevel)
        Notification_Eligibility_Alert_Recipients                    = $($_Notification_Admin_Admin_Eligibility.notificationRecipients) -join ','
        Notification_Eligibility_Assignee_isDefaultRecipientEnabled  = $($_Notification_Eligibility_Assignee.isDefaultRecipientsEnabled)
        Notification_Eligibility_Assignee_NotificationLevel          = $($_Notification_Eligibility_Assignee.NotificationLevel)
        Notification_Eligibility_Assignee_Recipients                 = $($_Notification_Eligibility_Assignee.notificationRecipients) -join ','
        Notification_Eligibility_Approvers_isDefaultRecipientEnabled = $($_Notification_Eligibility_Approvers.isDefaultRecipientsEnabled)
        Notification_Eligibility_Approvers_NotificationLevel         = $($_Notification_Eligibility_Approvers.NotificationLevel)
        Notification_Eligibility_Approvers_Recipients                = $($_Notification_Eligibility_Approvers.notificationRecipients -join ',')
        Notification_Active_Alert_isDefaultRecipientEnabled          = $($_Notification_Active_Alert.isDefaultRecipientsEnabled)
        Notification_Active_Alert_NotificationLevel                  = $($_Notification_Active_Alert.notificationLevel)
        Notification_Active_Alert_Recipients                         = $($_Notification_Active_Alert.notificationRecipients -join ',')
        Notification_Active_Assignee_isDefaultRecipientEnabled       = $($_Notification_Active_Assignee.isDefaultRecipientsEnabled)
        Notification_Active_Assignee_NotificationLevel               = $($_Notification_Active_Assignee.notificationLevel)
        Notification_Active_Assignee_Recipients                      = $($_Notification_Active_Assignee.notificationRecipients -join ',')
        Notification_Active_Approvers_isDefaultRecipientEnabled      = $($_Notification_Active_Approvers.isDefaultRecipientsEnabled)
        Notification_Active_Approvers_NotificationLevel              = $($_Notification_Active_Approvers.notificationLevel)
        Notification_Active_Approvers_Recipients                     = $($_Notification_Active_Approvers.notificationRecipients -join ',')
        Notification_Activation_Alert_isDefaultRecipientEnabled      = $($_Notification_Activation_Alert.isDefaultRecipientsEnabled)
        Notification_Activation_Alert_NotificationLevel              = $($_Notification_Activation_Alert.NotificationLevel)
        Notification_Activation_Alert_Recipients                     = $($_Notification_Activation_Alert.NotificationRecipients -join ',')
        Notification_Activation_Assignee_isDefaultRecipientEnabled   = $($_Notification_Activation_Assignee.isDefaultRecipientsEnabled)
        Notification_Activation_Assignee_NotificationLevel           = $($_Notification_Activation_Assignee.NotificationLevel)
        Notification_Activation_Assignee_Recipients                  = $($_Notification_Activation_Assignee.NotificationRecipients -join ',')
        Notification_Activation_Approver_isDefaultRecipientEnabled   = $($_Notification_Activation_Approver.isDefaultRecipientsEnabled)
        Notification_Activation_Approver_NotificationLevel           = $($_Notification_Activation_Approver.NotificationLevel)
        Notification_Activation_Approver_Recipients                  = $($_Notification_Activation_Approver.NotificationRecipients -join ',')
    }
}

function Get-PIMDirectoryRoleEligibleAssignment {
    <#
    .SYNOPSIS
    Function returns Azure Directory role eligible assignments.

    .DESCRIPTION
    Function returns Azure Directory role eligible assignments.

    .PARAMETER skipAssignmentSettings
    If specified, the function will not retrieve assignment settings for the roles. This can speed up the function if you don't need the detailed settings.

    .EXAMPLE
    Get-PIMDirectoryRoleEligibleAssignment
    #>

    [CmdletBinding()]
    param (
        [switch] $skipAssignmentSettings
    )

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-MgGraph."
    }

    Invoke-MgGraphRequest -Uri "v1.0/roleManagement/directory/roleEligibilityScheduleInstances?`$expand=roleDefinition,principal" | Get-MgGraphAllPages | % {
        if ($skipAssignmentSettings) {
            $_ | select *, @{n = 'PrincipalName'; e = { $_.principal.displayName } }, @{n = 'RoleName'; e = { $_.roleDefinition.displayName } }
        } else {
            $rules = Get-PIMDirectoryRoleAssignmentSetting -roleId $_.roleDefinitionId

            $_ | select *, @{n = 'PrincipalName'; e = { $_.principal.displayName } }, @{n = 'RoleName'; e = { $_.roleDefinition.displayName } }, @{n = 'Policy'; e = { $rules } }
        }
    }
}

function Get-PIMGroup {
    <#
    .SYNOPSIS
    Function returns Azure groups with some PIM eligible assignments a.k.a. PIM enabled groups.

    .DESCRIPTION
    Function returns Azure groups with some PIM eligible assignments a.k.a. PIM enabled groups.

    To get more details about the PIM eligible assignments, use Get-PIMGroupEligibleAssignment.

    .EXAMPLE
    Get-PIMGroup

    Function returns Azure groups with some PIM eligible assignments a.k.a. PIM enabled groups.
    #>

    [CmdletBinding()]
    param()

    Write-Warning "Searching for groups with PIM eligible assignment. This can take a while."

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-MgGraph."
    }

    # I don't know how to get PIM enabled groups in better way than just get all PIM capable groups and find whether they have some eligible assignment set
    $possiblePIMGroup = Invoke-MgGraphRequest -Uri "v1.0/groups?`$select=Id,DisplayName,OnPremisesSyncEnabled,GroupTypes,MailEnabled,SecurityEnabled" | Get-MgGraphAllPages | ? { $_.onPremisesSyncEnabled -eq $null -and $_.GroupTypes -notcontains 'DynamicMembership' -and !($_.MailEnabled -and $_.SecurityEnabled -and $_.GroupTypes -notcontains 'Unified') -and !($_.MailEnabled -and !$_.SecurityEnabled) }

    if (!$possiblePIMGroup) { return }

    $groupWithPIMEligibleAssignment = New-GraphBatchRequest -url "identityGovernance/privilegedAccess/group/eligibilitySchedules?`$filter=groupId eq '<placeholder>'" -placeholder $possiblePIMGroup.Id | Invoke-GraphBatchRequest -graphVersion v1.0 -dontAddRequestId

    $possiblePIMGroup | ? Id -In ($groupWithPIMEligibleAssignment.groupId) | select *, @{Name = 'EligibleAssignment'; Expression = { $id = $_.Id; $groupWithPIMEligibleAssignment | ? groupId -EQ $id } }
}

function Get-PIMGroupEligibleAssignment {
    <#
    .SYNOPSIS
    Returns eligible assignments for Azure AD groups (PIM).

    .DESCRIPTION
    This function finds Azure AD groups that have Privileged Identity Management (PIM) eligible assignments. It can process specific group IDs or search all groups for PIM eligibility. Optionally, it retrieves assignment settings for each group and translates object IDs to display names for easier interpretation.

    .PARAMETER groupId
    One or more Azure AD group IDs to process. If not specified, all possible PIM-enabled groups will be searched.

    .PARAMETER skipAssignmentSettings
    If specified, the function will not retrieve assignment settings for the roles. This can speed up the function if you don't need the detailed settings.

    .EXAMPLE
    Get-PIMGroupEligibleAssignment
    Returns all Azure AD groups with PIM eligible assignments and their assignment settings.

    .EXAMPLE
    Get-PIMGroupEligibleAssignment -groupId "12345678-aaaa-bbbb-cccc-1234567890ab" -skipAssignmentSettings
    Returns PIM eligible assignments for the specified group, skipping assignment settings for faster results.

    .NOTES
    Author: @AndrewZtrhgf
    #>

    [CmdletBinding()]
    param (
        [string[]] $groupId,

        [switch] $skipAssignmentSettings
    )

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-MgGraph."
    }

    if ($groupId) {
        $possiblePIMGroupId = $groupId
    } else {
        # I don't know how to get the list of PIM enabled groups so I have to find them
        # by searching for eligible role assignments for every PIM-supported-type group
        Write-Warning "Searching for groups with PIM eligible assignment. This can take a while."

        $possiblePIMGroupId = (Invoke-MgGraphRequest -Uri "v1.0/groups?`$select=Id,DisplayName,OnPremisesSyncEnabled,GroupTypes,MailEnabled,SecurityEnabled" | Get-MgGraphAllPages | ? { $_.onPremisesSyncEnabled -eq $null -and $_.GroupTypes -notcontains 'DynamicMembership' -and !($_.MailEnabled -and $_.SecurityEnabled -and $_.GroupTypes -notcontains 'Unified') -and !($_.MailEnabled -and !$_.SecurityEnabled) }).id
    }

    if (!$possiblePIMGroupId) { return }

    # search for groups that have some PIM settings defined
    $groupWithPIMEligibleAssignment = New-GraphBatchRequest -url "identityGovernance/privilegedAccess/group/eligibilitySchedules?`$filter=groupId eq '<placeholder>'" -placeholder $possiblePIMGroupId | Invoke-GraphBatchRequest -graphVersion v1.0 -dontAddRequestId

    if (!$groupWithPIMEligibleAssignment) {
        Write-Warning "None of the groups have PIM eligible assignments"
        return
    }

    #region get assignment settings for all PIM groups
    if (!$skipAssignmentSettings) {
        $assignmentSettingBatch = [System.Collections.Generic.List[Object]]::new()
        $groupWithPIMEligibleAssignment | % {
            $groupId = $_.groupId
            $type = $_.accessId

            $assignmentSettingBatch.Add((New-GraphBatchRequest -url "policies/roleManagementPolicyAssignments?`$filter=scopeId eq '$groupId' and scopeType eq 'Group' and roleDefinitionId eq '$type'&`$expand=policy(`$expand=rules)"))
        }

        $assignmentSettingList = Invoke-GraphBatchRequest -batchRequest $assignmentSettingBatch -graphVersion beta -dontAddRequestId
    }
    #endregion get assignment settings for all PIM groups

    #region translate all Ids to corresponding DisplayName
    $idToTranslate = [System.Collections.Generic.List[Object]]::new()
    $groupWithPIMEligibleAssignment.PrincipalId | % { $idToTranslate.add($_) }
    $groupWithPIMEligibleAssignment.groupId | % { $idToTranslate.add($_) }
    $idToTranslate = $idToTranslate | select -Unique
    $translationList = Get-AzureDirectoryObject -id $idToTranslate
    #endregion translate all Ids to corresponding DisplayName

    # output the results
    $groupWithPIMEligibleAssignment | % {
        $groupId = $_.groupId
        $type = $_.accessId
        $principalId = $_.PrincipalId

        # get the PIM assignment settings
        if ($skipAssignmentSettings) {
            $assignmentSetting = $null
        } else {
            $assignmentSetting = $assignmentSettingList | ? { $_.ScopeId -eq $groupId -and $_.roleDefinitionId -eq $type }
        }

        $_ | select Id, CreatedDateTime, ModifiedDateTime, Status, GroupId, @{n = 'GroupName'; e = { ($translationList | ? Id -EQ $groupId).DisplayName } }, PrincipalId, @{n = 'PrincipalName'; e = { ($translationList | ? Id -EQ $principalId).DisplayName } }, AccessId, MemberType, ScheduleInfo, @{ n = 'Policy'; e = { $assignmentSetting.policy } }
    }
}

function Get-PIMManagementGroupEligibleAssignment {
    <#
    .SYNOPSIS
    Function returns all PIM eligible IAM assignments on selected (all) Azure Management group(s).

    .DESCRIPTION
    Function returns all PIM eligible IAM assignments on selected (all) Azure Management group(s).

    .PARAMETER name
    Name of the Azure Management Group(s) to process.

    .PARAMETER skipAssignmentSettings
    If specified, the function will not retrieve assignment settings for the roles. This can speed up the function if you don't need the detailed settings.

    .EXAMPLE
    Get-PIMManagementGroupEligibleAssignment

    Returns all PIM eligible IAM assignments over all Azure Management Groups.

    .EXAMPLE
    Get-PIMManagementGroupEligibleAssignment -Name IT_test

    Returns all PIM eligible IAM assignments over selected Azure Management Group.
    #>

    [CmdletBinding()]
    param (
        [string[]] $name,

        [switch] $skipAssignmentSettings
    )

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    if ($name) {
        $managementGroupNameList = $name
    } else {
        $managementGroupNameList = (Get-AzManagementGroup).Name
    }

    New-AzureBatchRequest -url "https://management.azure.com/providers/Microsoft.Management/managementGroups/<placeholder>/providers/Microsoft.Authorization/roleEligibilitySchedules?api-version=2020-10-01&`$filter=atScope()" -placeholder $managementGroupNameList | Invoke-AzureBatchRequest | Expand-ObjectProperty -propertyName Properties | Expand-ObjectProperty -propertyName ExpandedProperties | ? memberType -EQ 'Direct' | % {
        if ($skipAssignmentSettings) {
            $assignmentSetting = $null
        } else {
            $roleId = ($_.roleDefinitionId -split "/")[-1]
            $assignmentSetting = Get-PIMResourceRoleAssignmentSetting -roleId $roleId -scope $_.Scope.Id
        }

        $_ | select *, @{n = 'Policy'; e = { $assignmentSetting } }
    }
}

function Get-PIMResourceRoleAssignmentSetting {
    <#
    .SYNOPSIS
    Gets PIM assignment settings for a given Azure resource role at a specific scope.

    .DESCRIPTION
    This function retrieves Privileged Identity Management (PIM) policy assignment settings for a specified Azure resource role (such as Reader, Contributor, etc.) at a given scope (subscription, resource group, or resource). You can specify the role by name or ID.

    .PARAMETER rolename
    The name of the Azure resource role to query. Mandatory if using the rolename parameter set.

    .PARAMETER roleId
    The object ID of the Azure resource role to query. Mandatory if using the roleId parameter set.

    .PARAMETER scope
    The Azure scope (subscription, resource group, or resource) to query for the role assignment settings. Mandatory.

    .EXAMPLE
    Get-PIMResourceRoleAssignmentSetting -rolename "Reader" -scope "/subscriptions/xxxx/resourceGroups/yyyy"
    Retrieves PIM assignment settings for the Reader role at the specified resource group scope.

    .EXAMPLE
    Get-PIMResourceRoleAssignmentSetting -roleId "acdd72a7-3385-48ef-bd42-f606fba81ae7" -scope "/subscriptions/xxxx/resourceGroups/yyyy"
    Retrieves PIM assignment settings for the specified role ID at the given scope.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "rolename")]
        [string] $rolename,
        [Parameter(Mandatory = $true, ParameterSetName = "roleId")]
        [string] $roleId,
        [Parameter(Mandatory = $true)]
        [string] $scope
    )

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    $base = "https://management.azure.com"
    $endpoint = "$base/$scope/providers/Microsoft.Authorization"
    # Get ID of the role $rolename assignable at the provided scope
    if ($rolename) {
        $restUri = "$endpoint/roleDefinitions?api-version=2022-04-01&`$filter=roleName eq '$rolename'"
    } else {
        $restUri = "$endpoint/roleDefinitions/$roleId?api-version=2022-04-01"
    }
    $roleID = ((Invoke-AzRestMethod -Uri $restUri -ErrorAction Stop).content | ConvertFrom-Json).value.id
    # get the role assignment for the roleID
    $restUri = "$endpoint/roleManagementPolicyAssignments?api-version=2020-10-01&`$filter=roleDefinitionId eq '$roleID'"
    $policyId = ((Invoke-AzRestMethod -Uri $restUri -ErrorAction Stop).content | ConvertFrom-Json).value.properties.policyId
    # get the role policy for the policyID
    $restUri = "$base/$policyId/?api-version=2020-10-01"
    ((Invoke-AzRestMethod -Uri $restUri -ErrorAction Stop).content | ConvertFrom-Json).properties
}

function Get-PIMSubscriptionEligibleAssignment {
    <#
    .SYNOPSIS
    Retrieves eligible role assignments for selected Azure subscriptions and their resources using PIM.

    .DESCRIPTION
    This function finds all Privileged Identity Management (PIM) eligible role assignments for the specified Azure subscriptions and their resources. If no subscription IDs are provided, it processes all enabled subscriptions in the tenant. The output includes principal, role, scope, and assignment details for each eligible assignment found.

    .PARAMETER id
    One or more Azure subscription IDs to process. If not provided, all enabled subscriptions will be processed automatically.

    .EXAMPLE
    Get-PIMSubscriptionEligibleAssignment
    Retrieves PIM eligible assignments for all enabled subscriptions and their resources.

    .EXAMPLE
    Get-PIMSubscriptionEligibleAssignment -id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    Retrieves PIM eligible assignments for the specified subscription and its resources.

    #>

    [CmdletBinding()]
    param (
        [string[]] $id
    )

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    if ($id) {
        $subscriptionId = $id
    } else {
        $subscriptionId = (Get-AzSubscription | ? State -EQ 'Enabled').Id
    }

    New-AzureBatchRequest -url "/subscriptions/<placeholder>/providers/Microsoft.Authorization/roleEligibilitySchedules?api-version=2020-10-01" -placeholder $subscriptionId | Invoke-AzureBatchRequest | ? { $_.Properties.MemberType -eq 'Direct' -and $_.Properties.ExpandedProperties.Scope.Type -ne "managementgroup" } | % {
        $id = $_.id

        $_.properties | % {
            if (!$_.endDateTime) { $end = "permanent" } else { $end = $_.endDateTime }

            [PSCustomObject] @{
                "PrincipalName"  = $_.expandedproperties.principal.displayName
                "PrincipalEmail" = $_.expandedproperties.principal.email
                "PrincipalType"  = $_.expandedproperties.principal.type
                "PrincipalId"    = $_.expandedproperties.principal.id
                "RoleName"       = $_.expandedproperties.roleDefinition.displayName
                "RoleType"       = $_.expandedproperties.roleDefinition.type
                "RoleId"         = $_.expandedproperties.roleDefinition.id
                "ScopeId"        = $_.expandedproperties.scope.id
                "ScopeName"      = $_.expandedproperties.scope.displayName
                "ScopeType"      = $_.expandedproperties.scope.type
                "Status"         = $_.Status
                "createdOn"      = $_.createdOn
                "startDateTime"  = $_.startDateTime
                "endDateTime"    = $end
                "updatedOn"      = $_.updatedOn
                "memberType"     = $_.memberType
                "id"             = $id
            }
        }
    }
}

Export-ModuleMember -function Get-PIMAccountEligibleMemberOf, Get-PIMDirectoryRoleAssignmentSetting, Get-PIMDirectoryRoleEligibleAssignment, Get-PIMGroup, Get-PIMGroupEligibleAssignment, Get-PIMManagementGroupEligibleAssignment, Get-PIMResourceRoleAssignmentSetting, Get-PIMSubscriptionEligibleAssignment

Export-ModuleMember -alias Get-AzureAccountEligibleMemberOf
