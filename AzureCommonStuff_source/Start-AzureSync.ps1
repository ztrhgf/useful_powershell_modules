function Start-AzureSync {
    <#
        .SYNOPSIS
        Invoke Azure AD sync cycle command (Start-ADSyncSyncCycle) on the server where 'Azure AD Connect' is installed.

        .DESCRIPTION
        Invoke Azure AD sync cycle command (Start-ADSyncSyncCycle) on the server where 'Azure AD Connect' is installed.

        .PARAMETER Type
        Type of sync.

        Initial (full) or just delta.

        Delta is default.

        .PARAMETER ADSynchServer
        Name of the server where 'Azure AD Connect' is installed

        .EXAMPLE
        Start-AzureSync -ADSynchServer ADSYNCSERVER
        Invokes synchronization between on-premises AD and AzureAD on server ADSYNCSERVER by running command Start-ADSyncSyncCycle there.
    #>

    [Alias("Sync-ADtoAzure", "Start-AzureADSync")]
    [cmdletbinding()]
    param (
        [ValidateSet('delta', 'initial')]
        [string] $type = 'delta',

        [ValidateNotNullOrEmpty()]
        [string] $ADSynchServer
    )

    $ErrState = $false
    do {
        try {
            Invoke-Command -ScriptBlock { Start-ADSyncSyncCycle -PolicyType $using:type } -ComputerName $ADSynchServer -ErrorAction Stop | Out-Null
            $ErrState = $false
        } catch {
            $ErrState = $true
            Write-Warning "Start-AzureSync: Error in Sync:`n$_`nRetrying..."
            Start-Sleep 5
        }
    } while ($ErrState -eq $true)
}