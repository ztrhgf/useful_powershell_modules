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

    # check via $PSBoundParameters, because there can be no PIM groups at all aka PIMGroupList is $null
    if (!($PSBoundParameters.ContainsKey('PIMGroupList'))) {
        Write-Verbose "Getting groups with eligible PIM assignments"
        $PIMGroupList = Get-PIMGroup
    }

    # no PIM group exist, exit
    if (!$PIMGroupList) {
        Write-Warning "No PIM groups found"

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

function Get-PIMGraphTokenWithClaim {
    <#
    .SYNOPSIS
    Retrieves an MS Graph access token with specific claims and scopes suitable for activating PIM roles using interactive authentication.

    .DESCRIPTION
    This function acquires an OAuth2 access token for Microsoft Graph.
    It is specifically designed to handle 'claims' challenges, which are often required for Privileged Identity Management (PIM) role activation (step-up authentication).
    The function leverages the 'Microsoft.Identity.Client.dll' found in the 'Az.Accounts' module.

    .PARAMETER TenantId
    The Azure Active Directory Tenant ID. Defaults to the global variable '$_tenantId'.

    .PARAMETER Scope
    An array of permission scopes to request.

    'RoleAssignmentSchedule.ReadWrite.Directory' as permission needed to activate the PIM role is automatically added if not present.

    .PARAMETER Claim
    A JSON string containing the claims challenge required for the token.

    This is typically obtained from the 'WWW-Authenticate' header of a failed request or in ErrorDetails.Message property of error returned by Invoke-MgGraphRequest.

    .PARAMETER AsString
    If specified, returns the access token as a plain string. By default, it returns a SecureString.

    .EXAMPLE
    # acrs == Authentication context
    # c1 == id of the authentication context defined in Azure Conditional Access policies
    $claim = '{"access_token":{"acrs":{"essential":true, "value":"c1"}}}'
    $secureToken = Get-PIMGraphTokenWithClaim -Claim $claim

    # Re-connect Graph SDK using the Strong Token
    Connect-MgGraph -AccessToken $secureToken -NoWelcome

    .NOTES
    https://learn.microsoft.com/en-us/entra/identity-platform/developer-guide-conditional-access-authentication-context

    - Requires the 'Az.Accounts' module to be installed.
    - Performs interactive authentication (pop-up window).
    #>

    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string] $tenantId = $_tenantId,

        [string[]] $scope,

        [Parameter(Mandatory = $true)]
        [string] $claim,

        [switch] $asString
    )

    if (!$tenantId) {
        throw "$($MyInvocation.MyCommand): TenantId is required."
    }

    if (!($claim | ConvertFrom-Json -ErrorAction SilentlyContinue -OutVariable jsonObj)) {
        throw "$($MyInvocation.MyCommand): Claim is not a valid JSON string."
    }

    if ("RoleAssignmentSchedule.ReadWrite.Directory" -notin $scope) {
        $scope += "RoleAssignmentSchedule.ReadWrite.Directory"
    }

    # Load Microsoft.Identity.Client.dll Assembly ([Microsoft.Identity.Client.PublicClientApplicationBuilder] type) from Az.Accounts module
    if (!("Microsoft.Identity.Client.PublicClientApplicationBuilder" -as [Type])) {
        # to avoid dll conflicts try loaded modules first
        $modulePath = (Get-Module Az.Accounts | Sort-Object Version -Descending | Select-Object -First 1).ModuleBase

        if (!$modulePath) {
            $modulePath = (Get-Module Az.Accounts -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).ModuleBase
        }
        if ($modulePath) {
            $dllPath = Get-ChildItem -Path $modulePath -Filter "Microsoft.Identity.Client.dll" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($dllPath) {
                Add-Type -Path $dllPath.FullName
            } else {
                throw "Microsoft.Identity.Client.dll not found in Az.Accounts module."
            }
        } else {
            throw "No Az.Accounts module found. Please install the Az PowerShell module."
        }
    }

    # Build Public Client App
    $clientId = "14d82eec-204b-4c2f-b7e8-296a70dab67e" # Microsoft Graph PowerShell Client ID
    $pca = [Microsoft.Identity.Client.PublicClientApplicationBuilder]::Create($clientId).WithAuthority("https://login.microsoftonline.com/$tenantId").WithRedirectUri("http://localhost").Build()

    # Create Interactive Request
    $request = $pca.AcquireTokenInteractive($scope)

    $request = $request.WithClaims($claim)

    # Execute and return Token
    $token = $request.ExecuteAsync().GetAwaiter().GetResult().AccessToken

    if (!$token) {
        throw "$($MyInvocation.MyCommand): Failed to acquire token with claims."
    }

    if ($asString) {
        $token
    } else {
        ConvertTo-SecureString $token -AsPlainText -Force
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
    $possiblePIMGroup = Get-PIMSupportedGroup

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

        $possiblePIMGroupId = (Get-PIMSupportedGroup).id
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
        #TIP KQL instead of Get-AzManagementGroup to avoid error: ... does not have authorization to perform action 'Microsoft.Management/register/action' over scope ...
        $managementGroupNameList = Search-AzGraph2 -query "ResourceContainers
| where type =~ 'microsoft.management/managementgroups'
| project name" | Select-Object -ExpandProperty Name
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

function Get-PIMMyActiveDirectoryRole {
    <#
    .SYNOPSIS
    Retrieves the currently active Azure Directory roles assigned to the current user (permanent and via Privileged Identity Management (PIM)).

    .DESCRIPTION
    Retrieves the currently active Azure Directory roles assigned to the current user (permanent and via Privileged Identity Management (PIM)).
    It helps users identify their active roles and manage their access accordingly.

    .EXAMPLE
    Get-PIMMyActiveDirectoryRole

    This example retrieves all currently active Azure Directory roles assigned to the current user.
    #>

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-MgGraph."
    }

    $batchRequest = [System.Collections.Generic.List[Object]]::new()

    $batchRequest.Add((New-GraphBatchRequest -url "roleManagement/directory/roleDefinitions?`$select=description,displayName,id" -id directoryRoleDefinition))
    $batchRequest.Add((New-GraphBatchRequest -url "roleManagement/directory/roleAssignmentSchedules/filterByCurrentUser(on='principal')" -id myDirectoryRole))

    $batchResponse = Invoke-GraphBatchRequest -batchRequest $batchRequest

    $roleDefinition = $batchResponse | Where-Object { $_.RequestId -eq "directoryRoleDefinition" }
    $myDirectoryRole = $batchResponse | Where-Object { $_.RequestId -eq "myDirectoryRole" }

    $myDirectoryRole | Select-Object @{Name = 'RoleName'; Expression = { $roleId = $_.roleDefinitionId; ($roleDefinition | Where-Object Id -EQ $roleId).DisplayName } }, * -ExcludeProperty RequestId
}

function Get-PIMMyActiveResourceRole {
    <#
    .SYNOPSIS
    Function returns all active tenant wide (PIM and permanent) resource roles assignments for the current user.

    .DESCRIPTION
    Function returns all active tenant wide (PIM and permanent) resource roles assignments for the current user.
    Role assignments via membership in groups are also included.

    .EXAMPLE
    Get-PIMMyActiveResourceRole
    Returns all active tenant wide (PIM and permanent) resource roles assignments for the current user.
    #>

    [CmdletBinding()]
    param ()

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    # get tenant wide resource active eligible roles for the current user
    $url = "https://management.azure.com///providers/Microsoft.Authorization/roleAssignmentSchedules?`$filter=asTarget()&api-version=2020-10-01-preview"

    Invoke-AzRestMethod -Method Get -Uri $url | Select-Object -ExpandProperty Content | ConvertFrom-Json | Select-Object -ExpandProperty value | Expand-ObjectProperty -propertyName Properties | Select-Object *, @{Name = 'ScopeType'; Expression = { $_.expandedProperties.scope.type } }, @{Name = 'ScopeName'; Expression = { $_.expandedProperties.scope.displayName } }, @{Name = 'principalDisplayName'; Expression = { $_.expandedProperties.principal.displayName } }, @{Name = 'principalUPN'; Expression = { $_.expandedProperties.principal.userPrincipalName } }, @{Name = 'roleName'; Expression = { $_.expandedProperties.roleDefinition.displayName } }
}

