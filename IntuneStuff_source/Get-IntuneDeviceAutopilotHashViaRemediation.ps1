function Get-IntuneDeviceAutopilotHashViaRemediation {
    <#
    .SYNOPSIS
    Retrieve (via on-demand remediation) device autopilot hash, serial number and hostname and possibly upload it into the autopilot database .

    .DESCRIPTION
    Retrieve (via on-demand remediation) device autopilot hash, serial number and hostname and possibly upload it into the autopilot database.

    .PARAMETER name
    Device name.

    .PARAMETER id
    Device id.

    .PARAMETER uploadToAutopilotDatabase
    Switch to upload retrieved data to autopilot database.

    .PARAMETER dontWait
    Switch to not wait for command to finish a.k.a. remediation will not be deleted and no hash will be returned.

    .EXAMPLE
    Get-IntuneDeviceAutopilotHashViaRemediation -name np-10-ntb -uploadToAutopilotDatabase

    .NOTES
    Device has to be turned on.
    #>

    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, ParameterSetName = "name")]
        [string] $name,

        [Parameter(Mandatory = $true, ParameterSetName = "id")]
        [string] $id,

        [switch] $uploadToAutopilotDatabase,

        [switch] $dontWait
    )

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-MgGraph."
    }

    if ($uploadToAutopilotDatabase -and $dontWait) {
        throw "Cannot use -uploadToAutopilotDatabase with -dontWait"
    }

    # import parent module so we can prepend command definition to the send scriptblock later
    $cmdlet = Get-Command "ConvertTo-CompressedString" -ErrorAction Stop
    if (!(Get-Module $cmdlet.ModuleName)) {
        Import-Module $cmdlet.ModuleName
    }

    #region retrieve device serial number
    if ($name) {
        $request = New-GraphBatchRequest -url "/deviceManagement/managedDevices?`$filter=OperatingSystem eq 'Windows' and deviceName eq '$name'&`$select=serialNumber"
    } else {
        $request = New-GraphBatchRequest -url "/deviceManagement/managedDevices/$id`?&`$select=serialNumber"
    }
    $serialNumber = Invoke-GraphBatchRequest -batchRequest $request | select -ExpandProperty serialNumber

    if (!$serialNumber) {
        throw "Device '$name' ($id) not found in Intune"
    }
    #endregion retrieve device serial number

    $command = {
        $serial = (Get-CimInstance -Class Win32_BIOS).SerialNumber

        # Get the hash (if available)
        $devDetail = (Get-CimInstance -Namespace root/cimv2/mdm/dmmap -Class MDM_DevDetail_Ext01 -Filter "InstanceID='Ext' AND ParentID='./DevDetail'")
        if ($devDetail) {
            $hash = $devDetail.DeviceHardwareData
        } else {
            throw "Unable to get hash"
        }

        $result = [PSCustomObject]@{
            SerialNumber = $serial
            HardwareHash = $hash
            Hostname     = $env:COMPUTERNAME
        }

        $result | ConvertTo-Json -Compress | ConvertTo-CompressedString
    }

    $param = @{
        command                  = $command
        remediationSuffix        = "$serialNumber`_getAutopilotHash"
        prependCommandDefinition = "ConvertTo-CompressedString"
    }
    if ($name) { $param.deviceName = $name }
    if ($id) { $param.deviceId = $id }
    if ($dontWait) { $param.dontWait = $true }

    $result = Invoke-IntuneCommand @param

    if ($dontWait) { return }

    if ($result.processedoutput) {
        $result.processedoutput

        if ($uploadToAutopilotDatabase) {
            "Uploading hash for '$($result.processedoutput.hostname)'"
            Upload-IntuneAutopilotHash -psObject $result.processedoutput -skipSync
        }
    } else {
        throw "Unable to get hash for '$name' ($id)"
    }
}