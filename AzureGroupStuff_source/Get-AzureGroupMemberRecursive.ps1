#requires -modules Microsoft.Graph.Groups, Microsoft.Graph.Authentication, Microsoft.Graph.DirectoryObjects
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

    # list of ids of objects that were already written out, to skip duplicities
    $outputted = New-Object System.Collections.ArrayList

    foreach ($member in (Get-MgGroupMember -GroupId $id -All)) {
        $memberType = $member.AdditionalProperties["@odata.type"].split('.')[-1]
        $memberId = $member.Id

        if ($memberType -eq "group") {
            if ($includeNestedGroup) {
                if ($member.Id -notin $outputted) {
                    $null = $outputted.add($member.Id)
                    $member | Expand-MgAdditionalProperties
                } else {
                    # duplicity
                }
            }

            $param = @{
                allowedMemberType = $allowedMemberType
            }
            if ($excludeDisabled) { $param.excludeDisabled = $true }
            if ($includeNestedGroup) { $param.includeNestedGroup = $true }

            Write-Verbose "Expanding members of group $memberId"
            Get-AzureGroupMemberRecursive -id $memberId @param
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
            if ($member.Id -notin $outputted) {
                $null = $outputted.add($member.Id)
                $member | Expand-MgAdditionalProperties
            } else {
                # duplicity
            }
        }
    }
}