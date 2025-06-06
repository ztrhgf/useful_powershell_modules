function New-GraphBatchRequest {
    <#
    .SYNOPSIS
    Function creates PSObject(s) representing request(s) that can be used in Graph Api batching.

    .DESCRIPTION
    Function creates PSObject(s) representing request(s) that can be used in Graph Api batching.

    PSObject will look like this:
        @{
            Method  = "GET"
            URL     = "/deviceManagement/managedDevices/38027eb9-1f3e-49ea-bf91-f7b7f07c3a63"
            Id      = "deviceInfo"
        }

        Method = method that will be used when sending the request
        URL = ARM api URL that should be requested
        Id = ID that has to be unique across the batch requests

    .PARAMETER method
    Request method.

    By default GET.

    .PARAMETER url
    Request URL in relative form like "/deviceManagement/managedDevices/38027eb9-1f3e-49ea-bf91-f7b7f07c3a63" a.k.a. without the "https://graph.microsoft.com/<apiVersion>" prefix (API version is specified when the batch is invoked).

    .PARAMETER urlWithPlaceholder
    Request URL in relative form like "/deviceManagement/managedDevices/<placeholder>" that contains "<placeholder>" string.
    Relative form means without the "https://graph.microsoft.com/<apiVersion>" prefix (API version is specified when the batch is invoked).
    For each value in the 'placeholder' parameter, new request url will be generated with such value used instead of the "<placeholder>" string.

    .PARAMETER placeholder
    Array of items (string, integers, ..) that will be used in the request url (defined in 'urlWithPlaceholder' parameter) instead of the "<placeholder>" string.

    .PARAMETER header
    Header that should be added to each request in the batch.

    .PARAMETER body
    Body that should be added to each request in the batch.

    .PARAMETER id
    Id of the request.
    Can only be specified when only one URL is requested.

    By default random-generated-GUID.

    .EXAMPLE
    $batchRequest = New-GraphBatchRequest -url "/deviceManagement/managedDevices/38027eb9-1f3e-49ea-bf91-f7b7f07c3a63?`$select=id,devicename&`$expand=DetectedApps", "/deviceManagement/managedDevices/aaa932b4-5af4-4120-86b1-ab64b964a56s?`$select=id,devicename&`$expand=DetectedApps"

    Invoke-GraphBatchRequest -batchRequest $batchRequest -graphVersion beta

    Creates batch request object containing both urls & run it ('DetectedApps' property can be retrieved only when requested devices one by one).

    .EXAMPLE
    $deviceId = (Get-MgBetaDeviceManagementManagedDevice -Property id -All).Id

    New-GraphBatchRequest -urlWithPlaceholder "/deviceManagement/managedDevices/<placeholder>?`$select=id,devicename&`$expand=DetectedApps" -placeholder $deviceId | Invoke-GraphBatchRequest -graphVersion beta

    Creates batch request object containing dynamically generated urls for every id in the $deviceId array & run it ('DetectedApps' property can be retrieved only when requested devices one by one).

    .NOTES
    https://learn.microsoft.com/en-us/graph/json-batching
    #>

    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param (
        [string] $method = "GET",

        [Parameter(Mandatory = $true, ParameterSetName = "Url")]
        [string[]] $url,

        [Parameter(Mandatory = $true, ParameterSetName = "DynamicUrl")]
        [ValidateScript( {
                if ($_ -like "*<placeholder>*") {
                    $true
                } else {
                    throw "$_ doesn't contain '<placeholder>' string (that should be replaced by real value from `$placeholder then)"
                }
            })]
        [string] $urlWithPlaceholder,

        [Parameter(Mandatory = $true, ParameterSetName = "DynamicUrl")]
        $placeholder,

        $header,

        $body,

        [string] $id
    )

    if ($id -and @($url).count -gt 1) {
        throw "'id' parameter cannot be used with multiple urls"
    }

    if ($urlWithPlaceholder) {
        $url = $placeholder | % {
            $urlWithPlaceholder -replace "<placeholder>", $_
        }
    }

    $url | % {
        # fix common mistake where there are multiple slashes
        $_ = $_ -replace "(?<!^https:)/{2,}", "/"

        if ($_ -like "http*" -or $_ -like "*/beta/*" -or $_ -like "*/v1.0/*" -or $_ -like "*/graph.microsoft.com/*") {
            throw "url '$_' has to be relative (without the whole 'https://graph.microsoft.com/<apiversion>' part)!"
        }


        $property = [ordered]@{
            method = $method
            URL    = $_
        }

        if ($id) {
            $property.id = $id
        } else {
            $property.id = (New-Guid).Guid
        }

        if ($header) {
            $property.headers = $header
        }

        if ($body) {
            $property.body = $body
        }

        New-Object -TypeName PSObject -Property $property
    }
}