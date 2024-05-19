
function Get-CMCollectionComplianceStatus {
    [CmdletBinding()]
    param (
        [ArgumentCompleter( {
                param ($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams)
                Get-CimInstance -Namespace "root\SMS\Site_$_SCCMSiteCode" -Query "select LocalizedDisplayName from SMS_ConfigurationBaselineInfo" -ComputerName $_SCCMServer | ? { $_.LocalizedDisplayName -like "*$WordToComplete*" } | % { '"' + $_.LocalizedDisplayName + '"' }
            })]
        [string[]] $confBaseline
        ,
        [ArgumentCompleter( {
                param ($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams)
                Get-CimInstance -Namespace "root\SMS\Site_$_SCCMSiteCode" -Query "select Name from SMS_Collection" -ComputerName $_SCCMServer | ? { $_.Name -like "*$WordToComplete*" } | % { '"' + $_.Name + '"' }
            })]
        [string[]] $collection
        ,
        [string[]] $computerName
    )

    if ($computerName -and $collection) {
        Write-Warning "Collection will be ignored, because you have selected computerName"
    }
    if (!$confBaseline -and !$computerName -and !$collection) {
        throw "You have to specify confBaseline and/or collection and/or computer"
    }

    $filter = ""

    if ($confBaseline) {
        $list = @()
        $confBaseline | % {
            $name = $_
            $list += Get-CimInstance -Namespace "root\SMS\Site_$_SCCMSiteCode" -Query "select LocalizedDisplayName, CI_ID from SMS_ConfigurationBaselineInfo" -ComputerName $_SCCMServer | ? { $_.LocalizedDisplayName -eq $name } | select -exp CI_ID
        }

        if ($filter) {
            $and = " and"
        }
        $list = $list -join ', '
        $filter += "$and CI.CI_ID IN($list)"
    }

    if ($computerName) {
        if ($filter) {
            $and = " and"
        }
        $computerName = ($computerName | % { "'" + $_ + "'" }) -join ', '
        $filter += "$and VRS.Netbios_Name0 IN($computerName)"
    }

    if ($collection) {
        $list = @()
        $collection | % {
            $name = $_
            $list += Get-CimInstance -Namespace "root\SMS\Site_$_SCCMSiteCode" -Query "select Name, CollectionID from SMS_Collection" -ComputerName $_SCCMServer | ? { $_.Name -eq $name } | select -exp CollectionID
        }

        if ($filter) {
            $and = " and"
        }
        $list = ($list | % { "'" + $_ + "'" }) -join ', '
        $filter += "$and FM.CollectionID IN ($list)"
    }

    $sqlCommand = "
    select distinct VRS.Netbios_Name0 as ComputerName, CI.UserName, CI.DisplayName, CI.ComplianceStateName from v_R_System VRS
    right join v_FullCollectionMembership_Valid FM on VRS.ResourceID=FM.ResourceID
    right join fn_ListCI_ComplianceState(1033) CI on VRS.ResourceID=CI.ResourceID
    where $filter"

    Write-Verbose $sqlCommand

    $a = Invoke-SQL -dataSource $_SCCMServer -database "CM_$_SCCMSiteCode" -sqlCommand $sqlCommand
    $a | select ComputerName, UserName, DisplayName, ComplianceStateName | Sort-Object ComputerName
}