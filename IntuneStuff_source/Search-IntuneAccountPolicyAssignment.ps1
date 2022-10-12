
#requires -modules AzureAD
#requires -modules Microsoft.Graph.Intune
function Search-IntuneAccountPolicyAssignment {
    <#
    .SYNOPSIS
    Function for getting Intune policies, assigned (directly/indirectly) to selected account.
    Exclude assignments and assignments for 'All Users', 'All Devices' are taken in account by default when calculating the results.

    .DESCRIPTION
    Function for getting Intune policies, assigned (directly/indirectly) to selected account.
    Exclude assignments and assignments for 'All Users', 'All Devices' are taken in account by default when calculating the results.

    Intune Filters are ignored for now!

    .PARAMETER accountId
    ObjectID of the account you are getting assignments for.

    .PARAMETER skipAllUsersAllDevicesAssignments
    Switch. Hides all assignments for 'All Users' and 'All Devices'.
    A.k.a. just policies assigned to selected account (groups where he is member (directly or transitively)), will be outputted.

    .PARAMETER ignoreExcludes
    Switch. Ignore policies EXCLUDE assignments when calculating the results.

    By default if specified account is member of any excluded group, policy will be omitted.

    .PARAMETER justDirectGroupAssignments
    Switch. Usable only if accountId belongs to a group.
    Just assignments for this particular group will be shown. Not assignments for groups this group is member of or assignments for 'All Users' or 'All Devices'.

    But as a side effect assignments which would be otherwise ignored, because of exclude rule for parent group where this one is as a member will be shown!"

    .PARAMETER policyType
    Array of Intune policy types you want to search through.

    Possible values are:
    'ALL' to search through all policies.

    'app','appConfigurationPolicy','appProtectionPolicy','compliancePolicy','configurationPolicy','customAttributeShellScript','deviceEnrollmentConfiguration','deviceManagementPSHScript','deviceManagementShellScript','endpointSecurity','iosAppProvisioningProfile','iosUpdateConfiguration','policySet','remediationScript','sModeSupplementalPolicy','windowsAutopilotDeploymentProfile','windowsFeatureUpdateProfile','windowsQualityUpdateProfile','windowsUpdateRing' to search through just some policies subset.

    By default 'ALL' policies are searched.

    .PARAMETER intunePolicy
    Object as returned by Get-IntunePolicy function.
    Can be used if you make more searches to avoid getting Intune policies over and over again.

    .PARAMETER basicOverview
    Switch. Just some common subset of available policy properties will be gathered (id, displayName, lastModifiedDateTime, assignments).
    Makes the result more human readable.

    .PARAMETER flatOutput
    Switch. All Intune policies will be outputted as array instead of one psobject with policies divided into separate sections/object properties.
    Policy parent "type" is added as new property 'PolicyType' to each policy for filtration purposes.

    .EXAMPLE
    Connect-MSGraph
    Search-IntuneAccountPolicyAssignment -accountId a815da8b-6324-4feb-94ef-96723ba4fbf7 -justDirectGroupAssignments

    Get all Intune policies assigned DIRECTLY to specified GROUP account (a.k.a. NOT to groups where specified group is member of!). Policies assigned to 'All Users', 'All Devices' will be omitted. Policies where specified GROUP is excluded will be omitted!

    .EXAMPLE
    Connect-MSGraph
    Search-IntuneAccountPolicyAssignment -accountId a815da8b-6324-4feb-94ef-96723ba4fbf7 -policyType 'compliancePolicy','configurationPolicy'

    Get just 'compliancePolicy','configurationPolicy' Intune policies assigned to specified account (a.k.a. groups where he is member of (directly/transitively)). Policies assigned to 'All Users', 'All Devices' will be included. Policies where specified account (a.k.a. groups where he is member of (directly/transitively)) is excluded will be omitted!

    .EXAMPLE
    Connect-MSGraph
    Search-IntuneAccountPolicyAssignment -accountId a815da8b-6324-4feb-94ef-96723ba4fbf7

    Get all Intune policies assigned to specified account (a.k.a. groups where he is member of (directly/transitively)). Policies assigned to 'All Users', 'All Devices' will be included. Policies where specified account (a.k.a. groups where he is member of (directly/transitively)) is excluded will be omitted!

    .EXAMPLE
    Connect-MSGraph
    Search-IntuneAccountPolicyAssignment -accountId a815da8b-6324-4feb-94ef-96723ba4fbf7 -basicOverview

    Get all Intune policies assigned to specified account (a.k.a. groups where he is member of (directly/transitively)). Policies assigned to 'All Users', 'All Devices' will be included. Policies where specified account (a.k.a. groups where he is member of (directly/transitively)) is excluded will be omitted!

    Result will be one PSObject with policies saved in it's properties. And just subset of available properties for each policy will be gathered.

    .EXAMPLE
    Connect-MSGraph
    Search-IntuneAccountPolicyAssignment -accountId a815da8b-6324-4feb-94ef-96723ba4fbf7 -flatOutput

    Get all Intune policies assigned to specified account (a.k.a. groups where he is member of (directly/transitively)). Policies assigned to 'All Users', 'All Devices' will be included. Policies where specified account (a.k.a. groups where he is member of (directly/transitively)) is excluded will be omitted!

    Result will be array of policies.

    .EXAMPLE
    Connect-MSGraph
    # cache the Intune policies
    $intunePolicy = Get-IntunePolicy
    Search-IntuneAccountPolicyAssignment -accountId a815da8b-6324-4feb-94ef-96723ba4fbf7 -intunePolicy $intunePolicy -basicOverview
    Search-IntuneAccountPolicyAssignment -accountId 3465da8b-6325-daeb-94ef-56723ba4f5gt -intunePolicy $intunePolicy -basicOverview

    Do multiple searches using cached Intune policies.

    .EXAMPLE
    Connect-MSGraph
    $intunePolicy = Get-IntunePolicy -flatOutput
    Search-IntuneAccountPolicyAssignment -accountId a815da8b-6324-4feb-94ef-96723ba4fbf7 -intunePolicy $intunePolicy -basicOverview -flatOutput
    Search-IntuneAccountPolicyAssignment -accountId 3465da8b-6325-daeb-94ef-56723ba4f5gt -intunePolicy $intunePolicy -flatOutput

    Do multiple searches using cached Intune policies.

    .NOTES
    Requires function Get-IntunePolicy.
    #>

    [CmdletBinding()]
    [Alias("Search-IntuneAccountAppliedPolicy", "Get-IntuneAccountPolicyAssignment")]
    param (
        [Parameter(Mandatory = $true)]
        [string] $accountId,

        [switch] $skipAllUsersAllDevicesAssignments,

        [switch] $ignoreExcludes,

        [switch] $justDirectGroupAssignments,

        [ValidateSet('ALL', 'app', 'appConfigurationPolicy', 'appProtectionPolicy', 'compliancePolicy', 'configurationPolicy', 'customAttributeShellScript', 'deviceEnrollmentConfiguration', 'deviceManagementPSHScript', 'deviceManagementShellScript', 'endpointSecurity', 'iosAppProvisioningProfile', 'iosUpdateConfiguration', 'policySet', 'remediationScript', 'sModeSupplementalPolicy', 'windowsAutopilotDeploymentProfile', 'windowsFeatureUpdateProfile', 'windowsQualityUpdateProfile', 'windowsUpdateRing')]
        [ValidateNotNullOrEmpty()]
        [string[]] $policyType = 'ALL',

        $intunePolicy,

        [switch] $basicOverview,

        [switch] $flatOutput
    )

    Write-Warning "For now, assignment filters are ignored when deciding if assignment should be shown as applied!"

    if (!(Get-Module AzureAD) -and !(Get-Module AzureAD -ListAvailable)) {
        throw "Module AzureAD is missing"
    }
    if (!(Get-Module Microsoft.Graph.Intune) -and !(Get-Module Microsoft.Graph.Intune -ListAvailable)) {
        throw "Module Microsoft.Graph.Intune is missing"
    }

    #region helper functions
    # check whether there is at least one assignment that includes one of the groups searched account is member of and at the same time, there is none exclude rule
    function _isAssigned {
        $input | ? {
            $isAssigned = $false
            $isExcluded = $false

            $policy = $_

            Write-Verbose "Processing policy '$($policy.displayName)' ($($policy.id))"

            if (!$accountId) {
                # if no account specified, return all assignments
                return $true
            }

            foreach ($assignment in $policy.assignments) {
                # Write-Verbose "`tApplied to group(s): $($assignment.target.groupId -join ', ')"

                if (!$isAssigned -and ($assignment.target.groupId -in $accountMemberOfGroup.objectid -and $assignment.target.'@odata.type' -eq '#microsoft.graph.groupAssignmentTarget')) {
                    Write-Verbose "`t++  INCLUDE assignment for group $($assignment.target.groupId) exists"
                    $isAssigned = $true
                } elseif (!$isAssigned -and !$skipAllUsersAllDevicesAssignments -and ($assignment.target.'@odata.type' -eq '#microsoft.graph.allDevicesAssignmentTarget')) {
                    Write-Verbose "`t++  INCLUDE assignment for 'All devices' exists"
                    $isAssigned = $true
                } elseif (!$isAssigned -and !$skipAllUsersAllDevicesAssignments -and ($assignment.target.'@odata.type' -eq '#microsoft.graph.allLicensedUsersAssignmentTarget')) {
                    Write-Verbose "`t++  INCLUDE assignment for 'All users' exists"
                    $isAssigned = $true
                } elseif (!$ignoreExcludes -and $assignment.target.groupId -in $accountMemberOfGroup.objectid -and $assignment.target.'@odata.type' -eq '#microsoft.graph.exclusionGroupAssignmentTarget') {
                    Write-Verbose "`t--  EXCLUDE assignment for group $($assignment.target.groupId) exists"
                    $isExcluded = $true
                    break # faster processing, but INCLUDE assignments process after EXCLUDE ones won't be shown
                } else {
                    # this assignment isn't for searched account
                }
            }

            if ($isExcluded -or !$isAssigned) {
                Write-Verbose "`t--- NOT applied"
                return $false
            } else {
                Write-Verbose "`t+++ IS applied"
                return $true
            }
        }
    }
    #endregion helper functions

    #region get account group membership
    # assignment cannot be targeted to user/device but group, i.e. get account group membership
    $objectType = $null
    $accountObj = $null

    $accountObj = Get-AzureADObjectByObjectId -ObjectIds $accountId -Types group, user, device -ErrorAction Stop
    $objectType = $accountObj.ObjectType
    if (!$objectType) {
        throw "Undefined object. It is not user, group or device."
    }
    Write-Verbose "$accountId '$($accountObj.displayName)' is a $objectType"

    switch ($objectType) {
        'device' {
            if ($justDirectGroupAssignments) {
                Write-Warning "Parameter 'justDirectGroupAssignments' can be used only if group is searched. Ignoring."
            }

            Write-Verbose "Getting account transitive memberOf property"
            $accountMemberOfGroup = Invoke-MSGraphRequest -Url "https://graph.microsoft.com/v1.0/devices/$accountId/transitiveMemberOf?`$select=displayName,id" -ErrorAction Stop | Get-MSGraphAllPages | select @{n = 'ObjectId'; e = { $_.id } }, DisplayName

        }

        'user' {
            if ($justDirectGroupAssignments) {
                Write-Warning "Parameter 'justDirectGroupAssignments' can be used only if group is searched. Ignoring."
            }

            Write-Verbose "Getting account transitive memberOf property"
            $accountMemberOfGroup = Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/users/$accountId/transitiveMemberOf?`$select=displayName,id" -ErrorAction Stop | Get-MSGraphAllPages | select @{n = 'ObjectId'; e = { $_.id } }, DisplayName
        }

        'group' {
            if ($justDirectGroupAssignments) {
                Write-Warning "Just assignments for this particular group will be shown. Not assignments for groups this group is member of or assignments for 'All Users' or 'All Devices'. But as a side effect assignments which would be otherwise ignored, because of exclude rule for parent group where this one is as a member will be shown!"

                $skipAllUsersAllDevicesAssignments = $true

                # search just the group itself
                $accountMemberOfGroup = $accountObj | select ObjectId, DisplayName
            } else {
                Write-Verbose "Getting account transitive memberOf property"
                $accountMemberOfGroup = @()
                # add group itself
                $accountMemberOfGroup += $accountObj | select ObjectId, DisplayName
                # add group transitive memberof
                $accountMemberOfGroup += Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/groups/$accountId/transitiveMemberOf?`$select=displayName,id" -ErrorAction Stop | Get-MSGraphAllPages | select @{n = 'ObjectId'; e = { $_.id } }, DisplayName
            }
        }

        default {
            throw "Undefined object type $objectType"
        }
    }

    if (!$justDirectGroupAssignments) {
        if ($accountMemberOfGroup) {
            Write-Verbose "Account is member of group(s): $(($accountMemberOfGroup | % {$_.displayName + " (" + $_.ObjectId + ")"}) -join ', ')"
        } elseif ($objectType -ne 'group' -and !$accountMemberOfGroup -and $skipAllUsersAllDevicesAssignments) {
            Write-Warning "Account $accountId isn't member of any group and 'All Users', 'All Devices' assignments should be skipped. Stopping."

            return
        }
    }
    #endregion get account group membership

    # get Intune policies
    if (!$intunePolicy) {
        $param = @{
            policyType = $policyType
        }
        if ($flatOutput) { $param.flatOutput = $true }
        $intunePolicy = Get-IntunePolicy @param
    } else {
        Write-Verbose "Given IntunePolicy object will be used instead of calling Get-IntunePolicy. Therefore PolicyType parameter is ignored too."
        if ($flatOutput -and $intunePolicy -and !(($intunePolicy | select -First 1).PolicyType)) {
            throw "Given IntunePolicy object isn't 'flat' (created using Get-IntunePolicy -flatOutput)."
        }
    }

    #region filter & output Intune policies
    if ($flatOutput) {
        # I am working directly with array of policies
        # filter & output
        if ($basicOverview) {
            $intunePolicy | _isAssigned | select id, displayName, lastModifiedDateTime, assignments, policyType
        } else {
            $intunePolicy | _isAssigned
        }
    } else {
        # I am working with object, where policies are stored as values of this object properties (policy names)
        $resultProperty = [ordered]@{}

        $intunePolicy | Get-Member -MemberType NoteProperty | select -ExpandProperty name | % {
            $policyName = $_

            if ($intunePolicy.$policyName) {
                # filter out policies that are not assigned to searched account
                $assignedPolicy = $intunePolicy.$policyName | _isAssigned

                if ($assignedPolicy) {
                    if ($basicOverview) {
                        $assignedPolicy = $assignedPolicy | select id, displayName, lastModifiedDateTime, assignments
                    }

                    $resultProperty.$policyName = $assignedPolicy
                } else {
                    Write-Verbose "There is none policy of type '$policyName' assigned. Skipping"
                }
            } else {
                Write-Verbose "There is none policy of type '$policyName'. Skipping"
            }
        }

        # output filtered object
        New-Object -TypeName PSObject -Property $resultProperty
    }
    #endregion filter & output Intune policies
}