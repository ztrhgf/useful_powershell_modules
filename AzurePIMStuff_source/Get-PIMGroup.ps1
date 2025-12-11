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