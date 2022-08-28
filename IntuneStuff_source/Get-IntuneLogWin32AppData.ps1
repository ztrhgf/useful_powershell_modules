function Get-IntuneLogWin32AppData {
    <#
    .SYNOPSIS
    Function for getting Intune Win32Apps information from clients log files ($env:ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension*.log).

    .DESCRIPTION
    Function for getting Intune Win32Apps information from clients log files ($env:ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension*.log).

    Finds data about last processing of Win32Apps and outputs them into console as an PowerShell object.

    Returns various information like app detection and requirement scripts etc.

    .EXAMPLE
    $win32AppData = Get-IntuneLogWin32AppData

    $myApp = ($win32AppData | ? Name -eq 'MyApp')

    "Output complete object"
    $myApp

    "Detection script content for application 'MyApp'"
    $myApp.DetectionRule.DetectionText.ScriptBody

    "Requirement script content for application 'MyApp'"
    $myApp.ExtendedRequirementRules.RequirementText.ScriptBody

    "Installation script content for application 'MyApp'"
    $myApp.InstallCommandLine

    Show various interesting information for MyApp application deployment.

    .NOTES
    Run on Windows client managed using Intune MDM.
    #>

    [CmdletBinding()]
    param ()

    #region helper functions
    function ConvertFrom-Base64 {
        param ($encodedString)
        [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($encodedString))
    }

    function _enhanceObject {
        param ($object)

        $object | select *,
        @{n = 'DetectionRule'; e = { $_.DetectionRule | ConvertFrom-Json | select @{n = 'DetectionType'; e = { $_.DetectionType } }, @{n = 'DetectionText'; e = { $r = $_.DetectionText | ConvertFrom-Json; $r | select *, @{n = 'ScriptBody'; e = { ConvertFrom-Base64 ($_.ScriptBody -replace "^77u/") } } -ExcludeProperty 'ScriptBody' } } } },
        @{n = 'RequirementRules'; e = { $_.RequirementRules | ConvertFrom-Json } },
        @{n = 'ExtendedRequirementRules'; e = { $r = $_.ExtendedRequirementRules | ConvertFrom-Json; $r | select *, @{n = 'RequirementText'; e = { $r = $_.RequirementText | ConvertFrom-Json; $r | select *, @{n = 'ScriptBody'; e = { ConvertFrom-Base64 $_.ScriptBody } } -ExcludeProperty 'ScriptBody' } } -ExcludeProperty 'RequirementText' } },
        @{n = 'InstallEx'; e = { $_.InstallEx | ConvertFrom-Json } },
        @{n = 'ReturnCodes'; e = { $_.ReturnCodes | ConvertFrom-Json } }`
            -ExcludeProperty DetectionRule, RequirementRules, ExtendedRequirementRules, InstallEx, ReturnCodes
    }
    #endregion helper functions

    # get list of available Intune logs
    $intuneLogList = Get-ChildItem -Path "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs" -Filter "IntuneManagementExtension*.log" -File | sort LastWriteTime -Descending | select -ExpandProperty FullName

    if (!$intuneLogList) {
        Write-Error "Unable to find any Intune log files. Unable to get script content."
        return
    }

    foreach ($intuneLog in $intuneLogList) {
        # how content of the log can looks like
        # <![LOG[Get policies = [{"Id":"56695a77-925a-4....

        Write-Verbose "Searching for Win32Apps in '$intuneLog'"

        # get line text where win32apps processing is mentioned
        $match = Select-String -Path $intuneLog -Pattern ("^" + [regex]::escape('<![LOG[Get policies = [{"Id":')) -List | select -ExpandProperty Line

        if ($match) {
            # get rid of non-JSON prefix/suffix
            $jsonList = $match -replace [regex]::Escape("<![LOG[Get policies = [") -replace ([regex]::Escape("]]LOG]!>") + ".*")
            # ugly but working solution :D
            $i = 0
            $jsonListSplitted = $jsonList -split '},{"Id":'
            if ($jsonListSplitted.count -gt 1) {
                # there are multiple JSONs divided by comma, I have to process them one by one
                $jsonListSplitted | % {
                    # split replaces text that was used to split, I have to recreate it
                    $json = ""
                    if ($i -eq 0) {
                        # first item
                        $json = $_ + '}'
                    } elseif ($i -ne ($jsonListSplitted.count - 1)) {
                        $json = '{"Id":' + $_ + '}'
                    } else {
                        # last item
                        $json = '{"Id":' + $_
                    }

                    ++$i

                    # customize converted object (convert base64 to text and JSON to object)
                    _enhanceObject ($json | ConvertFrom-Json)
                }
            } else {
                # there is just one JSON, I can directly convert it to an object
                # customize converted object (convert base64 to text and JSON to object)
                _enhanceObject ($jsonList | ConvertFrom-Json)
            }

            break # don't continue the search when you already have match
        } else {
            Write-Verbose "There is no data related to Win32App. Trying next log."
        }
    }
}