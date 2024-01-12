function Invoke-IntuneWin32AppRedeploy {
    <#
    .SYNOPSIS
    Function for forcing redeploy of selected Win32App deployed from Intune.

    .DESCRIPTION
    Function for forcing redeploy of selected Win32App deployed from Intune.

    OutGridView is used to output discovered Apps.

    Redeploy means that corresponding registry keys will be deleted from registry and service IntuneManagementExtension will be restarted.

    .PARAMETER computerName
    Name of remote computer where you want to force the redeploy.

    .PARAMETER getDataFromIntune
    Switch for getting Apps and User names from Intune, so locally used IDs can be translated.
    If you omit this switch, local Intune logs will be searched for such information instead.

    .PARAMETER credential
    Credential object used for Intune authentication.

    .PARAMETER tenantId
    Azure Tenant ID.
    Requirement for Intune App authentication.

    .PARAMETER dontWait
    Don't wait on Win32App redeploy completion.

    .PARAMETER noDetails
    Show just basic app data in the GUI.

    .EXAMPLE
    Invoke-IntuneWin32AppRedeploy

    Get and show Win32App(s) deployed from Intune to this computer. Selected ones will be then redeployed.
    IDs of targeted users and apps will be translated using information from local Intune log files.

    .EXAMPLE
    Invoke-IntuneWin32AppRedeploy -computerName PC-01 -getDataFromIntune credential $creds

    Get and show Win32App(s) deployed from Intune to computer PC-01. IDs of apps and targeted users will be translated to corresponding names. Selected ones will be then redeployed.
    #>

    [CmdletBinding()]
    [Alias("Invoke-IntuneWin32AppRedeployLocally")]
    param (
        [string] $computerName,

        [Alias("online")]
        [switch] $getDataFromIntune,

        [System.Management.Automation.PSCredential] $credential,

        [string] $tenantId,

        [switch] $dontWait,

        [switch] $noDetails
    )

    if (!(Get-Command Get-IntuneWin32AppLocally)) {
        throw "Command Get-IntuneWin32AppLocally is missing"
    }

    if (!$computerName) {
        # access to registry key "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension" now needs admin permission
        if (! ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
            throw "Function '$($MyInvocation.MyCommand)' needs to be run with administrator permission"
        }
    }

    #region helper function
    # function gets app GRS hash from Intune log files
    function Get-Win32AppGRSHash {
        param (
            [Parameter(Mandatory = $true)]
            [string] $appId
        )

        $intuneLogList = Get-ChildItem -Path "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs" -Filter "IntuneManagementExtension*.log" -File | sort LastWriteTime -Descending | select -ExpandProperty FullName

        if (!$intuneLogList) {
            Write-Error "Unable to find any Intune log files. Redeploy will probably not work as expected."
            return
        }

        foreach ($intuneLog in $intuneLogList) {
            $appMatch = Select-String -Path $intuneLog -Pattern "\[Win32App\]\[V3Processor\] Processing subgraph with app ids: $appId" -Context 0, 1
            if ($appMatch) {
                foreach ($match in $appMatch) {
                    $hash = ([regex]"\\GRS\\(.*)\\").Matches($match).captures.groups[1].value
                    if ($hash) {
                        return $hash
                    }
                }
            }
        }

        Write-Verbose "Unable to find App '$appId' GRS hash in any of the Intune log files. Redeploy will probably not work as expected"
    }
    # create helper functions text definition for usage in remote sessions
    $allFunctionDefs = "function Get-Win32AppGRSHash { ${function:Get-Win32AppGRSHash} }; function Invoke-FileContentWatcher { ${function:Invoke-FileContentWatcher} }"
    #endregion helper function

    #region get deployed Win32Apps
    $param = @{}
    if ($computerName) { $param.computerName = $computerName }
    if ($getDataFromIntune) { $param.getDataFromIntune = $true }
    if ($credential) { $param.credential = $credential }
    if ($tenantId) { $param.tenantId = $tenantId }

    Write-Verbose "Getting deployed Win32Apps"
    $win32App = Get-IntuneWin32AppLocally @param
    #endregion get deployed Win32Apps

    if ($win32App) {
        if ($noDetails) {
            $win32App = $win32App | select -Property Name, Id, Scope, ComplianceState, DesiredState, DeploymentType, ScopeId
        }

        $appToRedeploy = $win32App | Out-GridView -PassThru -Title "Pick app(s) for redeploy"

        #region redeploy selected Win32Apps
        if ($appToRedeploy) {
            $scriptBlock = {
                param ($verbosePref, $allFunctionDefs, $appToRedeploy, $dontWait)

                # inherit verbose settings from host session
                $VerbosePreference = $verbosePref

                # recreate functions from their text definitions
                . ([ScriptBlock]::Create($allFunctionDefs))

                $win32AppKeys = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps" -Recurse -Depth 2 | select PSChildName, PSPath, PSParentPath

                $appToRedeploy | % {
                    $appId = $_.id
                    $appName = $_.name
                    $scopeId = $_.scopeId
                    $scope = $_.scope
                    if ($scopeId -eq 'device') { $scopeId = "00000000-0000-0000-0000-000000000000" }
                    if (!$appId) { throw "ID property is missing. Problem is probably in function Get-IntuneWin32AppLocally." }
                    if (!$scopeId) { throw "ScopeId property is missing. Problem is probably in function Get-IntuneWin32AppLocally." }
                    $txt = $appName
                    if (!$txt) { $txt = $appId }
                    Write-Warning "Preparing redeploy for Win32App '$txt' (scope $scope) by deleting it's registry key"

                    $win32AppKeyToDelete = $win32AppKeys | ? { $_.PSChildName -Match "^$appId`_\d+" -and $_.PSParentPath -Match "\\$scopeId$" }

                    if ($win32AppKeyToDelete) {
                        $win32AppKeyToDelete | % {
                            Write-Verbose "Deleting $($_.PSPath)"
                            Remove-Item $_.PSPath -Force -Recurse
                        }

                        # GRS key needs to be deleted too https://call4cloud.nl/2022/07/retry-lola-retry/#part1-4
                        $win32AppKeyGRSHash = Get-Win32AppGRSHash $appId
                        if ($win32AppKeyGRSHash) {
                            $win32AppGRSKeys = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\$scopeId\GRS"
                            $win32AppGRSKeyToDelete = $win32AppGRSKeys | ? { $_.PSChildName -eq $win32AppKeyGRSHash }
                            if ($win32AppGRSKeyToDelete) {
                                Write-Verbose "Deleting $($win32AppGRSKeyToDelete.PSPath)"
                                Remove-Item $win32AppGRSKeyToDelete.PSPath -Force -Recurse
                            }
                        }
                    } else {
                        throw "BUG??? App $appId with scope $scopeId wasn't found in the registry"
                    }
                }

                Write-Warning "Invoking redeploy (by restarting service IntuneManagementExtension). Redeploy can take several minutes!"
                Restart-Service IntuneManagementExtension -Force

                if (!$dontWait) {
                    Write-Warning "Waiting for start of the Intune Win32App(s) redeploy (this can take minute or two)"
                    $null = Invoke-FileContentWatcher -path "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log" -searchString "Load global Win32App settings" -stopOnFirstMatch
                    Write-Warning "Waiting for the completion of the Intune Win32App(s) redeploy (this can take several minutes!)"
                    $null = Invoke-FileContentWatcher -path "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log" -searchString "application poller stopped." -stopOnFirstMatch
                }
            }

            $param = @{
                scriptBlock  = $scriptBlock
                argumentList = ($VerbosePreference, $allFunctionDefs, $appToRedeploy, $dontWait)
            }
            if ($computerName) {
                $param.computerName = $computerName
            }

            Invoke-Command @param
        }
        #endregion redeploy selected Win32Apps
    } else {
        Write-Warning "No deployed Win32App detected"
    }
}