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

    function Get-AppsInstallSummaryReportPage {
        param ([int] $top, [int] $skip)

        $body = @{ top = $top; skip = $skip } | ConvertTo-Json
        $outputFile = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        try {
            Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/beta/deviceManagement/reports/microsoft.graph.getAppsInstallSummaryReport' -Body $body -ContentType 'application/json' -OutputFilePath $outputFile -ErrorAction Stop | Out-Null
            Get-Content -LiteralPath $outputFile -Raw -ErrorAction Stop | ConvertFrom-Json
        } finally {
            Remove-Item -LiteralPath $outputFile -Force -ErrorAction SilentlyContinue
        }
    }

    $finalResult = [System.Collections.Generic.List[Object]]::new()

    do {
        $result = Get-AppsInstallSummaryReportPage -top 25 -skip $finalResult.Count

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