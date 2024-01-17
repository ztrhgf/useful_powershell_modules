function Get-AzureGroupMemberRecursive {
    <#
    .SYNOPSIS
    Function for getting Azure group members recursively.

    .DESCRIPTION
    Function for getting Azure group members recursively.

    Some advanced filtering options are available.

    .PARAMETER id
    Id of the group whose members you want to retrieve.

    .PARAMETER excludeDisabled
    Switch for excluding disabled members from the output.

    .PARAMETER includeNestedGroup
    Switch for including nested groups in the output (otherwise just their members will be included).

    .PARAMETER allowedMemberType
    What type of members should be outputted.

    Available options: 'User', 'Device', 'All'.

    By default 'All'.

    .EXAMPLE
    Get-AzureGroupMemberRecursive -groupId 330a6343-da12-4999-bf87-a0ae60a68bbc

    .NOTES
    Requires following graph modules: Microsoft.Graph.Groups, Microsoft.Graph.Authentication, Microsoft.Graph.DirectoryObjects
    #>

    [Alias("Get-MgGroupMemberRecursive")]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias("GroupId")]
        [guid] $id,

        [switch] $excludeDisabled,

        [switch] $includeNestedGroup,

        [ValidateSet('User', 'Device', 'All')]
        [string] $allowedMemberType = 'All'
    )

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): The context is invalid. Please login using Connect-MgGraph."
    }

    foreach ($member in (Get-MgGroupMember -GroupId $id -All)) {
        $memberType = $member.AdditionalProperties["@odata.type"].split('.')[-1]
        $memberId = $member.Id

        if ($memberType -eq "group") {
            if ($includeNestedGroup) {
                $member | Expand-MgAdditionalProperties
            }

            $param = @{
                allowedMemberType = $allowedMemberType
            }
            if ($includeDisabled) { $param.includeDisabled = $true }

            Write-Verbose "Expanding members of group $memberId"
            Get-AzureGroupMemberRecursive -Id $memberId @param
        } else {
            if ($allowedMemberType -ne 'All' -and $memberType -ne $allowedMemberType) {
                Write-Verbose "Skipping $memberType member $memberId, because not of $allowedMemberType type."
                continue
            }

            if ($excludeDisabled) {
                $accountEnabled = (Get-MgDirectoryObject -DirectoryObjectId $memberId -Property accountEnabled).AdditionalProperties.accountEnabled
                if (!$accountEnabled) {
                    Write-Verbose "Skipping $memberType member $memberId, because not enabled."
                    continue
                }
            }

            $member | Expand-MgAdditionalProperties
        }
    }
}

function Get-AzureGroupSettings {
    <#
    .SYNOPSIS
    Function for getting group settings.
    Official Get-MgGroup -Property Settings doesn't return anything for some reason.

    .DESCRIPTION
    Function for getting group settings.
    Official Get-MgGroup -Property Settings doesn't return anything for some reason.

    .PARAMETER groupId
    Group ID.

    .EXAMPLE
    Get-AzureGroupSettings -groupId 01c19ec3-e1bb-44f3-ab36-86071b745375

    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $groupId
    )

    Invoke-MgGraphRequest -Uri "v1.0/groups/$groupId/settings" -OutputType PSObject | select -exp value | select *, @{n = 'ValuesAsObject'; e = {
            # return settings values as proper hashtable
            $hash = @{}
            $_.Values | % { $hash.($_.name) = $_.value }
            $hash
        }
    } #-ExcludeProperty Values
}

