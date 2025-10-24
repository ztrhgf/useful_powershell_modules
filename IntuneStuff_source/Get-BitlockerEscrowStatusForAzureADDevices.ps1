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

  $recoveryKeys = Invoke-MgGraphRequest -Uri "beta/informationProtection/bitlocker/recoveryKeys?`$select=createdDateTime,deviceId" | Get-MgGraphAllPages

  $aadDevices = Invoke-MgGraphRequest -Uri "v1.0/deviceManagement/managedDevices?`$filter=operatingSystem eq 'Windows'&select=azureADDeviceId,deviceName,id,userPrincipalName,isEncrypted,managedDeviceOwnerType,deviceEnrollmentType,enrolledDateTime" | Get-MgGraphAllPages

  $aadDevices | select *, @{n = 'ValidRecoveryBitlockerKeyInAzure'; e = {
      $deviceId = $_.azureADDeviceId
      $enrolledDateTime = $_.enrolledDateTime
      $validRecoveryKey = $recoveryKeys | ? { $_.deviceId -eq $deviceId -and $_.createdDateTime -ge $enrolledDateTime }
      if ($validRecoveryKey) { $true } else { $false } }
  }
}