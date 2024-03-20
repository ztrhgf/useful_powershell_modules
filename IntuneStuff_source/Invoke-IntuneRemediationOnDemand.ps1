#requires -modules Microsoft.Graph.Authentication, Microsoft.Graph.Beta.DeviceManagement
function Invoke-IntuneRemediationOnDemand {
    <#
    .SYNOPSIS
    Function for invoking remediation script on demand on selected Windows device(s).

    .DESCRIPTION
    Function for invoking remediation script on demand on selected Windows device(s).

    .PARAMETER deviceName
    Intune device name(s).

    .PARAMETER deviceId
    Intune device ID(s).
    Can be retrieved by Get-IntuneManagedDevice or Get-MgDeviceManagementManagedDevice.

    .PARAMETER remediationScriptId
    ID of the remediation script.
    Can be retrieved by Get-MgDeviceManagementDeviceHealthScript.

    .EXAMPLE
    Invoke-IntuneRemediationOnDemand

    Interactively select device and remediation script you want to run on it.

    .EXAMPLE
    Invoke-IntuneRemediationOnDemand -deviceName PC-01, PC-02 -remediationScriptId a0f00dea-a3ed-4604-b440-021daf549f93

    Run remediation script on selected devices.

    .EXAMPLE
    Invoke-IntuneRemediationOnDemand -deviceId 66d714ce-d469-4fe4-af3f-7ea5f51980b8 -remediationScriptId a0f00dea-a3ed-4604-b440-021daf549f93

    Run remediation script on selected device.
    #>

    [CmdletBinding(DefaultParameterSetName = 'name')]
    [Alias("Invoke-IntuneOnDemandRemediation", "Invoke-IntuneRemediationScriptOnDemand")]
    param (
        [Parameter(ParameterSetName = "name")]
        [string[]] $deviceName,

        [Parameter(ParameterSetName = "id")]
        [guid[]] $deviceId,

        [guid] $remediationScriptId
    )

    #region checks
    $deviceName = $deviceName | select -Unique
    $deviceId = $deviceId | select -Unique

    if (!(Get-MgContext)) {
        throw "Authentication needed, call Connect-MgGraph"
    }
    if ((Get-MgContext).scopes -notcontains "DeviceManagementManagedDevices.PrivilegedOperations.All") {
        throw "Scope 'DeviceManagementManagedDevices.PrivilegedOperations.All' is needed"
    }
    #endregion checks

    # ask for remediation id if missing
    while (!$remediationScriptId) {
        $remediationScriptId = Get-MgBetaDeviceManagementDeviceHealthScript -All | select DisplayName, Description, Id | Out-GridView -OutputMode Single -Title "Select remediation you want to invoke" | select -ExpandProperty Id
    }

    # translate device name to id
    if ($deviceName) {
        $deviceId = $deviceName | % {
            $devId = (Get-MgBetaDeviceManagementManagedDevice -Filter "deviceName eq '$_'" -Property Id).Id
            if ($devId) {
                $devId
            } else {
                Write-Warning "Device $_ doesn't exist"
            }
        }
    }

    # ask for device id if missing
    while (!$deviceId) {
        $deviceId = Get-MgBetaDeviceManagementManagedDevice -Property DeviceName, ManagedDeviceOwnerType, OperatingSystem, Id -All -Filter "OperatingSystem eq 'Windows'" | select deviceName, managedDeviceOwnerType, id | Out-GridView -OutputMode Multiple -Title "Select device(s) you want run the remediation on" | select -ExpandProperty Id
    }

    # invoke remediation on demand
    $deviceId | % {
        Write-Verbose "Invoking remediation $remediationScriptId on device $_"

        $remediationScriptBody = @{
            "ScriptPolicyId" = $remediationScriptId
        }

        Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$_')/initiateOnDemandProactiveRemediation" -Method POST -Body $remediationScriptBody
    }
}