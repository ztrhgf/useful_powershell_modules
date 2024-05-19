function Invoke-GraphAPIRequest {
    <#
    .SYNOPSIS
    Function for creating request against Microsoft Graph API.

    .DESCRIPTION
    Function for creating request against Microsoft Graph API.

    It supports paging and throttling.

    .PARAMETER uri
    Request URI.

    https://graph.microsoft.com/v1.0/me/
    https://graph.microsoft.com/v1.0/devices
    https://graph.microsoft.com/v1.0/users
    https://graph.microsoft.com/v1.0/groups
    https://graph.microsoft.com/beta/servicePrincipals?&$expand=appRoleAssignedTo
    https://graph.microsoft.com/beta/servicePrincipals?$select=id,appId,servicePrincipalType,displayName
    https://graph.microsoft.com/beta/servicePrincipals?$filter=(servicePrincipalType%20eq%20%27ManagedIdentity%27)
    https://graph.microsoft.com/beta/servicePrincipals?$filter=contains(serialNumber,'$encoded')
    https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicySettingStateSummaries/1234/deviceComplianceSettingStates?`$filter=NOT(state eq 'compliant')
    https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$select=id&`$filter=complianceState eq 'compliant'
    https://graph.microsoft.com/beta/users?`$select=id,userPrincipalName,displayName,mail,otherMails,proxyAddresses&`$filter=proxyAddresses/any(c:c eq 'smtp:$technicalNotificationMail') or otherMails/any(c:c eq 'smtp:$technicalNotificationMail')

    .PARAMETER credential
    Credentials used for creating authentication header for request.

    .PARAMETER header
    Authentication header for request.

    .PARAMETER method
    Default is GET.

    .PARAMETER waitTime
    Number of seconds before new try in case of 'Too Many Requests' error.

    Default is 5 seconds.

    .EXAMPLE
    $header = New-GraphAPIAuthHeader -credential $intuneCredential
    $aadDevice = Invoke-GraphAPIRequest -Uri "https://graph.microsoft.com/v1.0/devices" -header $header | Get-MSGraphAllPages

    .EXAMPLE
    $aadDevice = Invoke-GraphAPIRequest -Uri "https://graph.microsoft.com/v1.0/devices" -credential $intuneCredential | Get-MSGraphAllPages

    .NOTES
    https://configmgrblog.com/2017/12/05/so-what-can-we-do-with-microsoft-intune-via-microsoft-graph-api/
    #>

    [CmdletBinding()]
    [Alias("Invoke-MgRequest")]
    param (
        [Parameter(Mandatory = $true)]
        [string] $uri,

        [Parameter(Mandatory = $true, ParameterSetName = "credential")]
        [System.Management.Automation.PSCredential] $credential,

        [Parameter(Mandatory = $true, ParameterSetName = "header")]
        $header,

        [ValidateSet('GET', 'POST', 'DELETE', 'UPDATE')]
        [string] $method = "GET",

        [ValidateRange(1, 999)]
        [int] $waitTime = 5
    )

    Write-Verbose "uri $uri"

    if ($credential) {
        $header = New-GraphAPIAuthHeader -credential $credential
    }

    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $header -Method $method -ErrorAction Stop
    } catch {
        switch ($_) {
            { $_ -like "*(429) Too Many Requests*" } {
                Write-Warning "(429) Too Many Requests. Waiting $waitTime seconds to avoid further throttling and try again"
                Start-Sleep $waitTime
                Invoke-GraphAPIRequest -uri $uri -header $header -method $method
            }
            { $_ -like "*(400) Bad Request*" } { throw "(400) Bad Request. There has to be some syntax/logic mistake in this request ($uri)" }
            { $_ -like "*(401) Unauthorized*" } { throw "(401) Unauthorized Request (new auth header has to be created?)" }
            { $_ -like "*Forbidden*" } { throw "Forbidden access. Use account with correct API permissions for this request ($uri)" }
            default { throw $_ }
        }
    }

    # sometimes the results is in Value property, sometimes it is the returned object itself
    if ($response -and ($response | Get-Member -MemberType NoteProperty -Name Value)) {
        $response.Value
    } else {
        $response
    }

    # understand if top parameter is used in the URI
    try {
        $prevErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Stop"
        $topValue = ([regex]"top=(\d+)").Matches($uri).captures.groups[1].value
    } catch {
        Write-Verbose "uri ($uri) doesn't contain TOP"
    } finally {
        $ErrorActionPreference = $prevErrorActionPreference
    }

    if (!$topValue -or ($topValue -and $topValue -gt 100)) {
        # there can be more results to return, check that
        # need to loop the requests because only 100 results are returned each time
        $nextLink = $response.'@odata.nextLink'
        while ($nextLink) {
            Write-Verbose "Next uri $nextLink"
            try {
                $response = Invoke-RestMethod -Uri $NextLink -Headers $header -Method $method -ErrorAction Stop
            } catch {
                switch ($_) {
                    { $_ -like "*(429) Too Many Requests*" } {
                        Write-Warning "(429) Too Many Requests. Waiting $waitTime seconds to avoid further throttling and try again"
                        Start-Sleep $waitTime
                        Invoke-GraphAPIRequest -uri $NextLink -header $header -method $method
                    }
                    { $_ -like "*(400) Bad Request*" } { throw "(400) Bad Request. There has to be some syntax/logic mistake in this request ($uri)" }
                    { $_ -like "*(401) Unauthorized*" } { throw "(401) Unauthorized Request (new auth header has to be created?)" }
                    { $_ -like "*Forbidden*" } { throw "Forbidden access. Use account with correct API permissions for this request ($uri)" }
                    default { throw $_ }
                }
            }

            # sometimes the results is in Value property, sometimes it is the returned object itself
            if ($response -and ($response | Get-Member -MemberType NoteProperty -Name Value)) {
                $response.Value
            } else {
                $response
            }

            $nextLink = $response.'@odata.nextLink'
        }
    } else {
        # to avoid 'Too Many Requests' error when working with Graph API (/auditLogs/signIns) and using top parameter
        Write-Verbose "There is no need to check if more results can be returned. I.e. if parameter 'top' is used in the URI it is lower than 100 (so all results will be returned in the first request anyway)"
    }
}