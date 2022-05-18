function Invoke-ReRegisterDeviceToIntune {
    <#
    .SYNOPSIS
    Function for repairing Intune join connection. Useful if you delete device from AAD etc.

    .DESCRIPTION
    Function for repairing Intune join connection. Useful if you delete device from AAD etc.

    .PARAMETER joinType
    Possible values are: 'hybridAADJoined', 'AADJoined', 'AADRegistered'

    .EXAMPLE
    Invoke-ReRegisterDeviceToIntune -joinType 'hybridAADJoined'

    .NOTES
    # https://docs.microsoft.com/en-us/azure/active-directory/devices/faq
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('hybridAADJoined', 'AADJoined', 'AADRegistered')]
        [string] $joinType
    )

    if ($joinType -eq 'hybridAADJoined') {
        dsregcmd.exe /debug /leave

        Write-Warning "Now manually synchronize device to Azure by running: Sync-ADtoAzure"
        $choice = ""
        while ($choice -notmatch "^[Y|N]$") {
            $choice = Read-Host "Continue? (Y|N)"
        }
        if ($choice -eq "N") {
            break
        }

        $result = dsregcmd.exe /debug /join
        if ($result -match "Join error subcode: error_missing_device") {
            throw "Join wasn't successful because device is not synchronized in AAD. Run Sync-ADtoAzure command, wait 10 minutes and than on client run: dsregcmd.exe /debug /join"
        } else {
            $result
        }
    } elseif ($joinType -eq 'AADJoined') {
        if (! ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
            throw "You don't have administrator rights"
        }

        dsregcmd.exe /forcerecovery

        "Sign out and sign in back to the device to complete the recovery"
    } else {
        "Go to Settings > Accounts > Access Work or School.`nSelect the account and select Disconnect.`nClick on '+ Connect' and register the device again by going through the sign in process."
    }
}