function Get-IntuneAppInstallSummaryReport {
    <#
    .SYNOPSIS
    Function returns deploy status of all apps.

    .DESCRIPTION
    Function returns deploy status of all apps.

    .EXAMPLE
    Get-IntuneAppInstallSummaryReport

    Returns deploy status of all apps.
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
        Get-MgBetaDeviceManagementReportAppInstallSummaryReport @param

        $result = Get-Content $tmpFile -Raw | ConvertFrom-Json

        Remove-Item $tmpFile -Force

        $columnList = $result.Schema.Column

        $result.Values | % {
            $finalResult.add($_)
        }

        $totalCount = $result.TotalRowCount
    } while ($finalResult.count -lt $totalCount)


    # convert the returned array of values to psobject
    $finalResult | % {
        $valueList = $_
        $property = [ordered]@{}
        $i = 0
        $columnList | % {
            if ($_ -eq 'FailedDevicePercentage') {
                $property.$_ = [Math]::Round($valueList[$i], 2)
            } else {
                $property.$_ = $valueList[$i]
            }
            ++$i
        }
        New-Object -TypeName PSObject -Property $property
    }
}