#requires -modules Microsoft.Graph.Authentication, Microsoft.Graph.Identity.DirectoryManagement
function Set-AADDeviceExtensionAttribute {
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
    Set-AADDeviceExtensionAttribute -deviceName nn-69-ntb -extensionId 1 -extensionValue 'ntb'

    On device nn-69-ntb set value 'ntb' into device ExtensionAttribute1.

    .EXAMPLE
    Set-AADDeviceExtensionAttribute -deviceName nn-69-ntb -extensionId 1

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
    } else {
        $device = Get-MgDeviceById -DeviceId $deviceId -ErrorAction SilentlyContinue
        $deviceName = $device.DisplayName
    }
    if (!$device) {
        throw "$device device wasn't found"
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