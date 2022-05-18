function Get-IntuneOverallComplianceStatus {
    <#
    .SYNOPSIS
    Function for getting overall device compliance status from Intune.

    .DESCRIPTION
    Function for getting overall device compliance status from Intune.

    .PARAMETER header
    Authentication header.

    Can be created via New-GraphAPIAuthHeader.

    .PARAMETER justProblematic
    Switch for outputting only non-compliant items.

    .EXAMPLE
    $header = New-GraphAPIAuthHeader -credential $cred
    Get-IntuneOverallComplianceStatus -header $header

    Will return compliance information for all devices in your Intune.

    .EXAMPLE
    $header = New-GraphAPIAuthHeader -credential $cred
    Get-IntuneOverallComplianceStatus -header $header -justProblematic

    Will return just information about non-compliant devices in your Intune.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable] $header
        ,
        [switch] $justProblematic
    )

    # helper hashtable for storing devices compliance data
    # just for performance optimization
    $deviceComplianceData = @{}

    # get compliant devices
    $URI = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$select=id&`$filter=complianceState eq 'compliant'"
    $compliantDevice = (Invoke-RestMethod -Headers $header -Uri $URI -Method Get).value

    # get overall compliance policies per-setting status
    $URI = 'https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicySettingStateSummaries'
    $complianceSummary = (Invoke-RestMethod -Headers $header -Uri $URI -Method Get).value
    $complianceSummary = $complianceSummary | select @{n = 'Name'; e = { ($_.settingName -split "\.")[-1] } }, nonCompliantDeviceCount, errorDeviceCount, conflictDeviceCount, id

    if ($justProblematic) {
        # preserve just problematic ones
        $complianceSummary = $complianceSummary | ? { $_.nonCompliantDeviceCount -or $_.errorDeviceCount -or $_.conflictDeviceCount }
    }

    if ($complianceSummary) {
        $complianceSummary | % {
            $complianceSettingId = $_.id

            Write-Verbose $complianceSettingId
            Write-Warning "Processing $($_.name)"

            # add help text, to help understand, what this compliance setting validates
            switch ($_.name) {
                'RequireRemainContact' { Write-Warning "`t- devices that haven't contacted Intune for last 30 days" }
                'RequireDeviceCompliancePolicyAssigned' { Write-Warning "`t- devices without any compliance policy assigned" }
                'ConfigurationManagerComplianceRequired' { Write-Warning "`t- devices that are not compliant in SCCM" }
            }

            # get devices, where this particular compliance setting is not ok
            $URI = "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicySettingStateSummaries/$complianceSettingId/deviceComplianceSettingStates?`$filter=NOT(state eq 'compliant')"
            $complianceStatus = (Invoke-RestMethod -Headers $header -Uri $URI -Method Get).value

            if ($justProblematic) {
                # preserve just problematic ones
                # omit devices that have some non compliant items but overall device status is compliant (i.e. ignore typically old, per user non-compliant statuses)
                $complianceStatus = $complianceStatus | ? { $_.state -ne "compliant" -and $_.DeviceId -notin $compliantDevice.Id }
            }

            # loop through all devices that are not compliant (get details) and output the result
            $deviceDetails = $complianceStatus | % {
                $deviceId = $_.deviceId
                $deviceName = $_.deviceName
                $userPrincipalName = $_.userPrincipalName

                Write-Verbose "Processing $deviceName with id: $deviceId and UPN: $userPrincipalName"

                #region get error details (if exists) for this particular device and compliance setting
                if (!($deviceComplianceData.$deviceName)) {
                    Write-Verbose "Getting compliance data for $deviceName"
                    $deviceComplianceData.$deviceName = Get-IntuneDeviceComplianceStatus -deviceId $deviceId -justProblematic -header $header
                }

                if ($deviceComplianceData.$deviceName) {
                    # get error details for this particular compliance setting
                    $errorDescription = $deviceComplianceData.$deviceName | ? { $_.setting -eq $complianceSettingId -and $_.userPrincipalName -eq $userPrincipalName -and $_.errorDescription -ne "No error code" } | select -ExpandProperty errorDescription -Unique
                }
                #endregion get error details (if exists) for this particular device and compliance setting

                # output result
                $_ | select deviceName, userPrincipalName, state, @{n = 'errDetails'; e = { $errorDescription } } | sort state, deviceName
            }

            # output result for this compliance setting
            [PSCustomObject]@{
                Name                    = $_.name
                NonCompliantDeviceCount = $_.nonCompliantDeviceCount
                ErrorDeviceCount        = $_.errorDeviceCount
                ConflictDeviceCount     = $_.conflictDeviceCount
                DeviceDetails           = $deviceDetails
            }
        }
    }
}