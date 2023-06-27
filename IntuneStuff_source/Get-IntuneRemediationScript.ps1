function Get-IntuneRemediationScript {
    <#
    .SYNOPSIS
    Function for showing Remediation scripts deployed from Intune to local/remote computer.

    Scripts details are gathered from clients registry (HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\IntuneManagementExtension\SideCarPolicies\Scripts\Execution) and Intune log file ($env:ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log).

    .DESCRIPTION
    Function for showing Remediation scripts deployed from Intune to local/remote computer.

    Scripts details are gathered from clients registry (HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\IntuneManagementExtension\SideCarPolicies\Scripts\Execution) and Intune log file ($env:ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log).

    .PARAMETER computerName
    Name of remote computer where you want to get the data from.

    .PARAMETER getDataFromIntune
    Switch for getting Scripts and User names from Intune, so locally used IDs can be translated to them.

    .PARAMETER credential
    Credential object used for Intune authentication.

    .PARAMETER tenantId
    Azure Tenant ID.
    Requirement for Intune App authentication.

    .EXAMPLE
    Get-IntuneRemediationScript

    Get and show common Remediation script(s) deployed from Intune to this computer.
    #>

    [CmdletBinding()]
    param (
        [string] $computerName,

        [switch] $getDataFromIntune,

        [System.Management.Automation.PSCredential] $credential,

        [string] $tenantId
    )

    if (!$computerName) {
        # access to registry key "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension" now needs admin permission
        if (! ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
            throw "Function '$($MyInvocation.MyCommand)' needs to be run with administrator permission"
        }
    }

    #region helper function
    function _getRemediationScript {
        param ([string] $scriptID)
        $intuneRemediationScript | ? id -EQ $scriptID
    }

    function _getScopeName {
        param ([string] $id)

        Write-Verbose "Translating $id"

        if (!$id) {
            Write-Verbose "id was null"
            return
        } elseif ($id -eq 'device') {
            # xml nodes contains 'device' instead of 'Device'
            return 'Device'
        }

        $errPref = $ErrorActionPreference
        $ErrorActionPreference = "Stop"
        try {
            if ($id -eq '00000000-0000-0000-0000-000000000000' -or $id -eq 'S-0-0-00-0000000000-0000000000-000000000-000') {
                return 'Device'
            } elseif ($id -match "^S-\d+-\d+-\d+") {
                # it is local account
                return ((New-Object System.Security.Principal.SecurityIdentifier($id)).Translate([System.Security.Principal.NTAccount])).Value
            } else {
                # it is AzureAD account
                if ($getDataFromIntune) {
                    return ($intuneUser | ? id -EQ $id).userPrincipalName
                } else {
                    $userSID = Get-UserSIDForUserAzureID $id
                    if ($userSID) {
                        _getScopeName $userSID
                    } else {
                        return $id
                    }
                }
            }
        } catch {
            Write-Warning "Unable to translate $id to account name ($_)"
            $ErrorActionPreference = $errPref
            return $id
        }
    }

    # create helper functions text definition for usage in remote sessions
    if ($computerName) {
        $allFunctionDefs = "function _getScopeName { ${function:_getScopeName} }; function _getIntuneScript { ${function:_getIntuneScript} }; function _getRemediationScript { ${function:_getRemediationScript} }; function Get-UserSIDForUserAzureID { ${function:Get-UserSIDForUserAzureID} }; function Get-IntuneLogRemediationScriptData { ${function:Get-IntuneLogRemediationScriptData} }"
    }
    #endregion helper function

    #region prepare
    if ($getDataFromIntune) {
        if (!(Get-Module 'Microsoft.Graph.Intune') -and !(Get-Module 'Microsoft.Graph.Intune' -ListAvailable)) {
            throw "Module 'Microsoft.Graph.Intune' is required. To install it call: Install-Module 'Microsoft.Graph.Intune' -Scope CurrentUser"
        }

        if ($tenantId) {
            # app logon
            if (!$credential) {
                $credential = Get-Credential -Message "Enter AppID and AppSecret for connecting to Intune tenant" -ErrorAction Stop
            }
            Update-MSGraphEnvironment -AppId $credential.UserName -Quiet
            Update-MSGraphEnvironment -AuthUrl "https://login.windows.net/$tenantId" -Quiet
            $null = Connect-MSGraph -ClientSecret $credential.GetNetworkCredential().Password -ErrorAction Stop
        } else {
            # user logon
            if ($credential) {
                $null = Connect-MSGraph -Credential $credential -ErrorAction Stop
                # $header = New-GraphAPIAuthHeader -credential $credential -ErrorAction Stop
            } else {
                $null = Connect-MSGraph -ErrorAction Stop
                # $header = New-GraphAPIAuthHeader -ErrorAction Stop
            }
        }

        Write-Verbose "Getting Intune data"
        # filtering by ID is as slow as getting all data
        # Invoke-MSGraphRequest -Url 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?$filter=(id%20eq%20%2756695a77-925a-4df0-be79-24ed039afa86%27)'
        $intuneRemediationScript = Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts?select=id,displayname" | Get-MSGraphAllPages
        $intuneUser = Invoke-MSGraphRequest -Url 'https://graph.microsoft.com/beta/users?select=id,userPrincipalName' | Get-MSGraphAllPages
    }

    if ($computerName) {
        $session = New-PSSession -ComputerName $computerName -ErrorAction Stop
    }
    #endregion prepare

    #region get data
    $scriptBlock = {
        param($verbosePref, $getDataFromIntune, $intuneRemediationScript, $intuneUser, $allFunctionDefs)

        # inherit verbose settings from host session
        $VerbosePreference = $verbosePref

        # recreate functions from their text definitions
        . ([ScriptBlock]::Create($allFunctionDefs))

        # get additional script data (script content etc)
        $scriptData = Get-IntuneLogRemediationScriptData

        Get-ChildItem "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\SideCarPolicies\Scripts\Reports" -ErrorAction SilentlyContinue | % {
            $userAzureObjectID = Split-Path $_.Name -Leaf
            $userRemScriptRoot = $_.PSPath

            # $lastFullReportTimeUTC = Get-ItemPropertyValue $userRemScriptRoot -Name LastFullReportTimeUTC
            $remScriptIDList = Get-ChildItem $userRemScriptRoot | select -ExpandProperty PSChildName | % { $_ -replace "_\d+$" } | select -Unique

            $remScriptIDList | % {
                $remScriptID = $_

                Write-Verbose "`tID $remScriptID"

                $newestRemScriptRecord = Get-ChildItem $userRemScriptRoot | ? PSChildName -Match ([regex]::escape($remScriptID)) | Sort-Object -Descending -Property PSChildName | select -First 1

                try {
                    $result = Get-ItemPropertyValue "$($newestRemScriptRecord.PSPath)\Result" -Name Result | ConvertFrom-Json
                } catch {
                    Write-Verbose "`tUnable to get Remediation Script Result data"
                }

                $lastExecution = Get-ItemPropertyValue "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\SideCarPolicies\Scripts\Execution\$userAzureObjectID\$($newestRemScriptRecord.PSChildName)" -Name LastExecution

                $extraScriptData = $scriptData | ? PolicyId -EQ $remScriptID

                if ($getDataFromIntune) {
                    $property = [ordered]@{
                        "Scope"                             = _getScopeName $userAzureObjectID
                        "DisplayName"                       = (_getRemediationScript $remScriptID).DisplayName
                        "Id"                                = $remScriptID
                        "LastError"                         = $result.ErrorCode
                        "LastExecution"                     = $lastExecution
                        # LastFullReportTimeUTC               = $lastFullReportTimeUTC
                        "InternalVersion"                   = $result.InternalVersion
                        "PreRemediationDetectScriptOutput"  = $result.PreRemediationDetectScriptOutput
                        "PreRemediationDetectScriptError"   = $result.PreRemediationDetectScriptError
                        "RemediationScriptErrorDetails"     = $result.RemediationScriptErrorDetails
                        "PostRemediationDetectScriptOutput" = $result.PostRemediationDetectScriptOutput
                        "PostRemediationDetectScriptError"  = $result.PostRemediationDetectScriptError
                        "RemediationExitCode"               = $result.Info.RemediationExitCode
                        "FirstDetectExitCode"               = $result.Info.FirstDetectExitCode
                        "LastDetectExitCode"                = $result.Info.LastDetectExitCode
                        "ErrorDetails"                      = $result.Info.ErrorDetails
                    }
                } else {
                    # no 'DisplayName' property
                    $property = [ordered]@{
                        "Scope"                             = _getScopeName $userAzureObjectID
                        "Id"                                = $remScriptID
                        "LastError"                         = $result.ErrorCode
                        "LastExecution"                     = $lastExecution
                        # LastFullReportTimeUTC               = $lastFullReportTimeUTC
                        "InternalVersion"                   = $result.InternalVersion
                        "PreRemediationDetectScriptOutput"  = $result.PreRemediationDetectScriptOutput
                        "PreRemediationDetectScriptError"   = $result.PreRemediationDetectScriptError
                        "RemediationScriptErrorDetails"     = $result.RemediationScriptErrorDetails
                        "PostRemediationDetectScriptOutput" = $result.PostRemediationDetectScriptOutput
                        "PostRemediationDetectScriptError"  = $result.PostRemediationDetectScriptError
                        "RemediationExitCode"               = $result.Info.RemediationExitCode
                        "FirstDetectExitCode"               = $result.Info.FirstDetectExitCode
                        "LastDetectExitCode"                = $result.Info.LastDetectExitCode
                        "ErrorDetails"                      = $result.Info.ErrorDetails
                    }
                }

                # add additional properties when possible
                if ($extraScriptData) {
                    Write-Verbose "Enrich script object data with information found in Intune log files"

                    $extraScriptData = $extraScriptData | select * -ExcludeProperty AccountId, PolicyId, DocumentSchemaVersion

                    $newProperty = Get-Member -InputObject $extraScriptData -MemberType NoteProperty
                    $newProperty | % {
                        $propertyName = $_.Name
                        $propertyValue = $extraScriptData.$propertyName

                        $property.$propertyName = $propertyValue
                    }
                } else {
                    Write-Verbose "For script $remScriptID there are no extra information in Intune log files"
                }

                New-Object -TypeName PSObject -Property $property
            }
        }
    }

    $param = @{
        scriptBlock  = $scriptBlock
        argumentList = ($VerbosePreference, $getDataFromIntune, $intuneRemediationScript, $intuneUser, $allFunctionDefs)
    }
    if ($computerName) {
        $param.session = $session
    }

    Invoke-Command @param | select -Property * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName
    #endregion get data

    if ($computerName) {
        Remove-PSSession $session
    }
}