function Get-PIMMyEligibleDirectoryRole {
    <#
    .SYNOPSIS
    Retrieves the eligible Azure Directory roles for the current user via Privileged Identity Management (PIM).

    .DESCRIPTION
    Retrieves the eligible Azure Directory roles for the current user via Privileged Identity Management (PIM).
    It helps users identify roles they can activate or manage within their tenant.

    .EXAMPLE
    Get-PIMMyEligibleDirectoryRole

    Retrieves and displays all eligible directory roles for the current user.
    #>

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-MgGraph."
    }

    $batchRequest = [System.Collections.Generic.List[Object]]::new()

    $batchRequest.Add((New-GraphBatchRequest -url "roleManagement/directory/roleDefinitions?`$select=description,displayName,id" -id directoryRoleDefinition))
    $batchRequest.Add((New-GraphBatchRequest -url "roleManagement/directory/roleEligibilitySchedules/filterByCurrentUser(on='principal')" -id myDirectoryRole))

    $batchResponse = Invoke-GraphBatchRequest -batchRequest $batchRequest

    $roleDefinition = $batchResponse | Where-Object { $_.RequestId -eq "directoryRoleDefinition" }
    $myDirectoryRole = $batchResponse | Where-Object { $_.RequestId -eq "myDirectoryRole" }

    $myDirectoryRole | Select-Object @{Name = 'RoleName'; Expression = { $roleId = $_.roleDefinitionId; ($roleDefinition | Where-Object Id -EQ $roleId).DisplayName } }, * -ExcludeProperty RequestId
}

function Get-PIMMyEligibleResourceRole {
    <#
    .SYNOPSIS
    Function returns all tenant wide PIM eligible resource roles for the current user.

    .DESCRIPTION
    Function returns all tenant wide PIM eligible resource roles for the current user.
    Role assignments via membership in groups are also included.

    .EXAMPLE
    Get-PIMMyEligibleResourceRole
    Returns all tenant wide PIM eligible resource roles for the current user.
    #>

    [CmdletBinding()]
    param ()

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    # get tenant wide resource eligible roles for the current user
    $url = "https://management.azure.com///providers/Microsoft.Authorization/roleEligibilitySchedules?`$filter=asTarget()&api-version=2020-10-01-preview"

    Invoke-AzRestMethod -Method Get -Uri $url | Select-Object -ExpandProperty Content | ConvertFrom-Json | Select-Object -ExpandProperty value | Expand-ObjectProperty -propertyName Properties | Select-Object *, @{Name = 'ScopeType'; Expression = { $_.expandedProperties.scope.type } }, @{Name = 'ScopeName'; Expression = { $_.expandedProperties.scope.displayName } }, @{Name = 'principalDisplayName'; Expression = { $_.expandedProperties.principal.displayName } }, @{Name = 'principalUPN'; Expression = { $_.expandedProperties.principal.userPrincipalName } }, @{Name = 'roleName'; Expression = { $_.expandedProperties.roleDefinition.displayName } } -ExcludeProperty expandedProperties
}

function Get-PIMResourceRoleAssignmentSetting {
    <#
        .SYNOPSIS
        Gets PIM assignment settings for a given Azure resource role at a specific scope.

        .DESCRIPTION
        This function retrieves Privileged Identity Management (PIM) policy assignment settings for a specified Azure resource role (such as Reader, Contributor, etc.) at a given scope (subscription, resource group, or resource). You can specify the role by name or ID.

        .PARAMETER roleName
        The name of the Azure resource role to query. Mandatory if using the roleName parameter set.

        .PARAMETER roleId
        The object ID of the Azure resource role to query. Mandatory if using the roleId parameter set.

        .PARAMETER scope
        The Azure scope (subscription, resource group, or resource) to query for the role assignment settings. Mandatory.

        .EXAMPLE
        Get-PIMResourceRoleAssignmentSetting -roleName "Reader" -scope "/subscriptions/xxxx/resourceGroups/yyyy"
        Retrieves PIM assignment settings for the Reader role at the specified resource group scope.

        .EXAMPLE
        Get-PIMResourceRoleAssignmentSetting -roleId "acdd72a7-3385-48ef-bd42-f606fba81ae7" -scope "/subscriptions/xxxx/resourceGroups/yyyy"
        Retrieves PIM assignment settings for the specified role ID at the given scope.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "rolename")]
        [string] $roleName,

        [Parameter(Mandatory = $true, ParameterSetName = "roleId")]
        [guid] $roleId,

        [Parameter(Mandatory = $true)]
        [string] $scope
    )

    (Get-Variable "roleId").Attributes.Clear()

    $scope = $scope.TrimStart('/')

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    $base = "https://management.azure.com"
    $endpoint = "$base/$scope/providers/Microsoft.Authorization"

    if ($roleName) {
        # get ID of the role $roleName assignable at the provided scope
        $restUri = "$endpoint/roleDefinitions?api-version=2022-05-01-preview&`$filter=roleName eq '$roleName'"
        Write-Verbose "Getting role ID for role '$roleName' at scope '$scope' (uri '$restUri')"
        $roleID = ((Invoke-AzRestMethod -Uri $restUri -ErrorAction Stop).content | ConvertFrom-Json).value.id
        if (!$roleID) {
            throw "$($MyInvocation.MyCommand): Role '$roleName' not found at scope '$scope'."
        }
    } else {
        $roleID = "/$scope/providers/Microsoft.Authorization/roleDefinitions/$roleId"
    }

    # get the role assignment for the roleID
    $restUri = "$endpoint/roleManagementPolicyAssignments?api-version=2020-10-01&`$filter=roleDefinitionId eq '$roleID'"
    Write-Verbose "Getting PIM role assignment for role ID '$roleID' at scope '$scope' (uri '$restUri')"
    $policyId = ((Invoke-AzRestMethod -Uri $restUri -ErrorAction Stop).content | ConvertFrom-Json).value.properties.policyId

    # get the role policy for the policyID
    $restUri = "$base/$policyId/?api-version=2020-10-01"
    Write-Verbose "Getting PIM role policy for policy ID '$policyId' (uri '$restUri')"
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

function Get-PIMSupportedGroup {
    <#
    .SYNOPSIS
    Get all groups that can be theoretically used for PIM assignment.

    Unfortunately I don't know a better way to filter out groups that have eligible PIM assignments.
    #>

    [CmdletBinding()]
    param()

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-MgGraph."
    }

    Invoke-MgGraphRequest -Uri "v1.0/groups?`$select=Id,DisplayName,OnPremisesSyncEnabled,GroupTypes,MailEnabled,SecurityEnabled" | Get-MgGraphAllPages | ? { $_.onPremisesSyncEnabled -eq $null -and $_.GroupTypes -notcontains 'DynamicMembership' -and !($_.MailEnabled -and $_.SecurityEnabled -and $_.GroupTypes -notcontains 'Unified') -and !($_.MailEnabled -and !$_.SecurityEnabled) }
}

