function Get-CMCollectionOGV {
    param (
        [ValidateNotNullOrEmpty()]
        [string] $sccmServer = $_SCCMServer
        ,
        [ValidateNotNullOrEmpty()]
        [string] $siteCode = $_SCCMSiteCode
        ,
        [string] $title = "Vyber kolekci"
        ,
        [ValidateSet('Multiple', 'Single')]
        [string] $outputMode = "Multiple"
        ,
        [ValidateSet('user', 'device', 'all')]
        [string[]] $type = "all"
        ,
        [switch] $returnAsObject
    )

    if ($type -eq "user") {
        $collectionType = 1
    } elseif ($type -eq "device") {
        $collectionType = 2
    } else {
        $collectionType = 1, 2
    }
    $collection = Get-WmiObject -ComputerName $sccmServer -Namespace "root\sms\site_$siteCode" -Query 'SELECT * FROM SMS_Collection' | ? { $_.CollectionType -in $collectionType } | select Name, Comment, MemberCount, RefreshType, CollectionID | sort Name | ogv -OutputMode $outputMode -Title $title
    if ($returnAsObject) {
        $collection
    } else {
        $collection | select -exp Name
    }
}