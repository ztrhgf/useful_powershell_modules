function Get-HybridADJoinStatus {
    <#
    .SYNOPSIS
    Function returns computer's Hybrid AD Join status.

    .DESCRIPTION
    Function returns computer's Hybrid AD Join status.

    .PARAMETER computerName
    Name of the computer you want to get status of.

    .PARAMETER wait
    How many seconds should function wait when checking AAD certificates creation.

    .EXAMPLE
    Get-HybridADJoinStatus
    #>

    [CmdletBinding()]
    param (
        [string] $computerName,

        [int] $wait = 0
    )

    $param = @{
        scriptBlock  = {
            param ($wait)

            # check certificates
            Write-Verbose "Two valid certificates should exist in Computer Personal cert. store (issuer: MS-Organization-Access, MS-Organization-P2P-Access [$(Get-Date -Format yyyy)]"

            while (!($hybridJoinCert = Get-ChildItem 'Cert:\LocalMachine\My\' | ? { $_.Issuer -match "MS-Organization-Access|MS-Organization-P2P-Access \[\d+\]" }) -and $wait -gt 0) {
                Start-Sleep 1
                --$wait
                Write-Verbose $wait
            }

            # check certificate validity
            if ($hybridJoinCert) {
                $validHybridJoinCert = $hybridJoinCert | ? { $_.NotAfter -gt [datetime]::Now -and $_.NotBefore -lt [datetime]::Now }
            }

            # check AzureAd join status
            $dsreg = dsregcmd.exe /status
            if (($dsreg | Select-String "AzureAdJoined :") -match "YES") {
                ++$AzureAdJoined
            }

            if ($AzureAdJoined -and $validHybridJoinCert -and @($validHybridJoinCert).count -ge 2 ) {
                return $true
            } else {
                if (!$AzureAdJoined) {
                    Write-Warning "$env:COMPUTERNAME is not AzureAD joined"
                } elseif (!$hybridJoinCert) {
                    Write-Warning "AzureAD certificates doesn't exist"
                } elseif ($hybridJoinCert -and !$validHybridJoinCert) {
                    Write-Warning "AzureAD certificates exists but are expired"
                } elseif ($hybridJoinCert -and @($validHybridJoinCert).count -lt 2) {
                    Write-Warning "AzureAD certificates exists but one of them is expired"
                }

                return $false
            }
        }

        argumentList = $wait
    }

    if ($computerName -and $computerName -notin "localhost", $env:COMPUTERNAME) {
        $param.computerName = $computerName
    }

    Invoke-Command @param
}