function Invoke-PIMDirectoryRoleActivation {
    <#
    .SYNOPSIS
    Activates one or more eligible Azure AD PIM roles for the current user.

    .DESCRIPTION
    This function creates a new role assignment schedule request to activate eligible Azure AD role(s).
    It resolves the role name(s) to the role definition ID and submits the activation request.

    .PARAMETER RoleName
    The display name(s) of the role(s) to activate (e.g., "Global Administrator").

    .PARAMETER Justification
    The reason for activating the role.

    .PARAMETER DurationInHours
    The duration of the activation in hours.

    Of set to 0, 30 minutes will be used instead

    By default 1 hour.

    .PARAMETER WaitAfterActivation
    The number of seconds to wait after activation to allow the role to propagate.
    Sharepoint, DevOps and Exchange roles takes dozens of minutes to propagate. The rest usually a minute or so.

    By default 30 seconds.

    .PARAMETER SufficientRoleName
    A role name(s) that, if already active, will prevent activation of the requested role(s).

    "Global Administrator" is always considered a sufficient role.

    Can be a string, string array or hashtable/dictionary with role name that is being activated as a key and sufficient role name(s) as a value.

    .EXAMPLE
    Invoke-PIMDirectoryRoleActivation -RoleName "Global Administrator" -Justification "Daily maintenance"

    .EXAMPLE
    Invoke-PIMDirectoryRoleActivation -RoleName "Exchange Administrator", "SharePoint Administrator" -Justification "Project X"

    .EXAMPLE
    Invoke-PIMDirectoryRoleActivation -RoleName "Security Reader" -SufficientRoleName "Security Administrator"

    If "Global Administrator" OR "Security Administrator" is already active, "Security Reader" will NOT be activated.

    .EXAMPLE
    $sufficientRoles = @{
        "Cloud Device Administrator" = "Intune Administrator"
        "Security Reader" = "Security Administrator"
    }
    Invoke-PIMDirectoryRoleActivation -RoleName "Security Reader", "Cloud Device Administrator" -SufficientRoleName $sufficientRoles

    "Cloud Device Administrator" will be skipped if "Global Administrator" OR "Intune Administrator" is active.
    "Security Reader" will be skipped if "Global Administrator" OR "Security Administrator" is active.

    .NOTES
    Ensure you have consented to the necessary permissions (RoleAssignmentSchedule.ReadWrite.Directory at least) to activate PIM roles.
    #>

    [CmdletBinding()]
    [Alias("Activate-PIMDirectoryRole", "ipdr")]
    param (
        [ArgumentCompleter( {
                param ($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams)

                Get-PIMMyEligibleDirectoryRole | Select-Object -ExpandProperty RoleName | Sort-Object | Where-Object { $_ -like "*$WordToComplete*" } | ForEach-Object { '"' + $_ + '"' }
            })]
        [string[]]$roleName,

        [string]$justification = "",

        [ValidateRange(0, 8)]
        [int]$durationInHours = 1,

        [int] $waitAfterActivation = 30,

        [object] $sufficientRoleName
    )

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-MgGraph -Scopes RoleAssignmentSchedule.ReadWrite.Directory."
    }

    # duration uses ISO 8601 format
    if ($durationInHours -eq 0) {
        # minimum is 30 minutes
        $durationAs8601 = "PT30M"
    } else {
        $durationAs8601 = "PT$($durationInHours)H"
    }

    #region get helper data
    # Get current user ID
    try {
        $me = Invoke-MgGraphRequest -Uri "v1.0/me" -Method GET
        $userId = $me.id
        Write-Verbose "Current User ID: $userId"
    } catch {
        throw "Failed to retrieve current user information: $_"
    }

    # Prepare batch request
    $batchRequest = [System.Collections.Generic.List[Object]]::new()
    $batchRequest.Add((New-GraphBatchRequest -url "roleManagement/directory/roleDefinitions?`$select=displayName,id" -id directoryRoleDefinition))
    $batchRequest.Add((New-GraphBatchRequest -url "roleManagement/directory/roleEligibilitySchedules/filterByCurrentUser(on='principal')?`$select=DirectoryScopeId,RoleDefinitionId" -id eligibleDirectoryRole))
    $batchRequest.Add((New-GraphBatchRequest -url "roleManagement/directory/roleAssignmentSchedules/filterByCurrentUser(on='principal')?`$select=DirectoryScopeId,RoleDefinitionId,AssignmentType" -id activeDirectoryRole))
    $batchRequest.Add((New-GraphBatchRequest -url "roleManagement/directory/roleAssignments?`$filter=principalId eq '$userId'&`$select=DirectoryScopeId,RoleDefinitionId" -id permanentDirectoryRole))

    $batchResponse = Invoke-GraphBatchRequest -batchRequest $batchRequest

    $roleDefinition = $batchResponse | Where-Object { $_.RequestId -eq "directoryRoleDefinition" }
    $eligibleDirectoryRoleRaw = $batchResponse | Where-Object { $_.RequestId -eq "eligibleDirectoryRole" }
    $activeDirectoryRoleRaw = $batchResponse | Where-Object { $_.RequestId -eq "activeDirectoryRole" }
    $permanentDirectoryRoleRaw = $batchResponse | Where-Object { $_.RequestId -eq "permanentDirectoryRole" }

    # Process Eligible Roles
    $eligibleDirectoryRole = $eligibleDirectoryRoleRaw | Select-Object @{Name = 'RoleName'; Expression = { ($roleDefinition | Where-Object Id -EQ $_.roleDefinitionId).DisplayName } }, * -ExcludeProperty RequestId

    # Process Active Roles (PIM Active + Permanent)
    $activeDirectoryRole = [System.Collections.Generic.List[Object]]::new()

    if ($activeDirectoryRoleRaw) {
        $activeDirectoryRole.AddRange(($activeDirectoryRoleRaw | Select-Object @{Name = 'RoleName'; Expression = { ($roleDefinition | Where-Object Id -EQ $_.roleDefinitionId).DisplayName } }, * -ExcludeProperty RequestId))
    }

    if ($permanentDirectoryRoleRaw) {
        foreach ($permRole in $permanentDirectoryRoleRaw) {
            $activeDirectoryRole.Add([PSCustomObject]@{
                    RoleName         = ($roleDefinition | Where-Object Id -EQ $permRole.roleDefinitionId).DisplayName
                    RoleDefinitionId = $permRole.roleDefinitionId
                    DirectoryScopeId = $permRole.directoryScopeId
                    AssignmentType   = "Permanent"
                })
        }
    }
    #endregion get helper data

    #region checks
    if (!$eligibleDirectoryRole) {
        throw "You have no eligible directory roles to activate."
    }
    #endregion checks

    # Interactive selection if no role provided
    if (!$roleName) {
        while (!$roleName) {
            $roleName = $eligibleDirectoryRole | Select-Object RoleName, DirectoryScopeId, RoleDefinitionId | Sort-Object RoleName | Out-GridView -Title "Select role(s) to activate" -OutputMode Multiple | Select-Object -ExpandProperty RoleName
        }
    }

    #region process roles to activate
    $activatedRole = 0
    $failedRoleActivation = 0

    foreach ($rlName in $roleName) {
        if ($rlName -notin $eligibleDirectoryRole.RoleName) {
            Write-Warning "Role '$rlName' is not found in your eligible roles. Use Get-PIMMyEligibleDirectoryRole to list your eligible roles."
            continue
        }

        # Check sufficient roles
        $rolesToCheck = [System.Collections.Generic.List[string]]::new()
        $rolesToCheck.Add("Global Administrator")

        if ($null -ne $sufficientRoleName) {
            if ($sufficientRoleName -is [System.Collections.IDictionary]) {
                # Assume hashtable/dictionary with role name as a key and sufficient role name(s) as a value
                if ($sufficientRoleName.Contains($rlName)) {
                    $val = $sufficientRoleName[$rlName]
                    if ($val) { $rolesToCheck.AddRange([string[]]$val) }
                }
            } else {
                # Assume string or string array of sufficient role names
                $rolesToCheck.AddRange([string[]]$sufficientRoleName)
            }
        }

        $hasSufficientRole = $activeDirectoryRole | Where-Object { $rolesToCheck -contains $_.RoleName } | Select-Object -First 1 | Select-Object -ExpandProperty RoleName

        if ($hasSufficientRole) {
            Write-Warning "Sufficient role '$hasSufficientRole' is already active. Skipping activation of '$rlName'."
            continue
        }

        if ($rlName -in $activeDirectoryRole.RoleName) {
            Write-Warning "Role '$rlName' is already active."
            continue
        }

        #region activate role
        $roleToActivate = $eligibleDirectoryRole | Where-Object { $_.RoleName -eq $rlName }
        $rlDefinitionId = $roleToActivate.roleDefinitionId

        #region check allowed maximum role activation time
        Write-Verbose "Retrieving policy settings for role '$rlName'..."
        $response = Invoke-MgGraphRequest -Uri "v1.0/policies/roleManagementPolicyAssignments?`$filter=scopeType eq 'DirectoryRole' and roleDefinitionId eq '$rlDefinitionId' and scopeId eq '/'&`$select=policyId" | Get-MgGraphAllPages
        $policyID = $response.policyID
        Write-Verbose "policyID = $policyID"

        # get the rules
        $response = Invoke-MgGraphRequest -Uri "v1.0/policies/roleManagementPolicies/$policyID/rules" | Get-MgGraphAllPages

        $maximumDurationAs8601 = $response | Where-Object id -EQ 'Expiration_EndUser_Assignment' | Select-Object -ExpandProperty MaximumDuration

        if ($maximumDurationAs8601 -and (New-TimeSpan -Hours $durationInHours) -gt [System.Xml.XmlConvert]::ToTimeSpan($maximumDurationAs8601)) {
            Write-Warning "Requested duration of $durationInHours hour(s) exceeds maximum allowed duration of $maximumDurationAs8601 for role '$rlName'. Using maximum allowed duration."
            $durationToSetAs8601 = $maximumDurationAs8601
        } else {
            $durationToSetAs8601 = $durationAs8601
        }
        #endregion check allowed maximum role activation time

        Write-Warning "Activating Directory Role '$rlName' ($rlDefinitionId) for $durationToSetAs8601..."

        # Construct payload
        $body = @{
            action           = "selfActivate"
            principalId      = $userId
            roleDefinitionId = $rlDefinitionId
            directoryScopeId = "/"
            justification    = $justification
        }

        if ($durationInHours) {
            $body.scheduleInfo = @{
                startDateTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                expiration    = @{
                    type     = "AfterDuration"
                    duration = "$durationToSetAs8601"
                }
            }
        }

        Write-Verbose "Submitting activation request..."

        try {
            $uri = "v1.0/roleManagement/directory/roleAssignmentScheduleRequests"
            $response = Invoke-MgGraphRequest -Method POST -Uri $uri -Body $body -ErrorAction Stop

            Write-Verbose "Successfully submitted activation request for '$rlName'."
            ++$activatedRole
            $response
        } catch {
            # Handle Conditional Access / MFA challenge (Claims)
            # When PIM requires FIDO/Passkey or specific MFA, the API returns 403 with a claims challenge.
            $exception = $_.ErrorDetails.Message
            $pimActivationPortalUrl = "https://portal.azure.com/?feature.msaljs=true#view/Microsoft_Azure_PIMCommon/ActivationMenuBlade/~/aadmigratedroles/provider/aadroles"

            if ($exception -and $exception -match 'claims=([^"]+)') {
                $claimsChallenge = $matches[1]
                $claimsChallenge = [System.Uri]::UnescapeDataString($claimsChallenge)

                Write-Warning "Activation of the role '$rlName' requires additional authentication (e.g. FIDO2/Passkey/MFA)."
                Write-Verbose "Claims challenge detected: $claimsChallenge"

                # Connect-AzAccount with 'Claims' parameter cannot be used, because we need to be granted scope 'RoleAssignmentSchedule.ReadWrite.Directory' for PIM activation
                $secureToken = Get-PIMGraphTokenWithClaim -Claim $claimsChallenge
                # Re-connect Graph SDK using the Strong Token
                Connect-MgGraph -AccessToken $secureToken -NoWelcome

                # Retry the request
                try {
                    Write-Verbose "Retrying activation request..."
                    $response = Invoke-MgGraphRequest -Method POST -Uri $uri -Body $body -ErrorAction Stop

                    Write-Verbose "Successfully submitted activation request for '$rlName' after re-authentication."
                    ++$activatedRole

                    # return activation details
                    $response
                } catch {
                    ++$failedRoleActivation

                    # disconnect just in case the session gets broken
                    # $null = Disconnect-MgGraph -ErrorAction SilentlyContinue

                    Write-Error "Failed to activate the role '$rlName' after re-authentication. Error was: $_"

                    if ($failedRoleActivation -eq 1) {
                        Write-Error "Opening the portal for manual activation."
                        Start-Process $pimActivationPortalUrl
                    }

                    continue
                }
            } else {
                ++$failedRoleActivation

                Write-Error "Failed to activate the role '$rlName'. Error was: $_"

                if ($failedRoleActivation -eq 1) {
                    Write-Error "Opening the portal for manual activation."
                    Start-Process $pimActivationPortalUrl
                }

                continue
            }
        }
        #endregion activate role
    }
    #endregion process roles to activate

    if ($waitAfterActivation -and $activatedRole) {
        Write-Warning "Waiting $waitAfterActivation seconds to allow role(s) activation to propagate..."
        Start-Sleep $waitAfterActivation
    }
}