function Set-AzureRingGroup {
    <#
    .SYNOPSIS
    Function for dynamically setting members of specified "ring" groups based on the provided users list (members of the rootGroup) and the members per group percent ratio (ringGroupConfig).

    Useful if you want to deploy some feature gradually (ring by ring).

    "Ring" group concept is inspired by Intune Autopatch deployment rings.

    .DESCRIPTION
    Function for dynamically setting members of specified "ring" groups based on the provided users list (members of the rootGroup) and the members per group percent ratio (ringGroupConfig).

    Useful if you want to deploy some feature gradually (ring by ring).

    "Ring" group concept is inspired by Intune Autopatch deployment rings.

    With each function run, members and their ratio is checked and a rebalance of members is made if needed.

    Ring groups can contain only accounts that are members of the root group too!

    Ring groups description will be automatically updated with each run of this function. It will contain date of the last update and some generated text about how many percent of the root group this group contains.

    .PARAMETER rootGroup
    Id of the Azure group which members should be distributed across all ring groups based on the percent weight specified in the "ringGroupConfig".

    Members are searched recursively! Only users or devices accounts are used based on 'memberType'.

    .PARAMETER ringGroupConfig
    Ordered hashtable where keys are IDs of the Azure "ring" groups and values are integers representing percent of the "rootGroup" group members this "ring" group should contain.
    Sum of the values must be 100 at total.

    Example:
    [ordered]@{
        'bcf239e9-6a5e-4de0-baf4-c14bda4c0571' = 5 # ring_1
        '19fe5c4c-7568-43a3-bd21-f95cb5547366' = 15 # ring_2
        '0db6da9f-c224-4252-a7dc-c31d55b3acb3' = 80 # ring_3
    }

    .PARAMETER forceRecalculate
    Use if you want to force members check even though count of the root group members is the same as of all ring groups members (to overwrite manual edits etc)

    .PARAMETER firstRingGroupMembersSetManually
    Switch to specify that first group in ringGroupConfig is being manually set a.k.a skipped in re-balancing process.
    Therefore its value in ringGroupConfig must be set to 0 (because members are added manually).
    Percent weight (specified in ringGroupConfig) of the rest of the ring groups is used only for re-balancing users that are non-first-ring-group members.

    .PARAMETER skipUnderscoreInNameCheck
    Switch for skipping check that all "ring" groups that have dynamically set members have '_' prefix in their name (name convention).

    .PARAMETER includeDisabled
    Switch for including also disabled members of the root group, otherwise just enabled will be used to fill the "ring" groups.

    .PARAMETER skipDescriptionUpdate
    Switch for not modifying ring groups description.

    .PARAMETER memberType
    Type of the "rootGroup" you want to set on "ring" groups.

    Possible values: User, Device.

    By default 'User'.

    .EXAMPLE
    # group whose members will be distributed between ring groups
    $rootGroup = "330a6543-da12-4999-bf87-a0ae60g28bbc"
    # ring groups configuration
    $ringGroupConfig = [ordered]@{
        # manually set members
        '9e6be2e2-c050-4887-b14c-e612a1b4bb48' = 0 # ring_0
        # automatically set members
        'bcf239e9-6a5e-4de0-baf4-c14bda4c0a71' = 5 # ring_1
        '19fe5c4c-7568-43a3-bd21-f95cb5547766' = 15 # ring_2
        '0db6da9f-c224-4252-a7dc-c31d55b9acb3' = 80 # ring_3
    }

    Set-AzureRingGroup -rootGroup $rootGroup -ringGroupConfig $ringGroupConfig -firstRingGroupMembersSetManually

    Members of the root group (minus members of the first "ring" group) will be distributed across rest of the "ring" groups by percent ratio selected in the $ringGroupConfig.
    Members of the first "ring" group stay intact.
    In case current "ring" groups members count doesn't correspond to the percent specified in the $ringGroupConfig, members will be removed/added accordingly.

    .EXAMPLE
    # group whose members will be distributed between ring groups
    $rootGroup = "330a6543-da12-4999-bf87-a0ae60g28bbc"
    # ring groups configuration
    $ringGroupConfig = [ordered]@{
        'bcf239e9-6a5e-4de0-baf4-c14bda4c0a71' = 5 # ring_1
        '19fe5c4c-7568-43a3-bd21-f95cb5547766' = 15 # ring_2
        '0db6da9f-c224-4252-a7dc-c31d55b9acb3' = 80 # ring_3
    }

    Set-AzureRingGroup -rootGroup $rootGroup -ringGroupConfig $ringGroupConfig

    Members of the root group will be distributed across the "ring" groups by percent ratio selected in the $ringGroupConfig.
    In case current "ring" groups members count doesn't correspond to the percent specified in the $ringGroupConfig, members will be removed/added accordingly.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [guid] $rootGroup,

        [Parameter(Mandatory = $true)]
        [System.Collections.Specialized.OrderedDictionary] $ringGroupConfig,

        [switch] $forceRecalculate,

        [switch] $firstRingGroupMembersSetManually,

        [switch] $skipUnderscoreInNameCheck,

        [switch] $includeDisabled,

        [switch] $skipDescriptionUpdate,

        [ValidateSet('User', 'Device')]
        [string] $memberType = 'User'
    )

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-MgGraph."
    }

    #region functions
    function _getGroupName {
        param ($id)

        return (Get-MgGroup -GroupId $id -Property displayname).displayname
    }

    function _getMemberName {
        param ($id)

        return (Get-MgDirectoryObject -DirectoryObjectId $id).AdditionalProperties.displayName
    }

    function _setRingGroupsDescription {
        "Updating ring groups description"
        $ringGroupConfig.Keys | % {
            $groupId = $_

            $value = $ringGroupConfig.$groupId
            $ring0GroupId = $($ringGroupConfig.Keys)[0]

            if ($firstRingGroupMembersSetManually -and $groupId -eq $ring0GroupId) {
                $description = "Contains selected $($memberType.ToLower()) members of the $(_getGroupName $rootGroup) group. Members are assigned manually. Last processed at $(Get-Date -Format 'yyyy.MM.dd_HH:mm')"
            } else {
                $description = "Contains cca $value% $($memberType.ToLower()) members of the $(_getGroupName $rootGroup) group. Members are assigned programmatically. Last processed at $(Get-Date -Format 'yyyy.MM.dd_HH:mm')"
            }

            Update-MgGroup -GroupId $groupId -Description $description
        }
    }
    #endregion functions

    if ($firstRingGroupMembersSetManually) {
        # first ring group has manually set members
        # some exceptions in checks etc needs to be made
        $ring0GroupId = $($ringGroupConfig.Keys)[0]
    } else {
        # first ring group has automatically set members (as the rest of the ring groups)
        # no extra treatment is needed
        $ring0GroupId = $null
    }

    #region checks
    # all groups exists
    $allGroupId = @()
    $allGroupId += $rootGroup
    $ringGroupConfig.Keys | % { $allGroupId += $_ }
    $allGroupId | % {
        $groupId = $_

        try {
            $null = [guid] $groupId
        } catch {
            throw "$groupId isn't valid group ID"
        }

        try {
            $null = Get-MgGroup -GroupId $groupId -Property displayname -ErrorAction Stop
        } catch {
            throw "Group with ID $groupId that is defined in `$ringGroupConfig doesn't exist"
        }
    }

    # all automatically filled ring groups should have '_' prefix (naming convention)
    if (!$skipUnderscoreInNameCheck) {
        $ringGroupConfig.Keys | % {
            $groupId = $_

            if (!$firstRingGroupMembersSetManually -or $groupId -ne $ring0GroupId) {
                $groupName = _getGroupName $groupId

                if ($groupName -notlike "_*") {
                    throw "Group $groupName ($groupId) doesn't have prefix '_'. It has dynamically set members therefore it should!"
                }
            }
        }
    }

    # beta ring group has 0% set as assigned members count
    if ($firstRingGroupMembersSetManually -and $ringGroupConfig[0] -ne 0) {
        throw "First group in `$ringGroupConfig is manually filled a.k.a. value must be set to 0 (now $($ringGroupConfig[0]))"
    }

    # sum of all ring groups assigned members percent is 100% at total
    $ringGroupPercentSum = $ringGroupConfig.Values | Measure-Object -Sum | select -ExpandProperty Sum
    if ($ringGroupPercentSum -ne 100) {
        throw "Total sum of groups percent has to be 100 (now $ringGroupPercentSum)"
    }
    #endregion checks

    # make a note that group was processed, by updating its description
    if (!$skipDescriptionUpdate) {
        _setRingGroupsDescription
    }

    # get all users/devices that should be assigned to the "ring" groups
    $rootGroupMember = Get-AzureGroupMemberRecursive -id $rootGroup -excludeDisabled:(!$includeDisabled) -allowedMemberType $memberType

    #region cleanup of members that are no longer in the root group or are placed in more than one group
    $memberOccurrence = @{}
    $ringGroupConfig.Keys | % {
        $groupId = $_
        Get-MgGroupMember -GroupId $groupId -All -Property Id | % {
            $memberId = $_.Id
            if ($memberId -notin $rootGroupMember.Id) {
                Write-Warning "Removing group's $(_getGroupName $groupId) member $(_getMemberName $memberId) (not in the root group)"
                Remove-MgGroupMemberByRef -GroupId $groupId -DirectoryObjectId $memberId
            } else {
                if ($memberOccurrence.$memberId) {
                    Write-Warning "Removing group's $(_getGroupName $groupId) member $(_getMemberName $memberId) (already member of the group $(_getGroupName $memberOccurrence.$memberId))"
                    Remove-MgGroupMemberByRef -GroupId $groupId -DirectoryObjectId $memberId
                } else {
                    $memberOccurrence.$memberId = $groupId
                }
            }
        }
    }
    #endregion cleanup of members that are no longer in the root group or are placed in more than one group

    $ringGroupsMember = $ringGroupConfig.Keys | % { Get-MgGroupMember -GroupId $_ -All -Property Id }

    $rootGroupMemberCount = $rootGroupMember.count
    $ringGroupsMemberCount = $ringGroupsMember.count
    if ($firstRingGroupMembersSetManually) {
        # set percent weight is calculated from all available members except the manually set members of the test (ring0) group
        $ring0GroupMember = Get-MgGroupMember -GroupId $ring0GroupId -All -Property Id
        $assignableRingGroupsMemberCount = $rootGroupMemberCount - $ring0GroupMember.count
    } else {
        $assignableRingGroupsMemberCount = $rootGroupMemberCount
    }

    if ($rootGroupMemberCount -eq $ringGroupsMemberCount -and !$forceRecalculate) {
        return "No change in members count detected. Exiting"
    }

    # contains users/devices that are members of the root group, but not of any ring group
    # plus users/devices that were removed from any ring group for redundancy a.k.a. should be relocate to another ring group
    $memberToRelocateList = New-Object System.Collections.ArrayList
    ($rootGroupMember).Id | % {
        if ($_ -notin $ringGroupsMember.Id) {
            $null = $memberToRelocateList.Add($_)
        }
    }

    # hashtable with group ids and number of members that should be added
    $groupWithMissingMember = @{}

    # remove obsolete/redundancy ring group members
    if ($assignableRingGroupsMemberCount -ne 0) {
        foreach ($groupId in $ringGroupConfig.Keys) {
            if ($firstRingGroupMembersSetManually -and $groupId -eq $ring0GroupId) {
                # ring0 group is manually filled, hence no checks on members count are needed
                continue
            }

            $groupMember = Get-MgGroupMember -GroupId $groupId -All -Property Id
            $groupCurrentMemberCount = $groupMember.count
            if ($groupCurrentMemberCount) {
                $groupCurrentWeight = [math]::round($groupCurrentMemberCount / $assignableRingGroupsMemberCount * 100)
            } else {
                $groupCurrentWeight = 0
            }

            $groupRequiredWeight = $ringGroupConfig.$groupId
            $groupRequiredMemberCount = [math]::round($assignableRingGroupsMemberCount / 100 * $groupRequiredWeight)
            if ($groupRequiredMemberCount -eq 0 -and $groupRequiredWeight -gt 0) {
                # assign at least one member
                $groupRequiredMemberCount = 1
            }

            if ($groupCurrentMemberCount -ne $groupRequiredMemberCount) {
                "Group $(_getGroupName $groupId) ($groupCurrentMemberCount member(s)) should contain $groupRequiredWeight% ($groupRequiredMemberCount member(s)) of all assignable ($assignableRingGroupsMemberCount) users/devices, but contains $groupCurrentWeight%"

                if ($groupCurrentMemberCount -gt $groupRequiredMemberCount) {
                    # remove some random users/devices
                    $memberToRelocate = Get-Random -InputObject $groupMember.Id -Count ($groupCurrentMemberCount - $groupRequiredMemberCount)

                    $memberToRelocate | % {
                        $memberId = $_

                        Write-Warning "Removing group's $(_getGroupName $groupId) member $(_getMemberName $memberId) (is over the set limit)"

                        Remove-MgGroupMemberByRef -GroupId $groupId -DirectoryObjectId $memberId

                        $null = $memberToRelocateList.Add($memberId)
                    }
                } else {
                    # make a note about how many members should be added (later, because at first I need to free up/remove them from their current groups)
                    $groupWithMissingMember.$groupId = $groupRequiredMemberCount - $groupCurrentMemberCount
                }
            }
        }
    }

    # add new members to ring groups that have less members than required
    if ($groupWithMissingMember.Keys) {
        # add some random users/devices from the pool of available users/devices
        # start with the group with least required members, because of the rounding there might not be enough of them for all groups and you want to have the testing groups filled
        foreach ($groupId in ($groupWithMissingMember.Keys | Sort-Object -Property { $ringGroupConfig.$_ })) {
            $memberToRelocateCount = $groupWithMissingMember.$groupId
            if ($memberToRelocateList.count -eq 0) {
                Write-Warning "There is not enough members left. Adding no members to the group $(_getGroupName $groupId) instead of $memberToRelocateCount"
            } else {
                if ($memberToRelocateList.count -lt $memberToRelocateCount) {
                    Write-Warning "There is not enough members left. Adding $($memberToRelocateList.count) instead of $memberToRelocateCount to the group $(_getGroupName $groupId)"
                    $memberToRelocateCount = $memberToRelocateList.count
                }

                $memberToAdd = Get-Random -InputObject $memberToRelocateList -Count $memberToRelocateCount

                $memberToAdd | % {
                    $memberId = $_

                    Write-Warning "Adding member $(_getMemberName $memberId) to the group $(_getGroupName $groupId)"

                    $params = @{
                        "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$memberId"
                    }
                    New-MgGroupMemberByRef -GroupId $groupId -BodyParameter $params

                    $null = $memberToRelocateList.Remove($memberId)
                }
            }
        }
    }

    if ($memberToRelocateList) {
        # this shouldn't happen?
        throw "There are still some unassigned users/devices left?!"
    }
}

Export-ModuleMember -function Get-AzureGroupMemberRecursive, Get-AzureGroupSettings, Set-AzureRingGroup

Export-ModuleMember -alias Get-MgGroupMemberRecursive
