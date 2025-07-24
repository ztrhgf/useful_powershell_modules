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