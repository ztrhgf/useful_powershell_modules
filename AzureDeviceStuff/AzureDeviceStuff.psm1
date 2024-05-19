function Get-AzureDeviceWithoutBitlockerKey {
    [CmdletBinding()]
    param ()

    Get-BitlockerEscrowStatusForAzureADDevices | ? { $_.BitlockerKeysUploadedToAzureAD -eq $false -and $_.userPrincipalName -and $_.lastSyncDateTime -and $_.isEncrypted }
}

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

  $aadDevices = Invoke-MgGraphRequest -Uri "v1.0/deviceManagement/managedDevices?`$filter=operatingSystem eq 'Windows'&select=azureADDeviceId,deviceName,id,userPrincipalName,isEncrypted,managedDeviceOwnerType,deviceEnrollmentType" | Get-MgGraphAllPages

  $aadDevices | select *, @{n = 'ValidRecoveryBitlockerKeyInAzure'; e = {
      $deviceId = $_.azureADDeviceId
      $enrolledDateTime = $_.enrolledDateTime
      $validRecoveryKey = $recoveryKeys | ? { $_.deviceId -eq $deviceId -and $_.createdDateTime -ge $enrolledDateTime }
      if ($validRecoveryKey) { $true } else { $false } }
  }
}

function Set-AzureDeviceExtensionAttribute {
    <#
    .SYNOPSIS
    Function for setting Azure device ExtensionAttribute.

    .DESCRIPTION
    Function for setting Azure device ExtensionAttribute.

    .PARAMETER deviceName
    Device name.

    .PARAMETER deviceId
    Device ID as returned by Get-MGDevice command.

    Can be used instead of device name.

    .PARAMETER extensionId
    Id number of the extension you want to set.

    Possible values are 1-15.

    .PARAMETER extensionValue
    Value you want to set. If empty, currently set value will be removed.

    .PARAMETER scope
    Permissions you want to use for connecting to Graph.

    Default is 'Directory.AccessAsUser.All' and can be used if you have Global or Intune administrator role.

    Possible values are: 'Directory.AccessAsUser.All', 'Device.ReadWrite.All', 'Directory.ReadWrite.All'

    .EXAMPLE
    Set-AzureDeviceExtensionAttribute -deviceName nn-69-ntb -extensionId 1 -extensionValue 'ntb'

    On device nn-69-ntb set value 'ntb' into device ExtensionAttribute1.

    .EXAMPLE
    Set-AzureDeviceExtensionAttribute -deviceName nn-69-ntb -extensionId 1

    On device nn-69-ntb empty current value saved in device ExtensionAttribute1.

    .NOTES
    https://blogs.aaddevsup.xyz/2022/05/how-to-use-microsoft-graph-sdk-for-powershell-to-update-a-registered-devices-extension-attribute/?utm_source=rss&utm_medium=rss&utm_campaign=how-to-use-microsoft-graph-sdk-for-powershell-to-update-a-registered-devices-extension-attribute
    #>

    [CmdletBinding(DefaultParameterSetName = 'deviceName')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "deviceName")]
        [string] $deviceName,

        [Parameter(Mandatory = $true, ParameterSetName = "deviceId")]
        [string] $deviceId,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 15)]
        $extensionId,

        [string] $extensionValue,

        [ValidateSet('Directory.AccessAsUser.All', 'Device.ReadWrite.All', 'Directory.ReadWrite.All')]
        [string] $scope = 'Directory.AccessAsUser.All'
    )

    #region checks
    if (!(Get-Module "Microsoft.Graph.Authentication" -ListAvailable -ea SilentlyContinue)) {
        throw "Microsoft.Graph.Authentication module is missing"
    }

    if (!(Get-Module "Microsoft.Graph.Identity.DirectoryManagement" -ListAvailable -ea SilentlyContinue)) {
        throw "Microsoft.Graph.Identity.DirectoryManagement module is missing"
    }
    #endregion checks

    # connect to Graph
    $null = Connect-MgGraph -Scopes $scope

    # get the device
    if ($deviceName) {
        $device = Get-MgDevice -Filter "DisplayName eq '$deviceName'"
        if (!$device) {
            throw "Device $deviceName wasn't found"
        }
    } else {
        $device = Get-MgDeviceById -DeviceId $deviceId -ErrorAction SilentlyContinue
        if (!$device) {
            throw "Device $deviceId wasn't found"
        }
        $deviceName = $device.DisplayName
    }

    if ($device.count -gt 1) {
        throw "There are more than one devices with name $device. Use DeviceId instead."
    }

    # get current value saved in attribute
    $currentExtensionValue = $device.AdditionalProperties.extensionAttributes."extensionAttribute$extensionId"

    # set attribute if necessary
    if (($currentExtensionValue -eq $extensionValue) -or ([string]::IsNullOrEmpty($currentExtensionValue) -and [string]::IsNullOrEmpty($extensionValue))) {
        Write-Warning "New extension value is same as existing one set in extensionAttribute$extensionId on device $deviceName. Skipping"
    } else {
        if ($extensionValue) {
            $verb = "Setting '$extensionValue' to"
        } else {
            $verb = "Emptying"
        }

        Write-Warning "$verb extensionAttribute$extensionId on device $deviceName (previous value was '$currentExtensionValue')"

        # prepare value hash
        $params = @{
            "extensionAttributes" = @{
                "extensionAttribute$extensionId" = $extensionValue
            }
        }

        Update-MgDevice -DeviceId $device.id -BodyParameter ($params | ConvertTo-Json)
    }
}

Export-ModuleMember -function Get-AzureDeviceWithoutBitlockerKey, Get-BitlockerEscrowStatusForAzureADDevices, Set-AzureDeviceExtensionAttribute

