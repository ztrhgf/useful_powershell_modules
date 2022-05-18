function Clear-CMClientCache {
    <#
    .SYNOPSIS
        vymaze cache SCCM klienta (persistentni balicky ponecha)
    .DESCRIPTION
        vymaze cache SCCM klienta (persistentni balicky ponecha)
        druha varianta https://gallery.technet.microsoft.com/scriptcenter/Deleting-the-SCCM-Cache-da03e4c7
    #>

    [cmdletbinding()]
    Param (
        [Parameter(ValueFromPipeline = $True, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName = "localhost"
    )

    PROCESS {
        Invoke-Command2 -ComputerName $ComputerName -ScriptBlock {
            $Computer = $env:COMPUTERNAME

            if (! ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
                throw "You don't have administrator rights"
            }

            Try {
                #Connect to Resource Manager COM Object
                $resman = New-Object -com "UIResource.UIResourceMgr"
                $cacheInfo = $resman.GetCacheInfo()

                #Enum Cache elements, compare date, and delete older than 60 days
                $cacheinfo.GetCacheElements() | foreach { $cacheInfo.DeleteCacheElement($_.CacheElementID) }
                if ($?) {
                    Write-Output "$computer hotovo"
                }

            } catch {
                Write-Output "$computer error"
            }
        }
    }
}