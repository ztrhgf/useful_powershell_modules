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