function Invoke-PIMResourceRoleActivation {
    <#
    .SYNOPSIS
    Activates one or more eligible Azure resource (IAM) PIM roles for the current user.

    .DESCRIPTION
    This function creates a new role assignment schedule request to activate eligible Azure resource role(s).
    It retrieves your eligible role assignments across tenant and allows you to activate them.

    Unlike Invoke-PIMDirectoryRoleActivation which handles Entra ID directory roles (like Global Administrator),
    this function handles Azure Resource Manager (ARM) roles (like Owner, Contributor, Reader) on Azure resources.

    .PARAMETER RoleToActivate
    A hashtable where the key is the Azure resource scope id and the value is the role name(s) to activate.

    Role Example:
    "Owner", "Contributor"

    Scope Example:
    - Subscription: "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    - Resource Group: "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/myRG"
    - Resource: "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/myRG/providers/Microsoft.Storage/storageAccounts/myStorage"

    If not provided, an interactive selection of all eligible roles will be shown.

    .PARAMETER Justification
    The reason for activating the role.

    .PARAMETER DurationInHours
    The duration of the activation in hours.

    If set to 0, 30 minutes will be used instead.

    By default 1 hour.

    .PARAMETER WaitAfterActivation
    The number of seconds to wait after activation to allow the role to propagate.

    By default 30 seconds.

    .PARAMETER ExcludeActivatedRoles
    If set, already activated roles will be excluded from the interactive selection.
    Adds several seconds to the execution time as active roles need to be retrieved.

    .EXAMPLE
    Invoke-PIMResourceRoleActivation

    Shows an interactive selection of all eligible Azure resource roles across all subscriptions.

    .EXAMPLE
    $roleToActivate = @{
        "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" = "Owner"
        "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/myRG" = "Contributor"
    }

    Invoke-PIMResourceRoleActivation -RoleToActivate $roleToActivate -Justification "Deployment task"

    Activates the "Owner" role on the specified subscription and "Contributor" role on the specified resource group
    with the justification "Deployment task".

    .EXAMPLE
    $tenantId = (Get-AzContext).Tenant.Id

    $roleToActivate = @{
        "/providers/Microsoft.Management/managementGroups/$tenantId" = "User Access Administrator"
    }

    Invoke-PIMResourceRoleActivation -RoleToActivate $roleToActivate -DurationInHours 4 -WaitAfterActivation 60

    Activates the "User Access Administrator" role on the tenant root group management group for 4 hours,
    then waits 60 seconds to allow the role to propagate.

    .NOTES
    Requires Az.Accounts module and an active Azure session (Connect-AzAccount).
    #>

    [CmdletBinding()]
    [Alias("Activate-PIMResourceRole", "iprr")]
    param (
        [hashtable] $roleToActivate,

        [string] $justification = "",

        [ValidateRange(0, 8)]
        [int] $durationInHours = 1,

        [int] $waitAfterActivation = 30,

        [switch] $excludeActivatedRoles
    )

    #region checks
    if ($roleToActivate) {
        # keys should be azure resource scope and value should be role name(s)
        $roleToActivate.GetEnumerator() | ForEach-Object {
            $role = $_
            if ($role.Key.Gettype().Name -ne 'String') {
                throw "Invalid roleToActivate key type: $($role.Key.GetType().Name). Expected String (Azure resource scope)."
            }
            if ($role.Value.Gettype().Name -ne 'String' -and $role.Value.Gettype().Name -ne 'String[]') {
                throw "Invalid roleToActivate value type: $($role.Value.GetType().Name). Expected String or String[] (Role name(s))."
            }
        }
    }
    #endregion checks

    #region authentication check
    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction SilentlyContinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand)`: Authentication needed. Please call Connect-AzAccount."
    }
    #endregion authentication check

    # duration uses ISO 8601 format
    if ($durationInHours -eq 0) {
        # minimum is 30 minutes
        $durationAs8601 = "PT30M"
    } else {
        $durationAs8601 = "PT$($durationInHours)H"
    }

    $base = "https://management.azure.com"

    #region get current user ID
    try {
        $context = Get-AzContext
        $userId = (Get-AzADUser -UserPrincipalName $context.Account.Id -ErrorAction Stop).Id
        Write-Verbose "Current User ID: $userId"
    } catch {
        throw "Failed to retrieve current user information: $_"
    }
    #endregion get current user ID

    #region get eligible and active role assignments
    # get eligible role assignments
    $eligibleRole = Get-PIMMyEligibleResourceRole | Select-Object Scope, ScopeType, ScopeName, RoleName, RoleDefinitionId, Id
    if ($excludeActivatedRoles) {
        # get active role assignments
        $activeRole = Get-PIMMyActiveResourceRole | Where-Object { $_.AssignmentType -eq 'Activated' } | Select-Object Scope, ScopeType, ScopeName, RoleName, RoleDefinitionId, Id
        # filter out already activated roles
        $eligibleRole = $eligibleRole | Where-Object {
            $elgRole = $_
            $isActive = $activeRole | Where-Object { $_.RoleName -eq $elgRole.RoleName -and $_.Scope -eq $elgRole.Scope }
            -not $isActive
        }
    }
    #endregion get eligible and active role assignments

    #region interactive selection if no role provided
    if (!$roleToActivate) {
        $selectedRole = $eligibleRole | Sort-Object ScopeName, RoleName | Out-GridView -Title "Select role(s) to activate" -OutputMode Multiple

        if (!$selectedRole) {
            Write-Warning "No roles selected."
            return
        }
    } else {
        # validate provided roles against eligible roles
        # that such role and scope exists in eligible roles
        $selectedRole = [System.Collections.Generic.List[Object]]::new()

        $roleToActivate.GetEnumerator() | ForEach-Object {
            $scope = $_.Key
            $roleName = @($_.Value)

            $roleName | ForEach-Object {
                $rName = $_

                # filter eligible roles
                $eligibleRoleInScope = $eligibleRole | Where-Object { $_.Scope -eq $scope -and $_.RoleName -eq $rName }

                if ($eligibleRoleInScope) {
                    $selectedRole.Add($eligibleRoleInScope)
                } else {
                    Write-Warning "No eligible role found for scope '$scope' with requested role name: $rName."
                }
            }
        }

        if (!$selectedRole) {
            throw "None of the requested roles ($(($roleToActivate.Values | ForEach-Object { $_ } | Sort-Object -Unique) -Join ', ')) and scopes are available in your eligible roles."
        }
    }
    #endregion interactive selection if no role provided

    #region process roles to activate
    $activatedRole = 0

    foreach ($role in $selectedRole) {
        $rlName = $role.RoleName
        $rlScope = $role.Scope
        $normalizedScope = $rlScope.TrimStart('/')
        $rlDefinitionId = $role.RoleDefinitionId

        # check if already active
        if ($excludeActivatedRoles) {
            $isActive = $activeRole | Where-Object { $_.RoleName -eq $rlName -and $_.Scope -eq $rlScope }

            if ($isActive) {
                Write-Warning "Role '$rlName' on scope '$rlScope' is already active."
                continue
            }
        }

        #region check allowed maximum role activation time
        $durationToSetAs8601 = $durationAs8601
        #TIP to speed up, we skip checking the maximum allowed duration and retrieve this setting only on error
        # try {
        #     Write-Verbose "Retrieving policy settings for role '$rlName' on scope '$rlScope'."
        #     $restUri = "$base/$normalizedScope/providers/Microsoft.Authorization/roleManagementPolicyAssignments?api-version=2020-10-01&`$filter=roleDefinitionId eq '$rlDefinitionId'"
        #     $policyAssignmentResponse = (Invoke-AzRestMethod -Uri $restUri -ErrorAction Stop).Content | ConvertFrom-Json
        #     $policyId = $policyAssignmentResponse.value[0].properties.policyId

        #     if ($policyId) {
        #         $restUri = "$base/$policyId`?api-version=2020-10-01"
        #         $policyResponse = (Invoke-AzRestMethod -Uri $restUri -ErrorAction Stop).Content | ConvertFrom-Json
        #         $rules = $policyResponse.properties.rules

        #         $expirationRule = $rules | Where-Object { $_.id -eq 'Expiration_EndUser_Assignment' }
        #         $maximumDurationAs8601 = $expirationRule.maximumDuration

        #         if ($maximumDurationAs8601 -and (New-TimeSpan -Hours $durationInHours) -gt [System.Xml.XmlConvert]::ToTimeSpan($maximumDurationAs8601)) {
        #             Write-Warning "Requested duration of $durationInHours hour(s) exceeds maximum allowed duration of $maximumDurationAs8601 for role '$rlName'. Using maximum allowed duration."
        #             $durationToSetAs8601 = $maximumDurationAs8601
        #         } else {
        #             $durationToSetAs8601 = $durationAs8601
        #         }
        #     } else {
        #         $durationToSetAs8601 = $durationAs8601
        #     }
        # } catch {
        #     Write-Verbose "Could not retrieve policy settings for role '$rlName': $_. Using requested duration."
        #     $durationToSetAs8601 = $durationAs8601
        # }
        #endregion check allowed maximum role activation time

        #region build activation request
        $requestName = [guid]::NewGuid().ToString()

        $requestBody = @{
            properties = @{
                principalId                     = $userId
                roleDefinitionId                = $rlDefinitionId
                requestType                     = "SelfActivate"
                linkedRoleEligibilityScheduleId = $role.Id
                scheduleInfo                    = @{
                    startDateTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                    expiration    = @{
                        type     = "AfterDuration"
                        duration = $durationToSetAs8601
                    }
                }
            }
        }

        if ($justification) {
            $requestBody.properties.justification = $justification
        }
        #endregion build activation request

        #region send activation request
        try {
            $restUri = "$base/$normalizedScope/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/$($requestName)?api-version=2020-10-01"
            # send activation request
            Write-Warning "Activating Azure Resource Role '$rlName' on scope '$($role.ScopeName)' ($rlScope) for $($durationToSetAs8601 -replace '^PT','')."
            $response = Invoke-AzRestMethod -Uri $restUri -Method PUT -Payload ($requestBody | ConvertTo-Json -Depth 10) -ErrorAction Stop

            #region handle Conditional Access / MFA challenge (Claims)
            # when PIM requires FIDO/Passkey or specific MFA, the API returns 400 with a claims challenge
            $exception = ($response.Content | ConvertFrom-Json).error.message

            if ($exception -and $exception -match 'claims=([^"]+)') {
                #region reauthenticate using claims challenge
                Write-Warning "Activation of the role '$rlName' requires additional authentication (e.g. FIDO2/Passkey/MFA)."

                $claimsChallenge = $matches[1]
                $claimsChallenge = [System.Uri]::UnescapeDataString($claimsChallenge)

                Write-Verbose "Claims challenge detected: $claimsChallenge"

                $bytes = [System.Text.Encoding]::ASCII.GetBytes($claimsChallenge)
                $encodedClaimsChallenge = [Convert]::ToBase64String($bytes)
                #TIP tenant is required to avoid error: WARNING: Unable to acquire token for tenant '<tenantid>' with error 'InteractiveBrowserCredential authentication failed: Redirect Uri mismatch.  Expected (/favicon.ico) Actual (/). '
                $null = Connect-AzAccount -Claims $encodedClaimsChallenge -Tenant (Get-AzContext).tenant.id -ErrorAction Stop -WarningAction SilentlyContinue
                #endregion reauthenticate using claims challenge

                # retry the request
                try {
                    Write-Verbose "Retrying activation request..."
                    $response = Invoke-AzRestMethod -Uri $restUri -Method PUT -Payload ($requestBody | ConvertTo-Json -Depth 10) -ErrorAction Stop
                } catch {
                    ++$failedRoleActivation

                    Write-Error "Failed to activate role '$rlName' after re-authentication. Error was: $_"

                    if ($failedRoleActivation -eq 1) {
                        Write-Error "Opening the portal for manual activation."
                        Start-Process "https://portal.azure.com/?feature.msaljs=true#view/Microsoft_Azure_PIMCommon/ActivationMenuBlade/~/aadmigratedroles/provider/aadroles"
                    }

                    continue
                }
            }
            #endregion handle Conditional Access / MFA challenge (Claims)

            if ($response.StatusCode -in 200, 201) {
                Write-Verbose "Successfully submitted activation request for '$rlName' on '$($role.ScopeName)' ($rlScope)."
                ++$activatedRole

                $result = $response.Content | ConvertFrom-Json

                # return activation details
                [PSCustomObject]@{
                    RoleName    = $rlName
                    ScopeId     = $rlScope
                    Status      = $result.properties.status
                    RequestId   = $result.name
                    RequestType = $result.properties.requestType
                    Duration    = $durationToSetAs8601
                }
            } else {
                $errorContent = $response.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
                $errorMessage = if ($errorContent.error.message) { $errorContent.error.message } else { $response.Content }
                if ($errorMessage -like "*ExpirationRule*") {
                    Write-Verbose "Retrieving policy settings for role '$rlName' on scope '$rlScope'."
                    $assSetting = Get-PIMResourceRoleAssignmentSetting -roleId $rlDefinitionId.split("/")[-1] -scope $rlScope
                    $maximumDuration = $assSetting.effectiveRules | Where-Object id -EQ "Expiration_EndUser_Assignment" | Select-Object -ExpandProperty maximumDuration
                    $errorDetail = "Maximum allowed duration is $($maximumDuration -replace '^PT','')."
                } elseif ($errorMessage -like "*JustificationRule*") {
                    $errorDetail = "Justification is required for activating this role."
                } elseif ($errorMessage -like "*The Role assignment already exists*") {
                    Write-Warning "The role is already assigned."
                    continue
                } else {
                    $errorDetail = ""
                }

                Write-Error "Failed to activate role '$rlName' on '$rlScope'. Status: $($response.StatusCode). Error: $errorMessage. $errorDetail"
            }
        } catch {
            Write-Error "Failed to activate role '$rlName' on '$rlScope'. Error: $_"
        }
        #endregion send activation request
    }
    #endregion process roles to activate

    if ($waitAfterActivation -and $activatedRole) {
        Write-Warning "Waiting $waitAfterActivation seconds to allow role(s) activation to propagate..."
        Start-Sleep $waitAfterActivation
    }
}

