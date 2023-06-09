#requires -modules WindowsAutoPilotIntune
function Upload-IntuneAutopilotHash {
    <#
    .SYNOPSIS
    Function for uploading Autopilot hash into Intune.

    .DESCRIPTION
    Function for uploading Autopilot hash into Intune.
    Autopilot hash can be gathered from local computer or passed in PS object.

    Beware that when the device already exists in the Autopilot, it won't be recreated (hash doesn't change)!

    .PARAMETER psObject
    PS object with properties that will be used for upload.
    - (mandatory) SerialNumber
        Device serial number.
    - (mandatory) HardwareHash
        Device hardware hash.
    - (optional) Hostname
        Device hostname
    - (optional) ownerUPN
        Device owner UPN

    .PARAMETER thisDevice
    Switch that instead of using PS object (psObject) for getting the data, hash of this computer will be uploaded.
    Requires admin rights!

    .PARAMETER ownerUPN
    UPN of the device owner.

    .PARAMETER groupTag
    Group tag for easier identification of the devices.

    By default current date.

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
    #>

    [CmdletBinding(DefaultParameterSetName = 'PSObject')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "PSObject")]
        [PSCustomObject] $psObject,

        [Parameter(Mandatory = $true, ParameterSetName = "thisDevice")]
        [switch] $thisDevice,

        [string] $ownerUPN,

        [parameter(Mandatory = $false, HelpMessage = "Specify the order identifier, e.g. 'Purchase<ID>'.")]
        [ValidateNotNullOrEmpty()]
        [string] $groupTag = (Get-Date -Format "dd.MM.yyyy")
    )

    # check mandatory properties
    if ($psObject) {
        $property = $psObject | Get-Member -MemberType NoteProperty, Property

        if ($property.Name -notcontains "SerialNumber") {
            throw "PSObject doesn't contain property SerialNumber"
        }
        if ($property.Name -notcontains "HardwareHash") {
            throw "PSObject object doesn't contain property HardwareHash"
        }
    }

    $AuthToken = New-GraphAPIAuthHeader -useMSAL

    function Get-ErrorResponseBody {
        param(
            [parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [System.Exception]$Exception
        )

        # Read the error stream
        $ErrorResponseStream = $Exception.Response.GetResponseStream()
        $StreamReader = New-Object System.IO.StreamReader($ErrorResponseStream)
        $StreamReader.BaseStream.Position = 0
        $StreamReader.DiscardBufferedData()
        $ResponseBody = $StreamReader.ReadToEnd();

        # Handle return object
        return $ResponseBody
    }

    if ($thisDevice) {
        # Gather device hash data

        if (! ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
            throw "You don't have administrator rights"
        }

        Write-Verbose -Message "Gather device hash data from local machine"
        $HardwareHash = (Get-CimInstance -Namespace "root/cimv2/mdm/dmmap" -Class "MDM_DevDetail_Ext01" -Filter "InstanceID='Ext' AND ParentID='./DevDetail'" -Verbose:$false).DeviceHardwareData
        $SerialNumber = (Get-CimInstance -ClassName "Win32_BIOS" -Verbose:$false).SerialNumber
        [PSCustomObject]$psObject = @{
            SerialNumber = $SerialNumber
            HardwareHash = $HardwareHash
            Hostname     = $env:COMPUTERNAME
        }
    } else {
        # data was provided using PSObject properties
    }

    # Construct Graph variables
    $GraphVersion = "beta"
    $GraphResource = "deviceManagement/importedWindowsAutopilotDeviceIdentities"
    $GraphURI = "https://graph.microsoft.com/$($GraphVersion)/$($GraphResource)"

    foreach ($hashItem in $psObject) {
        "Processing $($hashItem.SerialNumber)"

        # Construct hash table for new Autopilot device identity and convert to JSON
        Write-Verbose -Message "Constructing required JSON body based upon parameter input data for device hash upload"
        $AutopilotDeviceIdentity = [ordered]@{
            '@odata.type'        = '#microsoft.graph.importedWindowsAutopilotDeviceIdentity'
            'groupTag'           = $groupTag
            'serialNumber'       = $hashItem.SerialNumber
            'productKey'         = ''
            'hardwareIdentifier' = $hashItem.HardwareHash
            'state'              = @{
                '@odata.type'          = 'microsoft.graph.importedWindowsAutopilotDeviceIdentityState'
                'deviceImportStatus'   = 'pending'
                'deviceRegistrationId' = ''
                'deviceErrorCode'      = 0
                'deviceErrorName'      = ''
            }
        }

        # set owner
        if ($hashItem.ownerUPN) {
            "`t - set owner $($hashItem.ownerUPN)"
            $AutopilotDeviceIdentity.assignedUserPrincipalName = $hashItem.ownerUPN
        } elseif ($ownerUPN) {
            "`t - set owner $ownerUPN"
            $AutopilotDeviceIdentity.assignedUserPrincipalName = $ownerUPN
        }

        $AutopilotDeviceIdentityJSON = $AutopilotDeviceIdentity | ConvertTo-Json

        try {
            # Call Graph API and post JSON data for new Autopilot device identity
            Write-Verbose -Message "Attempting to post data for hardware hash upload"
            # $result = Add-AutopilotImportedDevice -serialNumber $SerialNumber -hardwareIdentifier $HardwareHash -groupTag $groupTag #-assignedUser
            $result = Invoke-RestMethod -Uri $GraphURI -Headers $AuthToken -Method Post -Body $AutopilotDeviceIdentityJSON -ContentType "application/json" -ErrorAction Stop -Verbose:$false
            # $result
            Write-Verbose "Upload of $($hashItem.SerialNumber) finished"
        } catch [System.Exception] {
            # Construct stream reader for reading the response body from API call
            $ResponseBody = Get-ErrorResponseBody -Exception $_.Exception

            # Handle response output and error message
            Write-Output -InputObject "Response content:`n$ResponseBody"
            Write-Warning -Message "Failed to upload hardware hash. Request to $($GraphURI) failed with HTTP Status $($_.Exception.Response.StatusCode) and description: $($_.Exception.Response.StatusDescription)"
        }

        # set deviceName
        if ($hashItem.Hostname) {
            # invoking Intune Sync, to get imported device into Intune database, so I can set its hostname
            try {
                # Call Graph API and post Autopilot devices sync command
                Write-Verbose -Message "Attempting to perform a sync action in Autopilot"
                $GraphResource = "deviceManagement/windowsAutopilotSettings/sync"
                $GraphURI = "https://graph.microsoft.com/$($GraphVersion)/$($GraphResource)"
                $result = (Invoke-RestMethod -Uri $GraphURI -Headers $AuthToken -Method Post -ErrorAction Stop -Verbose:$false).Value
                Write-Verbose "Autopilot sync started"
            } catch [System.Exception] {
                # Construct stream reader for reading the response body from API call
                $ResponseBody = Get-ErrorResponseBody -Exception $_.Exception

                # Handle response output and error message
                Write-Output -InputObject "Response content:`n$ResponseBody"
                Write-Warning -Message "Request to $GraphURI failed with HTTP Status $($_.Exception.Response.StatusCode) and description: $($_.Exception.Response.StatusDescription)"
            }

            "`t - set hostname $($hashItem.Hostname)"
            $i = 0
            while (1) {
                ++$i
                $deviceId = Get-AutopilotDevice -serial $hashItem.SerialNumber -ea Stop | select -exp id
                if (!$deviceId) {
                    if ($i -gt 50) {
                        throw "$($hashItem.Hostname) ($($hashItem.SerialNumber)) didn't upload successfully. It probably exists in different tenant?"
                    }
                    Write-Host "`t`t$($hashItem.SerialNumber) not yet created..waiting"
                    Start-Sleep 10
                    continue
                }
                try {
                    Set-AutopilotDevice -id $deviceId -displayName $hashItem.Hostname -ea Stop
                    break
                } catch {
                    throw $_
                }
            }
        }
    }

    # invoking Intune Sync, to get imported devices into Intune database ASAP
    try {
        # Call Graph API and post Autopilot devices sync command
        Write-Verbose -Message "Attempting to perform a sync action in Autopilot"
        $GraphResource = "deviceManagement/windowsAutopilotSettings/sync"
        $GraphURI = "https://graph.microsoft.com/$($GraphVersion)/$($GraphResource)"
        $result = (Invoke-RestMethod -Uri $GraphURI -Headers $AuthToken -Method Post -ErrorAction Stop -Verbose:$false).Value
        Write-Verbose "Autopilot sync started"
    } catch [System.Exception] {
        # Construct stream reader for reading the response body from API call
        $ResponseBody = Get-ErrorResponseBody -Exception $_.Exception

        # Handle response output and error message
        Write-Output -InputObject "Response content:`n$ResponseBody"
        Write-Warning -Message "Request to $GraphURI failed with HTTP Status $($_.Exception.Response.StatusCode) and description: $($_.Exception.Response.StatusDescription)"
    }
}