#requires -modules Microsoft.Graph.DeviceManagement.Enrollment

function Upload-IntuneAutopilotHash {
    <#
    .SYNOPSIS
    Function for uploading Autopilot hash into Intune.

    .DESCRIPTION
    Function for uploading Autopilot hash into Intune.
    Autopilot hash can be gathered from local computer or passed in PS object.

    Beware that when the device already exists in the Autopilot, it won't be recreated (hash doesn't change)!

    .PARAMETER psObject
    PS object(s) with properties that will be used for upload.
    - (mandatory) SerialNumber
        Device serial number.
    - (mandatory) HardwareHash
        Device hardware hash.
    - (optional) Hostname
        Device hostname
    - (optional) ownerUPN
        Device owner UPN

    TIP: it is better from performance perspective to provide more objects at once instead of one-by-one processing

    .PARAMETER thisDevice
    Switch for getting&uploading hash of this computer instead of using PS object (psObject) as source of the data.
    Requires admin rights!

    .PARAMETER ownerUPN
    UPN of the device owner.

    .PARAMETER groupTag
    Group tag for easier identification of the devices.

    By default current date.

    .PARAMETER skipSync
    Skip final autopilot database sync step.
    It can cause throttling error message if invoked too many times in the short time period.

    .EXAMPLE
    Upload-IntuneAutopilotHash -thisDevice -ownerUPN johnd@contoso.com -Verbose

    Uploads this device hash into Intune Autopilot. Owner will be johnd@contoso.com and hostname $env:COMPUTERNAME.

    .EXAMPLE
    $data = [PSCustomObject]@{
        SerialNumber = "123456"
        HardwareHash = "T0FmBAEAHAAAAAoAHgZhSgAACgCSBmFKYGIyKgg...." # can be obtained via: (Get-CimInstance -Namespace "root/cimv2/mdm/dmmap" -Class "MDM_DevDetail_Ext01" -Filter "InstanceID='Ext' AND ParentID='./DevDetail'" -Verbose:$false).DeviceHardwareData
    }

    Upload-IntuneAutopilotHash -psObject $data -Verbose

    Uploads device with specified serial number and hash into Intune Autopilot. Owner and hostname will be empty.

    .EXAMPLE
    $domain = "contoso.com"
    $data = Get-CMAutopilotHash -computername ni-20-ntb
    $data = $data | select *, @{n='OwnerUPN';e={$_.Owner + "@" + $domain}}

    Upload-IntuneAutopilotHash -psObject $data -Verbose

    Uploads device with specified serial number and hash (retrieved from SCCM database) into Intune Autopilot. Owner will be empty but hostname will be filled with value from SCCM database (ni-20-ntb).

    .NOTES
    Inspired by https://www.manishbangia.com/import-autopilot-devices-sccm-sqlquery/ and https://www.powershellgallery.com/packages/Upload-WindowsAutopilotDeviceInfo/1.0.0/Content/Upload-WindowsAutopilotDeviceInfo.ps1

    Not using *-*AutopilotDevice cmdlets, because sometimes it connects using cached? token instead of actual AAD connection, so causing troubles in multi tenant environments
    #>

    [CmdletBinding(DefaultParameterSetName = 'PSObject')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "PSObject")]
        [PSCustomObject[]] $psObject,

        [Parameter(Mandatory = $true, ParameterSetName = "thisDevice")]
        [switch] $thisDevice,

        [string] $ownerUPN,

        [parameter(Mandatory = $false, HelpMessage = "Specify the order identifier, e.g. 'Purchase<ID>'.")]
        [ValidateNotNullOrEmpty()]
        [string] $groupTag = (Get-Date -Format "dd.MM.yyyy"),

        [switch] $skipSync
    )

    if ($psObject) {
        # check mandatory properties
        foreach ($autopilotItem in $psObject) {
            $property = $autopilotItem | Get-Member -MemberType NoteProperty, Property

            if ($property.Name -notcontains "SerialNumber") {
                $autopilotItem
                throw "PSObject doesn't contain mandatory property SerialNumber"
            }
            if ($property.Name -notcontains "HardwareHash") {
                $autopilotItem
                throw "PSObject object doesn't contain mandatory property HardwareHash"
            }
        }
    } elseif ($thisDevice) {
        # gather this device hash data
        if (! ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
            throw "You don't have administrator rights"
        }

        Write-Verbose "Gather device hash data of the local machine"
        $HardwareHash = (Get-CimInstance -Namespace "root/cimv2/mdm/dmmap" -Class "MDM_DevDetail_Ext01" -Filter "InstanceID='Ext' AND ParentID='./DevDetail'" -Verbose:$false).DeviceHardwareData
        $SerialNumber = (Get-CimInstance -ClassName "Win32_BIOS" -Verbose:$false).SerialNumber
        $psObject = [PSCustomObject]@{
            SerialNumber = $SerialNumber
            HardwareHash = $HardwareHash
            Hostname     = $env:COMPUTERNAME
        }
    } else {
        throw "Undefined state"
    }

    Connect-MgGraph -NoWelcome

    $failedUpload = @()
    $processedDevice = @()
    $missingDevice = @()

    # upload autopilot hashes
    Write-Host "Upload Autopilot hash(es)" -ForegroundColor Cyan
    foreach ($autopilotItem in $psObject) {
        "Processing $($autopilotItem.SerialNumber)"

        # Construct hash table for new Autopilot device identity and convert to JSON
        Write-Verbose "Constructing required JSON body based upon parameter input data for device hash upload"
        $AutopilotDeviceIdentity = [ordered]@{
            '@odata.type'        = '#microsoft.graph.importedWindowsAutopilotDeviceIdentity'
            'groupTag'           = $groupTag
            'serialNumber'       = $autopilotItem.SerialNumber
            'productKey'         = ''
            'hardwareIdentifier' = $autopilotItem.HardwareHash
            'state'              = @{
                '@odata.type'          = 'microsoft.graph.importedWindowsAutopilotDeviceIdentityState'
                'deviceImportStatus'   = 'pending'
                'deviceRegistrationId' = ''
                'deviceErrorCode'      = 0
                'deviceErrorName'      = ''
            }
        }

        Write-Verbose "`t - serialNumber $($autopilotItem.SerialNumber)"
        Write-Verbose "`t - hardwareIdentifier $($autopilotItem.HardwareHash)"

        # set owner
        if ($autopilotItem.ownerUPN) {
            Write-Verbose "`t - owner $($autopilotItem.ownerUPN)"
            $AutopilotDeviceIdentity.assignedUserPrincipalName = $autopilotItem.ownerUPN
        } elseif ($ownerUPN) {
            Write-Verbose "`t - owner $ownerUPN"
            $AutopilotDeviceIdentity.assignedUserPrincipalName = $ownerUPN
        }

        $AutopilotDeviceIdentityJSON = $AutopilotDeviceIdentity | ConvertTo-Json

        # create new Autopilot device
        try {
            Write-Verbose "Uploading hardware hash"
            New-MgDeviceManagementImportedWindowsAutopilotDeviceIdentity -BodyParameter $AutopilotDeviceIdentityJSON -ErrorAction Stop -Verbose:$false

            $processedDevice += $autopilotItem

            # make a note about devices not already synced into the Autopilot
            $autopilotDevice = Get-AutopilotDevice -serialNumber $autopilotItem.SerialNumber
            if (!$autopilotDevice) {
                $missingDevice += $autopilotItem
            }
        } catch {
            throw "Failed to upload hardware hash."

            $failedUpload += $autopilotItem.SerialNumber
        }
    }

    # invoke Autopilot SYNC, to get imported devices into the Intune database ASAP
    # also device record needs to exist in database so hostname can be set
    if ($missingDevice) {
        Write-Host "Performing a Autopilot database sync" -ForegroundColor Cyan
        Invoke-AutopilotSync
        "`t - sync started..waiting 60 seconds before continue"
        Start-Sleep 60
    }

    # set deviceName
    # in separate cycle to avoid TooManyRequests error when invoking sync after each device upload
    if ($psObject.Hostname -and $processedDevice) {
        Write-Host "Setting hostname" -ForegroundColor Cyan

        foreach ($autopilotItem in $psObject) {
            if ($autopilotItem.Hostname) {
                "Processing $($autopilotItem.SerialNumber)"

                if ($autopilotItem.SerialNumber -in $failedUpload) {
                    Write-Verbose "Skipping setting hostname of $($autopilotItem.SerialNumber), because it failed to upload"
                    continue
                }

                Write-Verbose "`t - hostname $($autopilotItem.Hostname)"
                $i = 0
                while (1) {
                    ++$i
                    # trying to get the autopilot device record
                    $deviceId = Get-AutopilotDevice -serialNumber $autopilotItem.SerialNumber | select -ExpandProperty id

                    if (!$deviceId) {
                        if ($i -gt 50) {
                            Write-Error "$($autopilotItem.Hostname) ($($autopilotItem.SerialNumber)) didn't upload successfully. It probably exists in different tenant?"
                            break
                        }

                        Write-Host "`t`t$($autopilotItem.SerialNumber) not yet created..waiting"
                        Start-Sleep 10
                        continue
                    }

                    Set-AutopilotDeviceName -id $deviceId -computerName $autopilotItem.Hostname -skipSync
                    break
                }
            }
        }

        if (!$skipSync) {
            Invoke-AutopilotSync
        }
    }
}