function New-PIMResourceEligibleRoleAssignment {
    <#
    .SYNOPSIS
    Creates a PIM eligible role assignment for a specified Azure resource.

    .DESCRIPTION
    This function creates a Privileged Identity Management (PIM) eligible role assignment for a user, group, or service principal
    on a specified Azure resource scope. It uses the Azure Resource Manager API to create role eligibility schedule requests.

    .PARAMETER scope
    The Azure resource scope where the role assignment will be created.
    Examples:
    - Subscription: "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    - Resource Group: "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/myRG"
    - Resource: "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/myRG/providers/Microsoft.Storage/storageAccounts/myStorage"

    .PARAMETER principalId
    The object ID of the principal (user, group, or service principal) to assign the role to.

    .PARAMETER roleName
    The name of the Azure role to assign. Use this parameter if you know the role name (e.g., "Reader", "Contributor", "Owner").
    Either roleName or roleDefinitionId must be specified.

    .PARAMETER roleDefinitionId
    The full resource ID of the role definition.
    Example: "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
    Either roleName or roleDefinitionId must be specified.

    .PARAMETER justification
    Optional justification for the role assignment request.

    .PARAMETER startDateTime
    The start date and time for the role eligibility. Defaults to current time.

    .PARAMETER duration
    The duration of the role eligibility in ISO 8601 duration format.
    Examples: "P365D" (365 days), "P1Y" (1 year), "P90D" (90 days).
    Defaults to "P365D".

    .PARAMETER permanent
    Switch to create a permanent (no expiration) role eligibility assignment.

    .PARAMETER configurePIMSettings
    Switch to run Set-PIMResourceRoleAssignmentSetting with default parameters for the role.
    This configures the PIM policy settings: no justification required, authentication context required, no approval required, permanent assignments allowed.

    .EXAMPLE
    New-PIMResourceEligibleRoleAssignment -scope "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -principalId "11111111-1111-1111-1111-111111111111" -roleName "Reader"

    Creates a Reader eligible role assignment for the specified principal on the subscription with default 365 days duration.

    .EXAMPLE
    New-PIMResourceEligibleRoleAssignment -scope "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/myRG" -principalId "11111111-1111-1111-1111-111111111111" -roleName "Contributor" -duration "P90D" -justification "Project access"

    Creates a Contributor eligible role assignment for 90 days with a justification.

    .EXAMPLE
    New-PIMResourceEligibleRoleAssignment -scope "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -principalId "11111111-1111-1111-1111-111111111111" -roleName "Owner" -permanent

    Creates a permanent Owner eligible role assignment.
    #>

    [CmdletBinding(DefaultParameterSetName = "roleName")]
    param (
        [Parameter(Mandatory = $true)]
        [string] $scope,

        [Parameter(Mandatory = $true)]
        [string] $principalId,

        [Parameter(ParameterSetName = "roleName")]
        [string] $roleName,

        [Parameter(Mandatory = $true, ParameterSetName = "roleDefinitionId")]
        [string] $roleDefinitionId,

        [string] $justification,

        [datetime] $startDateTime = (Get-Date),

        [string] $duration = "P365D",

        [switch] $permanent,

        [switch] $configurePIMSettings
    )

    #region Authentication check
    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction SilentlyContinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand)`: Authentication needed. Please call Connect-AzAccount."
    }
    #endregion Authentication check

    #region Normalize scope
    $scope = $scope.TrimStart('/')
    #endregion Normalize scope

    #region Get role definition ID
    $base = "https://management.azure.com"

    if (!$roleName -and !$roleDefinitionId) {
        # interactive role selection
        $restUri = "$base/$scope/providers/Microsoft.Authorization/roleDefinitions?api-version=2022-04-01"
        $allRolesResponse = (Invoke-AzRestMethod -Uri $restUri -ErrorAction Stop).Content | ConvertFrom-Json

        if (!$allRolesResponse.value -or $allRolesResponse.value.Count -eq 0) {
            throw "$($MyInvocation.MyCommand)`: No roles found at scope '/$scope'."
        }

        $selectedRole = $allRolesResponse.value | Select-Object @{N = 'RoleName'; E = { $_.properties.roleName } }, @{N = 'Description'; E = { $_.properties.description } }, @{N = 'Id'; E = { $_.name } } | Sort-Object RoleName | Out-GridView -Title "Select IAM role for scope: /$scope" -OutputMode Single

        if (!$selectedRole) {
            throw "$($MyInvocation.MyCommand)`: No role selected."
        }

        $roleName = $selectedRole.RoleName
    }

    if ($roleName) {
        $restUri = "$base/$scope/providers/Microsoft.Authorization/roleDefinitions?api-version=2022-04-01&`$filter=roleName eq '$roleName'"
        $roleDefResponse = (Invoke-AzRestMethod -Uri $restUri -ErrorAction Stop).Content | ConvertFrom-Json

        if (!$roleDefResponse.value -or $roleDefResponse.value.Count -eq 0) {
            throw "$($MyInvocation.MyCommand)`: Role '$roleName' not found at scope '/$scope'."
        }

        $roleDefinitionId = $roleDefResponse.value[0].id
    }
    #endregion Get role definition ID

    #region Configure PIM settings if requested
    if ($configurePIMSettings) {
        Write-Verbose "Configuring PIM settings for role '$roleName' at scope '/$scope'"
        Set-PIMResourceRoleAssignmentSetting -scope $scope -roleName $roleName
    }
    #endregion Configure PIM settings if requested

    #region Build request body
    $requestName = [guid]::NewGuid().ToString()

    $scheduleInfo = @{
        startDateTime = $startDateTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    }

    if ($permanent) {
        $scheduleInfo.expiration = @{
            type = "NoExpiration"
        }
    } else {
        $scheduleInfo.expiration = @{
            type     = "AfterDuration"
            duration = $duration
        }
    }

    $requestBody = @{
        properties = @{
            principalId      = $principalId
            roleDefinitionId = $roleDefinitionId
            requestType      = "AdminAssign"
            scheduleInfo     = $scheduleInfo
        }
    }

    if ($justification) {
        $requestBody.properties.justification = $justification
    }
    #endregion Build request body

    #region Send request
    $restUri = "$base/$scope/providers/Microsoft.Authorization/roleEligibilityScheduleRequests/$($requestName)?api-version=2020-10-01"

    $response = Invoke-AzRestMethod -Uri $restUri -Method PUT -Payload ($requestBody | ConvertTo-Json -Depth 10) -ErrorAction Stop

    if ($response.StatusCode -notin 200, 201) {
        $errorContent = $response.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
        $errorMessage = if ($errorContent.error.message) { $errorContent.error.message } else { $response.Content }
        throw "$($MyInvocation.MyCommand)`: Failed to create role eligibility assignment. Status: $($response.StatusCode). Error: $errorMessage"
    }

    $result = $response.Content | ConvertFrom-Json
    #endregion Send request

    #region Return result
    [PSCustomObject]@{
        Id                 = $result.id
        Name               = $result.name
        Status             = $result.properties.status
        PrincipalId        = $result.properties.principalId
        RoleDefinitionId   = $result.properties.roleDefinitionId
        Scope              = $result.properties.scope
        RequestType        = $result.properties.requestType
        StartDateTime      = $result.properties.scheduleInfo.startDateTime
        ExpirationType     = $result.properties.scheduleInfo.expiration.type
        ExpirationDuration = $result.properties.scheduleInfo.expiration.duration
        ExpirationEndDate  = $result.properties.scheduleInfo.expiration.endDateTime
        CreatedOn          = $result.properties.createdOn
    }
    #endregion Return result
}

