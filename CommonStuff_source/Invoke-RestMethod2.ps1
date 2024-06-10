function Invoke-RestMethod2 {
    <#
    .SYNOPSIS
    Proxy function for Invoke-RestMethod.

    Adds support for:
     - pagination (by detecting '@odata.nextLink')
     - throttling (by adding sleep time before giving another try)

    .DESCRIPTION
    Proxy function for Invoke-RestMethod.

    Adds support for:
     - pagination (by detecting '@odata.nextLink')
     - throttling (by adding sleep time before giving another try)

    .PARAMETER uri
    URL.

    .PARAMETER method
    Request method.

    Possible values: GET, POST, PATCH, PUT, DELETE

    By default GET.

    .PARAMETER headers
    Authentication header etc.

    .PARAMETER body
    Request body.

    .PARAMETER waitTime
    Number of seconds to wait if error "too many requests" is detected.

    By default 30.

    .EXAMPLE
    $header = New-M365DefenderAuthHeader

    $url = "https://api-eu.securitycenter.microsoft.com/api/vulnerabilities/machinesVulnerabilities"

    Invoke-RestMethod2 -uri $url -headers $header
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $uri,

        [ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')]
        [string] $method = "GET",

        $headers,

        $body,

        [ValidateRange(1, 999)]
        [int] $waitTime = 30
    )

    function _result {
        param ($response)

        if ($response | Get-Member -MemberType NoteProperty | select -ExpandProperty name | ? { $_ -notin '@odata.context', '@odata.nextLink', '@odata.count', 'Value' }) {
            # only one item was returned, no expand is needed
            $response
        } else {
            # its more than one result, I need to expand the Value property
            $response.Value
        }
    }

    $uriLink = $uri
    $responseObj = $Null

    do {
        try {
            Write-Verbose $uriLink

            $param = @{
                ErrorAction = 'Stop'
                Method      = $method
                Uri         = $uriLink
            }
            if ($headers) {
                $param.Headers = $headers
            }
            if ($body) {
                $param.Body = $body
            }
            $responseObj = Invoke-RestMethod @param

            _result $responseObj

            # loop through '@odata.nextLink' to get all results
            $uriLink = $responseObj.'@odata.nextLink'
        } catch {
            switch ($_) {
                #TODO https://learn.microsoft.com/en-us/defender-endpoint/api/common-errors?view=o365-worldwide#throttling tzn vycitat sleep z Retry-After
                { $_ -like "*Too Many Requests*" -or $_ -like "*TooManyRequests*" } {
                    Write-Warning "Too Many Requests. Waiting $waitTime seconds to avoid further throttling before trying again"
                    Start-Sleep $waitTime
                }

                { $_ -like "*Gateway Time-out*" } {
                    Write-Warning "Gateway Time-out. Waiting $waitTime seconds before trying again"
                    Start-Sleep $waitTime
                }

                { $_ -like "*(400)*" } { throw "(400) Bad Request. There has to be some syntax/logic mistake in this request ($uri)" }

                { $_ -like "*(401)*" } { throw "(401) Unauthorized Request (new auth header has to be created?)" }

                { $_ -like "*(408)*" } {
                    Write-Warning "(408) Request Time-out. Waiting $waitTime seconds before trying again"
                    Start-Sleep $waitTime
                }

                { $_ -like "*Forbidden*" } { throw "Forbidden access. Use account with correct API permissions for this request ($uri)" }

                default {
                    Write-Error $_
                    # break the loop (break command wasn't working)
                    $uriLink = $null
                }
            }
        }
    } while ($uriLink)
}