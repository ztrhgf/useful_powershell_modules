#Requires -Module ActiveDirectory
function Get-MDMClientData {
    <#
    .SYNOPSIS
    Function for getting client management information from AD, Intune, AAD and SCCM and combine them together.

    .DESCRIPTION
    Function for getting client management information from AD, Intune, AAD and SCCM and combine them together.
    Resultant object will have several properties with prefix AD, INTUNE, AAD or SCCM according to source of such data.

    .PARAMETER computer
    Computer(s) you want to get data about from AD, AAD, SCCM and Intune.
    As object(s) with name, sid and ObjectGUID of AD computers OR just list of computer names (in case of duplicity records, additional data to uniquely identify the correct one will be gathered from AD).

    .PARAMETER combineDataFrom
    List of sources you want to gather data from.

    Possible values are: Intune, SCCM, AAD, AD

    By default all values are selected.

    .PARAMETER graphCredential
    AppID and AppSecret for Azure App registration that has permissions needed to read Azure and Intune clients data.

    .PARAMETER sccmAdminServiceCredential
    Credentials for SCCM Admin Service API authentication. Needed only if current user doesn't have correct permissions.

    .EXAMPLE
    # active AD Windows clients that belongs to some user
    $activeADClients = Get-ADComputer -Filter "enabled -eq 'True' -and description -like '*'" -Properties description 

    $problematic = Get-MDMClientData -computer $activeADClients -graphCredential $cred

    .NOTES
    Requires functions: New-GraphAPIAuthHeader, Invoke-CMAdminServiceQuery
    #>

    [CmdletBinding()]
    param (
        $computer = (Get-ADComputer -Filter "enabled -eq 'True' -and description -like '*'" -Properties 'Name', 'sid', 'LastLogonDate', 'Enabled', 'DistinguishedName', 'Description', 'PasswordLastSet', 'ObjectGUID' | ? { $_.LastLogonDate -ge [datetime]::Today.AddDays(-90) }),

        [ValidateSet('Intune', 'SCCM', 'AAD', 'AD')]
        [string[]] $combineDataFrom = ('Intune', 'SCCM', 'AAD', 'AD'),

        [Alias("intuneCredential")]
        [System.Management.Automation.PSCredential] $graphCredential,

        [System.Management.Automation.PSCredential] $sccmAdminServiceCredential
    )

    #region checks
    if (!$computer) { throw "Computer parameter is missing" }

    if ($combineDataFrom -contains "Intune") {
        try {
            $null = Get-Command New-GraphAPIAuthHeader -ErrorAction Stop
        } catch {
            throw "New-GraphAPIAuthHeader command isn't available"
        }
    }

    if ($combineDataFrom -contains "SCCM") {
        try {
            $null = Get-Command Invoke-CMAdminServiceQuery -ErrorAction Stop
        } catch {
            throw "Invoke-CMAdminServiceQuery command isn't available"
        }
    }

    # it needs originally installed ActiveDirectory module, NOT copied/hacked one!
    if (!(Get-Module ActiveDirectory -ListAvailable)) {
        if ((Get-WmiObject win32_operatingsystem -Property caption).caption -match "server") {
            throw "Module ActiveDirectory is missing. Use: Install-WindowsFeature RSAT-AD-PowerShell -IncludeManagementTools"
        } else {
            throw "Module ActiveDirectory is missing. Use: Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online"
        }
    }
    #endregion checks

    #region helper functions
    function _ClientCheckPass {
        # translates number code to message
        param ($ClientCheckPass)

        switch ($ClientCheckPass) {
            1 { return "Passed" }
            2 { return "Failed" }
            3 { return "No results" }
            default { return "Not evaluated" }
        }
    }

    function _computerHasValidHybridJoinCertificate {
        # extracted from Export-ADSyncToolsHybridAzureADjoinCertificateReport.ps1
        # https://github.com/azureautomation/export-hybrid-azure-ad-join-computer-certificates-report--updated-

        [CmdletBinding()]
        param ([string]$computerName)

        $searcher = [adsisearcher]"(&(objectCategory=computer)(name=$computerName))"
        $searcher.PageSize = 500
        $searcher.PropertiesToLoad.AddRange(('usercertificate', 'name'))
        # $searcher.searchRoot = [adsi]"LDAP://OU=Computer_Accounts,DC=contoso,DC=com"
        $obj = $searcher.FindOne()
        $searcher.Dispose()
        if (!$obj) { throw "Unable to get $computerName" }

        $userCertificateList = @($obj.properties.usercertificate)
        $validEntries = @()
        $totalEntriesCount = $userCertificateList.Count
        Write-Verbose "'$computerName' has $totalEntriesCount entries in UserCertificate property."
        If ($totalEntriesCount -eq 0) {
            Write-Warning "'$computerName' has no Certificates - Skipped."
            return $false
        }
        # Check each UserCertificate entry and build array of valid certs
        ForEach ($entry in $userCertificateList) {
            Try {
                $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2] $entry
            } Catch {
                Write-Verbose "'$computerName' has an invalid Certificate!"
                Continue
            }
            Write-Verbose "'$computerName' has a Certificate with Subject: $($cert.Subject); Thumbprint:$($cert.Thumbprint)."
            $validEntries += $cert

        }

        $validEntriesCount = $validEntries.Count
        Write-Verbose "'$computerName' has a total of $validEntriesCount certificates (shown above)."

        # Get non-expired Certs (Valid Certificates)
        $validCerts = @($validEntries | Where-Object { $_.NotAfter -ge (Get-Date) })
        $validCertsCount = $validCerts.Count
        Write-Verbose "'$computerName' has $validCertsCount valid certificates (not-expired)."

        # Check for AAD Hybrid Join Certificates
        $hybridJoinCerts = @()
        $hybridJoinCertsThumbprints = [string] "|"
        ForEach ($cert in $validCerts) {
            $certSubjectName = $cert.Subject
            If ($certSubjectName.StartsWith($("CN=$objectGuid")) -or $certSubjectName.StartsWith($("CN={$objectGuid}"))) {
                $hybridJoinCerts += $cert
                $hybridJoinCertsThumbprints += [string] $($cert.Thumbprint) + '|'
            }
        }

        $hybridJoinCertsCount = $hybridJoinCerts.Count
        if ($hybridJoinCertsCount -gt 0) {
            Write-Verbose "'$computerName' has $hybridJoinCertsCount AAD Hybrid Join Certificates with Thumbprints: $hybridJoinCertsThumbprints"
            if ($hybridJoinCertsCount.count -lt 15) {
                # more than 15 certificates would cause fail
                return $true
            } else {
                return $false
            }
        } else {
            Write-Verbose "'$computerName' has no AAD Hybrid Join Certificates"
            return $false
        }
    }
    #endregion helper functions

    #region get data
    if ($combineDataFrom -contains "Intune" -or $combineDataFrom -contains "AAD") {
        $header = New-GraphAPIAuthHeader -credential $graphCredential -ErrorAction Stop
    }

    if ($combineDataFrom -contains "Intune") {
        $intuneDevice = (Invoke-RestMethod -Headers $header -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices" -Method Get).Value | select deviceName, deviceEnrollmentType, lastSyncDateTime, aadRegistered, azureADRegistered, deviceRegistrationState, azureADDeviceId, emailAddress

        # interactive user auth example
        # Connect-MSGraph
        # Get-DeviceManagement_ManagedDevices | select deviceName, deviceEnrollmentType, lastSyncDateTime, @{n = 'aadRegistered'; e = { $_.azureADRegistered } }, azureADRegistered, deviceRegistrationState, azureADDeviceId, emailAddress
    }

    if ($combineDataFrom -contains "SCCM") {
        $properties = 'Name', 'Domain', 'IsClient', 'IsActive', 'ClientCheckPass', 'ClientActiveStatus', 'LastActiveTime', 'ADLastLogonTime', 'CoManaged', 'IsMDMActive', 'PrimaryUser', 'SerialNumber', 'MachineId', 'UserName'
        $param = @{
            source = "v1.0/Device"
            select = $properties
        }
        if ($sccmAdminServiceCredential) {
            $param.credential = $sccmAdminServiceCredential
        }
        $sccmDevice = Invoke-CMAdminServiceQuery @param | select $properties

        # add more information
        $properties = 'ResourceID', 'InstallDate'
        $param = @{
            source = "wmi/SMS_G_System_OPERATING_SYSTEM"
            select = $properties
        }
        if ($sccmAdminServiceCredential) {
            $param.credential = $sccmAdminServiceCredential
        }
        $additionalData = Invoke-CMAdminServiceQuery @param | select $properties

        $sccmDevice = $sccmDevice | % {
            $deviceAdtData = $additionalData | ?  ResourceID -EQ $_.MachineId
            $_ | select *, @{n = 'InstallDate'; e = { if ($deviceAdtData.InstallDate) { Get-Date $deviceAdtData.InstallDate } } }, @{n = 'LastBootUpTime'; e = { if ($deviceAdtData.LastBootUpTime) { Get-Date $deviceAdtData.LastBootUpTime } } }
        }
    }

    if ($combineDataFrom -contains "AAD") {
        $aadDevice = Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/v1.0/devices" -header $header | select displayName, accountEnabled, approximateLastSignInDateTime, deviceOwnership, enrollmentType, isCompliant, isManaged, managementType, onPremisesSyncEnabled, onPremisesLastSyncDateTime, profileType, deviceId
    }
    #endregion get data

    # fill object properties
    foreach ($cmp in $computer) {
        if ($cmp.name) {
            # it is object
            $name = $cmp.name
        } elseif ($cmp.gettype().Name -eq "String") {
            # it is string
            $name = $cmp
        } else {
            $cmp
            throw "THIS OBJECT DOESN'T CONTAIN NAME PROPERTY"
        }

        Write-Verbose $name

        $deviceGUID = $deviceSID = $null

        $deviceProperty = [ordered]@{
            Name                   = $name
            hasValidHybridJoinCert = _computerHasValidHybridJoinCertificate $name
        }

        if ($combineDataFrom -contains "AD") {
            $property = 'Enabled', 'LastLogonDate', 'DistinguishedName', 'Description', 'Sid', 'ObjectGUID', 'PasswordLastSet'
            $missingProperty = @()

            # try to get the value from input
            $property | % {
                $propertyName = "AD_$_"
                if ($cmp.$_) {
                    switch ($_) {
                        "SID" {
                            $deviceProperty.$propertyName = $cmp.$_.value
                        }
                        "ObjectGUID" {
                            $deviceProperty.$propertyName = $cmp.$_.guid
                        }
                        default {
                            $deviceProperty.$propertyName = $cmp.$_
                        }
                    }
                } else {
                    $missingProperty += $_
                }
            }

            if ($missingProperty) {
                Write-Verbose "Getting missing property: $($missingProperty -join ', ')"
                $deviceADData = Get-ADComputer -Filter "name -eq '$name'" -Property $missingProperty
                $missingProperty | % {
                    $propertyName = "AD_$_"
                    switch ($_) {
                        "SID" {
                            $deviceProperty.$propertyName = $deviceADData.$_.value
                        }
                        "ObjectGUID" {
                            $deviceProperty.$propertyName = $deviceADData.$_.guid
                        }
                        default {
                            $deviceProperty.$propertyName = $deviceADData.$_
                        }
                    }
                }
            }
        }

        # getting SCCM data has to be before Intune because of comparing co-managed status
        if ($combineDataFrom -contains "SCCM") {

            $deviceSCCMRecord = @($sccmDevice | ? Name -EQ $name)

            if (!$deviceSCCMRecord) {
                $deviceProperty.SCCM_InDatabase = $false
            } else {
                # device is in SCCM
                $deviceProperty.SCCM_InDatabase = $true

                if ($deviceSCCMRecord.count -gt 1) {
                    # more records with the same name

                    $deviceProperty.SCCM_MultipleRecords = $deviceSCCMRecord.count

                    Write-Verbose "Device $name is $($deviceSCCMRecord.count)x in SCCM database!"

                    # get the correct one by using SID
                    $deviceSID = $cmp.sid.value
                    if (!$deviceSID) {
                        $deviceSID = $deviceProperty.AD_SID
                    }
                    if (!$deviceSID) {
                        $deviceSID = (Get-ADComputer -Filter "name -eq '$name'" -Property SID).SID.Value
                    }
                    if ($deviceSID) {
                        Write-Verbose "Search for the $name with $deviceSID SID in SCCM database"

                        $param = @{
                            source = "wmi/SMS_R_SYSTEM"
                            select = 'ResourceId'
                            filter = "SID eq '$deviceSID'"
                        }
                        if ($sccmAdminServiceCredential) {
                            $param.credential = $sccmAdminServiceCredential
                        }
                        $resourceId = Invoke-CMAdminServiceQuery @param | select -ExpandProperty ResourceId
                        Write-Verbose "$name has resourceId $resourceId"

                        $deviceSCCMRecord = @($sccmDevice | ? MachineId -EQ $resourceId)
                    }

                    if ($deviceSCCMRecord.count -gt 1) {
                        # unable to narrow down the results

                        if (!$deviceSID) {
                            $erMsg = "No SID property was provided to identify the correct one, nor was found in AD."
                        } else {
                            $erMsg = "Unable to identify the correct one."
                        }
                        Write-Warning "Device $name is $($deviceSCCMRecord.count)x in SCCM database.`n$erMsg Therefore setting property deviceSCCMRecord as `$null"
                        $deviceSCCMRecord = $null
                    }
                } else {
                    $deviceProperty.SCCM_MultipleRecords = $false
                }

                if ($deviceSCCMRecord.count -eq 1) {
                    if (!$deviceSCCMRecord.IsClient) {
                        $deviceProperty.SCCM_ClientInstalled = $false
                    } else {
                        # SCCM client is installed

                        $deviceProperty.SCCM_ClientInstalled = $true
                        if ($deviceSCCMRecord.LastActiveTime) {
                            $deviceProperty.SCCM_LastActiveTime = (Get-Date $deviceSCCMRecord.LastActiveTime)
                        } else {
                            $deviceProperty.SCCM_LastActiveTime = $null
                        }
                        $deviceProperty.SCCM_IsActive = $deviceSCCMRecord.IsActive
                        $deviceProperty.SCCM_clientCheckPass = _ClientCheckPass $deviceSCCMRecord.ClientCheckPass
                        $deviceProperty.SCCM_clientActiveStatus = $deviceSCCMRecord.ClientActiveStatus
                        if ($deviceSCCMRecord.CoManaged -ne 1) {
                            $deviceProperty.SCCM_CoManaged = $false
                        } else {
                            $deviceProperty.SCCM_CoManaged = $true
                        }
                        $deviceProperty.SCCM_User = $deviceSCCMRecord.UserName
                        $deviceProperty.SCCM_SerialNumber = $deviceSCCMRecord.SerialNumber
                        $deviceProperty.SCCM_MachineId = $deviceSCCMRecord.MachineId
                        $deviceProperty.SCCM_OSInstallDate = $deviceSCCMRecord.InstallDate
                    }
                }
            }
        }

        if ($combineDataFrom -contains "Intune") {

            $deviceIntuneRecord = @($intuneDevice | ? DeviceName -EQ $name)

            if (!$deviceIntuneRecord) {
                Write-Verbose "$name wasn't found in Intune database, trying to get its GUID"

                # try to search for it using its GUID
                if (!$deviceGUID) {
                    $deviceGUID = $cmp.ObjectGUID.Guid
                }
                if (!$deviceGUID) {
                    $deviceGUID = $deviceProperty.AD_ObjectGUID
                }
                if (!$deviceGUID) {
                    $deviceGUID = (Get-ADComputer -Filter "name -eq '$name'" -Property ObjectGUID).ObjectGUID.Guid
                }
                if ($deviceGUID) {
                    Write-Verbose "Search for the $name using its $deviceGUID GUID in Intune database"
                    # search for Intune device with GUID instead of name
                    $deviceIntuneRecord = @($intuneDevice | ? { $_.AzureADDeviceId -eq $deviceGUID })
                }
            }

            if (!$deviceIntuneRecord) {
                $deviceProperty.INTUNE_InDatabase = $false
            } else {
                # device is in Intune
                $deviceProperty.INTUNE_InDatabase = $true

                if ($deviceIntuneRecord.count -gt 1) {
                    # more records with the same name

                    $deviceProperty.INTUNE_MultipleRecords = $deviceIntuneRecord.count

                    Write-Verbose "Device $name is $($deviceIntuneRecord.count)x in Intune database!"

                    # get the correct one by using GUID
                    if (!$deviceGUID) {
                        $deviceGUID = $cmp.ObjectGUID.Guid
                    }
                    if (!$deviceGUID) {
                        $deviceGUID = $deviceProperty.AD_ObjectGUID
                    }
                    if (!$deviceGUID) {
                        $deviceGUID = (Get-ADComputer -Filter "name -eq '$name'" -Property ObjectGUID).ObjectGUID.Guid
                    }
                    if ($deviceGUID) {
                        Write-Verbose "Search for the $name with $deviceGUID GUID in Intune database"
                        $deviceIntuneRecord = @($intuneDevice | ? azureADDeviceId -EQ $deviceGUID)
                    }

                    if ($deviceIntuneRecord.count -gt 1) {
                        # unable to narrow down the results

                        if (!$deviceGUID) {
                            $erMsg = "No GUID property was provided to identify the correct one, nor was found in AD."
                        } else {
                            $erMsg = "Unable to identify the correct one."
                        }
                        Write-Warning "Device $name is $($deviceIntuneRecord.count)x in Intune database.`n$erMsg Therefore setting property deviceIntuneRecord as `$null"
                        $deviceIntuneRecord = $null
                    }
                } else {
                    $deviceProperty.INTUNE_MultipleRecords = $false
                }

                if ($deviceIntuneRecord.count -eq 1) {
                    $deviceProperty.INTUNE_Name = $deviceIntuneRecord.deviceName
                    $deviceProperty.INTUNE_DeviceId = $deviceIntuneRecord.azureADDeviceId
                    $deviceProperty.INTUNE_LastSyncDateTime = $deviceIntuneRecord.lastSyncDateTime
                    $deviceProperty.INTUNE_DeviceRegistrationState = $deviceIntuneRecord.deviceRegistrationState

                    if ($deviceIntuneRecord.deviceEnrollmentType -ne "windowsCoManagement") {
                        $deviceProperty.INTUNE_CoManaged = $false
                    } else {
                        $deviceProperty.INTUNE_CoManaged = $true
                        if (!$deviceProperty.SCCM_CoManaged -and $deviceProperty.SCCM_InDatabase -and $deviceProperty.SCCM_ClientInstalled) {
                            Write-Verbose "According to Intune, $name is co-managed even though SCCM says otherwise"
                        }
                    }

                    if (!$deviceIntuneRecord.aadRegistered -or !$deviceIntuneRecord.azureADRegistered) {
                        $deviceProperty.INTUNE_Registered = $false
                    } else {
                        $deviceProperty.INTUNE_Registered = $true
                    }

                    $deviceProperty.INTUNE_User = $deviceIntuneRecord.emailAddress
                }
            }
        }

        if ($combineDataFrom -contains "AAD") {

            $deviceAADRecord = @($aadDevice | ? DisplayName -EQ $name)

            if (!$deviceAADRecord) {
                Write-Verbose "$name wasn't found in Intune database, trying to get its GUID"

                # try to search for it using its GUID
                if (!$deviceGUID) {
                    $deviceGUID = $cmp.ObjectGUID.Guid
                }
                if (!$deviceGUID) {
                    $deviceGUID = $deviceProperty.AD_ObjectGUID
                }
                if (!$deviceGUID) {
                    $deviceGUID = (Get-ADComputer -Filter "name -eq '$name'" -Property ObjectGUID).ObjectGUID.Guid
                }
                if ($deviceGUID) {
                    Write-Verbose "Search for the $name using its $deviceGUID GUID in AAD database"
                    # search for AAD device with GUID instead of name
                    $deviceAADRecord = @($aadDevice | ? { $_.deviceId -eq $deviceGUID })
                }
            }

            if (!$deviceAADRecord) {
                $deviceProperty.AAD_InDatabase = $false
            } else {
                # device is in AAD
                $deviceProperty.AAD_InDatabase = $true

                if ($deviceAADRecord.count -gt 1) {
                    # more records with the same name

                    $deviceProperty.AAD_MultipleRecords = $deviceAADRecord.count

                    Write-Verbose "Device $name is $($deviceAADRecord.count)x in AAD database!"

                    # get the correct one using GUID
                    if (!$deviceGUID) {
                        $deviceGUID = $cmp.ObjectGUID.Guid
                    }
                    if (!$deviceGUID) {
                        $deviceGUID = $deviceProperty.AD_ObjectGUID
                    }
                    if (!$deviceGUID) {
                        $deviceGUID = (Get-ADComputer -Filter "name -eq '$name'" -Property ObjectGUID).ObjectGUID.Guid
                    }
                    if ($deviceGUID) {
                        Write-Verbose "Search for the $name with $deviceGUID GUID in AAD database"
                        $deviceAADRecord = @($aadDevice | ? deviceID -EQ $deviceGUID)
                    }

                    if ($deviceAADRecord.count -gt 1) {
                        # unable to narrow down the results

                        if (!$deviceGUID) {
                            $erMsg = "No GUID property was provided to identify the correct one, nor was found in AD."
                        } else {
                            $erMsg = "Unable to identify the correct one."
                        }
                        Write-Warning "Device $name is $($deviceAADRecord.count)x in AAD database.`n$erMsg Therefore setting property deviceAADRecord as `$null"
                        $deviceAADRecord = $null
                    }
                } else {
                    $deviceProperty.AAD_MultipleRecords = $false
                }

                if ($deviceAADRecord.count -eq 1) {
                    $deviceProperty.AAD_Name = $deviceAADRecord.displayName
                    $deviceProperty.AAD_LastActiveTime = $deviceAADRecord.approximateLastSignInDateTime
                    $deviceProperty.AAD_Owner = $deviceAADRecord.deviceOwnership
                    $deviceProperty.AAD_IsCompliant = $deviceAADRecord.isCompliant
                    $deviceProperty.AAD_DeviceId = $deviceAADRecord.deviceId
                    $deviceProperty.AAD_EnrollmentType = $deviceAADRecord.enrollmentType
                    $deviceProperty.AAD_IsManaged = $deviceAADRecord.isManaged
                    $deviceProperty.AAD_ManagementType = $deviceAADRecord.managementType
                    $deviceProperty.AAD_OnPremisesSyncEnabled = $deviceAADRecord.onPremisesSyncEnabled
                    $deviceProperty.AAD_ProfileType = $deviceAADRecord.profileType
                }
            }
        }

        New-Object -TypeName PSObject -Property $deviceProperty
    } # end of foreach
}