function Set-PIMResourceRoleAssignmentSetting {
    <#
    .SYNOPSIS
    Configures PIM assignment settings for a specified Azure resource role.

    .DESCRIPTION
    This function updates Privileged Identity Management (PIM) policy settings for a specified Azure resource role.
    It can configure settings such as justification requirements, authentication context requirements, and approval settings.

    .PARAMETER scope
    The Azure resource scope where the role policy will be updated.
    Examples:
    - Subscription: "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    - Resource Group: "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/myRG"

    .PARAMETER roleName
    The name of the Azure role to configure. Use this parameter if you know the role name (e.g., "Reader", "Contributor", "Owner").
    Either roleName or roleId must be specified.

    .PARAMETER roleId
    The object ID (GUID) of the role definition.
    Either roleName or roleId must be specified.

    .PARAMETER requireJustification
    Whether to require justification when activating the role.
    Defaults to $false (no justification required).

    .PARAMETER requireAuthenticationContext
    Whether to require a Conditional Access authentication context when activating the role.
    Defaults to $true (authentication context required).

    .PARAMETER authenticationContextId
    The ID of the Conditional Access authentication context to require.

    .PARAMETER requireApproval
    Whether to require approval when activating the role.
    Defaults to $false (no approval required).

    .PARAMETER approverGroupIds
    Array of group IDs that can approve activation requests.
    Only used if requireApproval is $true.

    .PARAMETER allowPermanentAssignment
    Whether to allow permanent eligible assignments (no expiration).
    Defaults to $true (eligible assignments will not expire based on policy defaults).

    .EXAMPLE
    Set-PIMResourceRoleAssignmentSetting -scope "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -roleName "Owner"

    Configures Owner role PIM settings with defaults: no justification required, no approval required.

    .EXAMPLE
    Set-PIMResourceRoleAssignmentSetting -scope "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -roleName "Contributor" -requireJustification $true -authenticationContextId "c2"

    Configures Contributor role PIM settings requiring justification and authentication context "c2".

    .EXAMPLE
    Set-PIMResourceRoleAssignmentSetting -scope "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -roleName "Owner" -requireApproval $true -approverGroupIds @("group-id-1", "group-id-2")

    Configures Owner role PIM settings requiring approval from specified groups.

    .EXAMPLE
    Set-PIMResourceRoleAssignmentSetting -scope "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -roleName "Reader" -requireAuthenticationContext $false

    Configures Reader role PIM settings with no authentication context requirement.
    #>

    [CmdletBinding(DefaultParameterSetName = "roleName")]
    param (
        [Parameter(Mandatory = $true)]
        [string] $scope,

        [Parameter(ParameterSetName = "roleName")]
        [string] $roleName,

        [Parameter(Mandatory = $true, ParameterSetName = "roleId")]
        [string] $roleId,

        [bool] $requireJustification = $false,

        [bool] $requireAuthenticationContext = $true,

        [string] $authenticationContextId,

        [bool] $requireApproval = $false,

        [string[]] $approverGroupIds,

        [bool] $allowPermanentAssignment = $true
    )

    #region Authentication check
    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction SilentlyContinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand)`: Authentication needed. Please call Connect-AzAccount."
    }
    #endregion Authentication check

    #region Normalize scope
    $scope = $scope.TrimStart('/')
    #endregion Normalize scope

    #region Get role definition ID and policy assignment
    $base = "https://management.azure.com"
    $endpoint = "$base/$scope/providers/Microsoft.Authorization"

    if (!$roleName -and !$roleId) {
        # interactive role selection
        $restUri = "$endpoint/roleDefinitions?api-version=2022-04-01"
        $allRolesResponse = (Invoke-AzRestMethod -Uri $restUri -ErrorAction Stop).Content | ConvertFrom-Json

        if (!$allRolesResponse.value -or $allRolesResponse.value.Count -eq 0) {
            throw "$($MyInvocation.MyCommand)`: No roles found at scope '/$scope'."
        }

        $selectedRole = $allRolesResponse.value | Select-Object @{N = 'RoleName'; E = { $_.properties.roleName } }, @{N = 'Description'; E = { $_.properties.description } }, @{N = 'Id'; E = { $_.name } } | Sort-Object RoleName | Out-GridView -Title "Select IAM role for scope: /$scope" -OutputMode Single

        if (!$selectedRole) {
            throw "$($MyInvocation.MyCommand)`: No role selected."
        }

        $roleName = $selectedRole.RoleName
    }

    if ($roleName) {
        $restUri = "$endpoint/roleDefinitions?api-version=2022-04-01&`$filter=roleName eq '$roleName'"
        $roleDefResponse = (Invoke-AzRestMethod -Uri $restUri -ErrorAction Stop).Content | ConvertFrom-Json

        if (!$roleDefResponse.value -or $roleDefResponse.value.Count -eq 0) {
            throw "$($MyInvocation.MyCommand)`: Role '$roleName' not found at scope '/$scope'."
        }

        $roleDefinitionIdFull = $roleDefResponse.value[0].id
    } else {
        $roleDefinitionIdFull = "/$scope/providers/Microsoft.Authorization/roleDefinitions/$roleId"
    }

    # get the policy assignment for this role
    $restUri = "$endpoint/roleManagementPolicyAssignments?api-version=2020-10-01&`$filter=roleDefinitionId eq '$roleDefinitionIdFull'"
    $policyAssignmentResponse = (Invoke-AzRestMethod -Uri $restUri -ErrorAction Stop).Content | ConvertFrom-Json

    if (!$policyAssignmentResponse.value -or $policyAssignmentResponse.value.Count -eq 0) {
        throw "$($MyInvocation.MyCommand)`: No PIM policy assignment found for role at scope '/$scope'."
    }

    $policyId = $policyAssignmentResponse.value[0].properties.policyId
    $policyName = ($policyId -split '/')[-1]
    #endregion Get role definition ID and policy assignment

    #region Get current policy settings
    $restUri = "$base/$scope/providers/Microsoft.Authorization/roleManagementPolicies/$($policyName)?api-version=2020-10-01"
    $currentPolicyResponse = (Invoke-AzRestMethod -Uri $restUri -ErrorAction Stop).Content | ConvertFrom-Json
    $currentRules = $currentPolicyResponse.properties.rules

    # parse current settings
    $currentEnablementRule = $currentRules | Where-Object { $_.id -eq "Enablement_EndUser_Assignment" }
    $currentAuthContextRule = $currentRules | Where-Object { $_.id -eq "AuthenticationContext_EndUser_Assignment" }
    $currentApprovalRule = $currentRules | Where-Object { $_.id -eq "Approval_EndUser_Assignment" }
    $currentExpirationRule = $currentRules | Where-Object { $_.id -eq "Expiration_Admin_Eligibility" }

    $currentRequireJustification = $currentEnablementRule.enabledRules -contains "Justification"
    $currentRequireAuthContext = [bool]$currentAuthContextRule.isEnabled
    $currentAuthContextId = $currentAuthContextRule.claimValue
    $currentRequireApproval = [bool]$currentApprovalRule.setting.isApprovalRequired
    $currentAllowPermanent = !$currentExpirationRule.isExpirationRequired
    #endregion Get current policy settings

    #region Build rules array
    [System.Collections.Generic.List[object]] $rules = @()

    # enablement rule for end user assignment (activation)
    $enabledRules = @()
    if ($requireJustification) {
        $enabledRules += "Justification"
    }
    # note: MFA is typically handled via authentication context, so we don't add it here by default

    $rules.Add(@{
            id           = "Enablement_EndUser_Assignment"
            ruleType     = "RoleManagementPolicyEnablementRule"
            target       = @{
                caller     = "EndUser"
                operations = @("All")
                level      = "Assignment"
            }
            enabledRules = $enabledRules
        })

    # authentication context rule
    $rules.Add(@{
            id         = "AuthenticationContext_EndUser_Assignment"
            ruleType   = "RoleManagementPolicyAuthenticationContextRule"
            target     = @{
                caller     = "EndUser"
                operations = @("All")
                level      = "Assignment"
            }
            isEnabled  = $requireAuthenticationContext
            claimValue = if ($requireAuthenticationContext) { $authenticationContextId } else { "" }
        })

    # approval rule
    $approvalSetting = @{
        isApprovalRequired               = $requireApproval
        isApprovalRequiredForExtension   = $false
        isRequestorJustificationRequired = $requireJustification
        approvalMode                     = "SingleStage"
        approvalStages                   = @()
    }

    if ($requireApproval -and $approverGroupIds) {
        $primaryApprovers = @()
        foreach ($groupId in $approverGroupIds) {
            $primaryApprovers += @{
                id          = $groupId
                description = ""
                isBackup    = $false
                userType    = "Group"
            }
        }

        $approvalSetting.approvalStages = @(
            @{
                approvalStageTimeOutInDays      = 1
                isApproverJustificationRequired = $true
                escalationTimeInMinutes         = 0
                primaryApprovers                = $primaryApprovers
                isEscalationEnabled             = $false
            }
        )
    }

    $rules.Add(@{
            id       = "Approval_EndUser_Assignment"
            ruleType = "RoleManagementPolicyApprovalRule"
            target   = @{
                caller     = "EndUser"
                operations = @("All")
                level      = "Assignment"
            }
            setting  = $approvalSetting
        })

    # expiration rule for admin eligible assignment (permanent assignment setting)
    $rules.Add(@{
            id                   = "Expiration_Admin_Eligibility"
            ruleType             = "RoleManagementPolicyExpirationRule"
            target               = @{
                caller     = "Admin"
                operations = @("All")
                level      = "Eligibility"
            }
            isExpirationRequired = !$allowPermanentAssignment
            maximumDuration      = "P365D"
        })
    #endregion Build rules array

    #region Send update request
    $requestBody = @{
        properties = @{
            rules = $rules
        }
    }

    $restUri = "$base/$scope/providers/Microsoft.Authorization/roleManagementPolicies/$($policyName)?api-version=2020-10-01"

    $response = Invoke-AzRestMethod -Uri $restUri -Method PATCH -Payload ($requestBody | ConvertTo-Json -Depth 20) -ErrorAction Stop

    if ($response.StatusCode -notin 200, 201) {
        $errorContent = $response.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
        $errorMessage = if ($errorContent.error.message) { $errorContent.error.message } else { $response.Content }
        throw "$($MyInvocation.MyCommand)`: Failed to update role management policy. Status: $($response.StatusCode). Error: $errorMessage"
    }

    $result = $response.Content | ConvertFrom-Json
    #endregion Send update request

    #region Warning about changed settings
    $displayRoleName = if ($roleName) { $roleName } else { $roleId }
    $changesDetected = $false

    $msg = @()

    if ($currentRequireJustification -ne $requireJustification) {
        $changesDetected = $true
        $msg += "  - Require justification: $currentRequireJustification -> $requireJustification"
    }

    if ($currentRequireAuthContext -ne $requireAuthenticationContext) {
        $changesDetected = $true
        $msg += "  - Require authentication context: $currentRequireAuthContext -> $requireAuthenticationContext"
    }

    if ($requireAuthenticationContext -and $currentAuthContextId -ne $authenticationContextId) {
        $changesDetected = $true
        $msg += "  - Authentication context ID: $currentAuthContextId -> $authenticationContextId"
    }

    if ($currentRequireApproval -ne $requireApproval) {
        $msg += "  - Require approval: $currentRequireApproval -> $requireApproval"
    }

    if ($currentAllowPermanent -ne $allowPermanentAssignment) {
        $changesDetected = $true

        $msg += "  - Allow permanent assignment: $currentAllowPermanent -> $allowPermanentAssignment"
    }

    if ($changesDetected) {
        Write-Warning "PIM assignment settings changed for role '$displayRoleName' at scope '/$scope':`n$($msg -join "`n")"
    } else {
        Write-Warning "No changes detected in PIM assignment settings for role '$displayRoleName' at scope '/$scope'."
    }
    #endregion Warning about changed settings

    #region Return result
    [PSCustomObject]@{
        PolicyId                     = $result.id
        PolicyName                   = $result.name
        Scope                        = $result.properties.scope
        RequireJustification         = $requireJustification
        RequireAuthenticationContext = $requireAuthenticationContext
        AuthenticationContextId      = if ($requireAuthenticationContext) { $authenticationContextId } else { $null }
        RequireApproval              = $requireApproval
        AllowPermanentAssignment     = $allowPermanentAssignment
        LastModifiedDateTime         = $result.properties.lastModifiedDateTime
    }
    #endregion Return result
}

Export-ModuleMember -function Get-PIMAccountEligibleMemberOf, Get-PIMDirectoryRoleAssignmentSetting, Get-PIMDirectoryRoleEligibleAssignment, Get-PIMGraphTokenWithClaim, Get-PIMGroup, Get-PIMGroupEligibleAssignment, Get-PIMManagementGroupEligibleAssignment, Get-PIMMyActiveDirectoryRole, Get-PIMMyActiveResourceRole, Get-PIMMyEligibleDirectoryRole, Get-PIMMyEligibleResourceRole, Get-PIMResourceRoleAssignmentSetting, Get-PIMSubscriptionEligibleAssignment, Get-PIMSupportedGroup, Invoke-PIMDirectoryRoleActivation, Invoke-PIMResourceRoleActivation, New-PIMResourceEligibleRoleAssignment, Set-PIMResourceRoleAssignmentSetting

Export-ModuleMember -alias Activate-PIMDirectoryRole, Activate-PIMResourceRole, Get-AzureAccountEligibleMemberOf, ipdr, iprr
