function Get-CMDeploymentStatus {
    <#
    .SYNOPSIS
    Get SCCM (not just application) deployment status.

    .DESCRIPTION
    Get SCCM (not just application) deployment status.

    .PARAMETER name
    (optional) name of the deployment.

    .PARAMETER SCCMServer
    Name of the SCCM server.

    Default is $_SCCMServer.

    .PARAMETER SCCMSiteCode
    Name of the SCCM site.

    Default is $_SCCMSiteCode.

    .EXAMPLE
    Get-CMDeploymentStatus

    Returns deployment status of all deployments in SCCM.

    .EXAMPLE
    Get-CMDeploymentStatus -name CB_not_for_ConditionalAccess

    Returns deployment status of CB_not_for_ConditionalAccess compliance deployment.
    #>

    [CmdletBinding()]
    param (
        [string] $name,

        [ValidateNotNullOrEmpty()]
        [string] $SCCMServer = $_SCCMServer,

        [ValidateNotNullOrEmpty()]
        [string] $SCCMSiteCode = $_SCCMSiteCode
    )

    if ($name) {
        $nameFilter = "where SoftwareName = '$name'"
    }

    Get-WmiObject -ComputerName $SCCMServer -Namespace "root\SMS\site_$SCCMSiteCode" -Query "SELECT SoftwareName, CollectionName, NumberTargeted, NumberSuccess, NumberErrors, NumberInprogress, NumberOther, NumberUnknown FROM SMS_DeploymentSummary $nameFilter" | select SoftwareName, CollectionName, NumberTargeted, NumberSuccess, NumberErrors, NumberInprogress, NumberOther, NumberUnknown
}