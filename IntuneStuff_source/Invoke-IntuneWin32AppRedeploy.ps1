#Requires -RunAsAdministrator
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

    .PARAMETER excludeSystemApp
    Switch for excluding Apps targeted to SYSTEM.

    .EXAMPLE
    Invoke-IntuneWin32AppRedeploy

    Get and show Win32App(s) deployed from Intune to this computer. Selected ones will be then redeployed.
    IDs of targeted users and apps will be translated using information from local Intune log files.

    .EXAMPLE
    Invoke-IntuneWin32AppRedeploy -computerName PC-01 -getDataFromIntune credential $creds

    Get and show Win32App(s) deployed from Intune to computer PC-01. IDs of apps and targeted users will be translated to corresponding names. Selected ones will be then redeployed.
    #>

    [CmdletBinding()]
    param (
        [string] $computerName,

        [switch] $getDataFromIntune,

        [System.Management.Automation.PSCredential] $credential,

        [string] $tenantId
    )

    if (!(Get-Command Get-IntuneWin32App)) {
        throw "Command Get-IntuneWin32App is missing"
    }

    if (! ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        throw "Run as admin"
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
            $appMatch = Select-String -Path $intuneLog -Pattern "\[Win32App\] ExecManager: processing targeted app .+ id='$appId'" -Context 0, 2
            if ($appMatch) {
                foreach ($match in $appMatch) {
                    $hash = ([regex]"\d+:Hash = ([^]]+)\]").Matches($match).captures.groups[1].value
                    if ($hash) {
                        return $hash
                    }
                }
            }
        }

        Write-Verbose "Unable to find App '$appId' GRS hash in any of the Intune log files. Redeploy will probably not work as expected"
    }
    # create helper functions text definition for usage in remote sessions
    $allFunctionDefs = "function Get-Win32AppGRSHash { ${function:Get-Win32AppGRSHash} };"
    #endregion helper function

    #region get deployed Win32Apps
    $param = @{}
    if ($computerName) { $param.computerName = $computerName }
    if ($getDataFromIntune) { $param.getDataFromIntune = $true }
    if ($credential) { $param.credential = $credential }
    if ($tenantId) { $param.tenantId = $tenantId }

    Write-Verbose "Getting deployed Win32Apps"
    $win32App = Get-IntuneWin32App @param
    #endregion get deployed Win32Apps

    if ($win32App) {
        $appToRedeploy = $win32App | Out-GridView -PassThru -Title "Pick app(s) for redeploy"

        #region redeploy selected Win32Apps
        if ($appToRedeploy) {
            $scriptBlock = {
                param ($verbosePref, $allFunctionDefs, $appToRedeploy)

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
                    if (!$appId) { throw "ID property is missing. Problem is probably in function Get-IntuneWin32App." }
                    if (!$scopeId) { throw "ScopeId property is missing. Problem is probably in function Get-IntuneWin32App." }
                    $txt = $appName
                    if (!$txt) { $txt = $appId }
                    Write-Verbose "Redeploying app $txt (scope $scope)"

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

                Write-Warning "Invoking redeploy (by removing registry key and restarting service IntuneManagementExtension). Redeploy can take several minutes!"
                Restart-Service IntuneManagementExtension -Force
            }

            $param = @{
                scriptBlock  = $scriptBlock
                argumentList = ($VerbosePreference, $allFunctionDefs, $appToRedeploy)
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