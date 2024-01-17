function Get-BitlockerEscrowStatusForAzureADDevices {
    <#
      .SYNOPSIS
      Retrieves bitlocker key upload status for Windows Azure AD devices

      .DESCRIPTION
      Use this report to determine which of your devices have backed up their bitlocker key to AzureAD (and find those that haven't and are at risk of data loss!).

      .NOTES
    https://msendpointmgr.com/2021/01/18/get-intune-managed-devices-without-an-escrowed-bitlocker-recovery-key-using-powershell/
    #>

    [cmdletbinding()]
    param()

    $null = Connect-MgGraph -Scopes BitLockerKey.ReadBasic.All, DeviceManagementManagedDevices.Read.All

    $recoveryKeys = @()
    $uri = "beta/informationProtection/bitlocker/recoveryKeys?`$select=id,createdDateTime,deviceId"
    do {
        $result = Invoke-MgGraphRequest -Uri $uri -OutputType PSObject
        $recoveryKeys += $result.value
        if ($result.'@odata.nextLink') {
            $uri = $result.'@odata.nextLink'
        } else {
            $uri = $null
        }
    } while ($uri)

    $aadDevices = @()
    $uri = "v1.0/deviceManagement/managedDevices?`$filter=operatingSystem eq 'Windows'&select=azureADDeviceId,deviceName,id,userPrincipalName,lastSyncDateTime,isEncrypted"
    do {
        $result = Invoke-MgGraphRequest -Uri $uri -OutputType PSObject
        $aadDevices += $result.value
        if ($result.'@odata.nextLink') {
            $uri = $result.'@odata.nextLink'
        } else {
            $uri = $null
        }
    } while ($uri)

    $aadDevices | select *, @{n = 'BitlockerKeysUploadedToAzureAD'; e = {
            $deviceId = $_.azureADDeviceId
            if ($deviceId -in $recoveryKeys.deviceId) { $true } else { $false } }
    }
}