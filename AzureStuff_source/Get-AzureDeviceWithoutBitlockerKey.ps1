function Get-AzureDeviceWithoutBitlockerKey {
    [CmdletBinding()]
    param ()

    Get-BitlockerEscrowStatusForAzureADDevices | ? { $_.BitlockerKeysUploadedToAzureAD -eq $false -and $_.userPrincipalName -and $_.lastSyncDateTime -and $_.isEncrypted }
}