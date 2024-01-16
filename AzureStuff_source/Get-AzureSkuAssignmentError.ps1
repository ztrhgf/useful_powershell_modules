function Get-AzureSkuAssignmentError {
    <#
    .SYNOPSIS
    Function returns users that have problems with licenses assignment.

    .DESCRIPTION
    Function returns users that have problems with licenses assignment.
    #>

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): The context is invalid. Please login using Connect-MgGraph."
    }

    $userWithLicenseProblem = Get-MgUser -Property UserPrincipalName, Id, LicenseAssignmentStates -All | ? { $_.LicenseAssignmentStates.state -eq 'error' }

    foreach ($user in $userWithLicenseProblem) {
        $errorLicense = $user.LicenseAssignmentStates | ? State -EQ "Error"

        foreach ($license in $errorLicense) {
            [PSCustomObject]@{
                UserPrincipalName   = $user.UserPrincipalName
                UserId              = $user.Id
                LicError            = $license.Error
                AssignedByGroup     = $license.AssignedByGroup
                AssignedByGroupName = (if ($license.AssignedByGroup) { (Get-MgGroup -GroupId $license.AssignedByGroup -Property DisplayName).DisplayName })
                LastUpdatedDateTime = $license.LastUpdatedDateTime
                SkuId               = $license.SkuId
                SkuName             = (Get-MgSubscribedSku -Property SkuPartNumber, SkuId -All | ? { $_.SkuId -eq $license.SkuId } | select -ExpandProperty SkuPartNumber)
            }
        }
    }

    <# logictejsi by bylo jit shora dolu (group > user), ale tam je problem s vracenim potrebnych dat
    Get-MgGroup -Property Id, DisplayName, AssignedLicenses, LicenseProcessingState, MembersWithLicenseErrors -Filter "HasMembersWithLicenseErrors eq true" | % {
        $groupId = $_.Id
        # kvuli bugu je potreba delat primy api call namisto pouziti property MembersWithLicenseErrors (je prazdna)
        Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId/membersWithLicenseErrors" -OutputType PSObject | select -ExpandProperty value
    }
    #>
}