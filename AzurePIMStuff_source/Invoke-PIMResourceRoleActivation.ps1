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