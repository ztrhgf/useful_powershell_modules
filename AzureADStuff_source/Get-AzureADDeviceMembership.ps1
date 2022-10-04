function Get-AzureADDeviceMembership {
    <#
    .SYNOPSIS
    Function for getting Azure device membership.

    .DESCRIPTION
    Function for getting Azure device membership.

    .PARAMETER deviceName
    Name of the device.

    .PARAMETER deviceObjectId
    ObjectID of the device.

    .PARAMETER transitiveMemberOf
    Switch for getting transitive memberOf.

    .PARAMETER header
    Authentication header.

    Can be created using New-GraphAPIAuthHeader.

    .EXAMPLE
    Connect-AzureAD2 -asYourself
    $header = New-GraphAPIAuthHeader -reuseExistingAzureADSession

    Get-AzureADDeviceMembership -deviceName PC-01

    .NOTES
    Original post: https://www.michev.info/Blog/Post/3096/reporting-on-group-membership-for-azure-ad-devices
    #>

    [CmdletBinding(DefaultParameterSetName = 'name')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "name")]
        [string] $deviceName,

        [Parameter(Mandatory = $true, ParameterSetName = "id")]
        [string] $deviceObjectId,

        [switch] $transitiveMemberOf,

        $header
    )

    if (!$header) {
        $header = New-GraphAPIAuthHeader -reuseExistingAzureADSession -ErrorAction Stop
    }

    #region get device details
    Write-Verbose "Get device details"
    if ($deviceName) {
        # name
        $uri = "https://graph.microsoft.com/v1.0/devices?`$filter=displayName eq '$deviceName'&`$select=displayName,id,deviceId"
        $deviceObj = Invoke-GraphAPIRequest -header $header -uri $uri
        $deviceObjectId = $deviceObj.id
    } else {
        # id
        $uri = "https://graph.microsoft.com/v1.0/devices/$deviceObjectId?`$select=displayName,id,deviceId"
        $deviceObj = Invoke-GraphAPIRequest -header $header -uri $uri
    }

    # it or name doesn't correspond to any device
    if (!$deviceObj.displayName) {
        throw "Device wasn't found"
    }
    #endregion get device details

    #region get device group membership
    if ($transitiveMemberOf) {
        $method = "transitivememberof"
    } else {
        $method = "memberof"
    }

    Write-Verbose "Get device membership"
    $uri = "https://graph.microsoft.com/v1.0/devices/$deviceObjectId/$method`?`$select=displayName,id,groupTypes,mailEnabled,securityEnabled"
    $deviceMemberOf = Invoke-GraphAPIRequest -header $header -uri $uri | select -Property DisplayName, @{n = 'ObjectId'; e = { $_.Id } }, GroupTypes, MailEnabled, SecurityEnabled
    $deviceObj | Add-Member -MemberType NoteProperty -Name "MemberOf" -Value $deviceMemberOf
    #endregion get device group membership

    # output the result
    $deviceObj
}