function Get-IntuneConfPolicyAssignmentSummaryReport {
    <#
    .SYNOPSIS
    Function returns assign status of all configuration policies.

    .DESCRIPTION
    Function returns assign status of all configuration policies.

    .EXAMPLE
    Get-IntuneConfPolicyAssignmentSummaryReport

    Returns assign status of all configuration policies
    #>

    [CmdletBinding()]
    param ()

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-MgGraph."
    }

    $finalResult = [System.Collections.Generic.List[Object]]::new()

    do {
        $tmpFile = (Join-Path $env:TEMP (Get-Random))

        $param = @{
            OutFile     = $tmpFile
            Top         = 25
            ErrorAction = "Stop"
        }
        if ($finalResult.count) {
            $param.skip = $finalResult.count
        }

        # command doesn't support -All hence we need to do pagination ourself
        Get-MgBetaDeviceManagementReportConfigurationPolicyNonComplianceSummaryReport @param

        $result = Get-Content $tmpFile -Raw | ConvertFrom-Json

        Remove-Item $tmpFile -Force

        $columnList = $result.Schema.Column

        $result.Values | % {
            $finalResult.add($_)
        }

        $totalCount = $result.TotalRowCount
    } while ($finalResult.count -lt $totalCount)

    # convert the returned array of values to psobject
    $finalResult = $finalResult | % {
        $valueList = $_
        $property = [ordered]@{}
        $i = 0
        $columnList | % {
            $property.$_ = $valueList[$i]
            ++$i
        }
        New-Object -TypeName PSObject -Property $property
    }

    #region get total devices count per platforms used in the report
    $platformDeviceCount = @{}

    switch (($finalResult.UnifiedPolicyPlatformType | select -Unique)) {
        { $_ -contains "Windows81AndLater" } {
            Get-MgDeviceManagementManagedDevice -Filter "OperatingSystem eq 'Windows' and ManagedDeviceOwnerType eq 'company'" -All -CountVariable windows81AndLaterDeviceCount

            $platformDeviceCount.Windows81AndLater = $windows81AndLaterDeviceCount
        }

        { $_ -contains "Windows10" } {
            Get-MgDeviceManagementManagedDevice -Filter "OperatingSystem eq 'Windows' and ManagedDeviceOwnerType eq 'company' and startswith(OSVersion,'10.')" -All -CountVariable windows10DeviceCount

            $platformDeviceCount.Windows10 = $windows10DeviceCount
        }

        { $_ -contains "androidWorkProfile" } {
            Get-MgDeviceManagementManagedDevice -Filter "OperatingSystem eq 'Android' and DeviceEnrollmentType eq 'UserEnrollment'" -All -CountVariable androidWorkProfileDeviceCount

            $platformDeviceCount.androidWorkProfile = $androidWorkProfileDeviceCount
        }

        # {$_ -contains "Android"} {
        #     Get-MgDeviceManagementManagedDevice -Filter "OperatingSystem eq 'Android' and DeviceEnrollmentType eq 'AndroidEnterpriseFullyManaged'" -All -CountVariable androidDeviceCount
        # }

        { $_ -contains "macOS" } {
            Get-MgDeviceManagementManagedDevice -Filter "OperatingSystem eq 'macOS'" -All -CountVariable macOSDeviceCount

            $platformDeviceCount.macOS = $macOSDeviceCount
        }

        default {
            Write-Warning "Undefined policy platform '$_'"
        }
    }
    #endregion get total devices count per platforms used in the report

    function _GetFailedDevicePercentage {
        # calculates percentage of problematic devices per policy
        param ($platform, $failedDeviceCount)

        if ($failedDeviceCount -eq 0) { return 0 }

        $allDeviceCount = $platformDeviceCount.$platform

        if (!$allDeviceCount) {
            Write-Warning "Missing '$platform' devices count. Unable to calculate the percentage."
            return 0
        }

        [Math]::Round($failedDeviceCount / $allDeviceCount * 100, 2)
    }

    # return results enhanced with failure percentage
    $finalResult | % {
        $resultLine = $_
        $resultLine | select *, @{n = 'FailedDevicePercentage'; e = { _GetFailedDevicePercentage -platform $resultLine.UnifiedPolicyPlatformType -failedDeviceCount $resultLine.NumberOfNonCompliantOrErrorDevices } }, @{n = 'ConflictedDevicePercentage'; e = { _GetFailedDevicePercentage -platform $resultLine.UnifiedPolicyPlatformType -failedDeviceCount $resultLine.NumberOfConflictDevices } }, @{n = 'NumberOfAllDevices'; e = { $platformDeviceCount.($resultLine.UnifiedPolicyPlatformType) } }
    }
}