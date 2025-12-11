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