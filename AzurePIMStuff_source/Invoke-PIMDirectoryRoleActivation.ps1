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