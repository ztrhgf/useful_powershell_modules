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

    When the 'placeholder' parameter is specified, for each value it contains, new request url will be generated with such value used instead of the '<placeholder>' string.

    .PARAMETER placeholder
    Array of items (string, integers, ..) that will be used in the request url ('url' parameter) instead of the "<placeholder>" string.

    .PARAMETER header
    Header that should be added to each request in the batch.

    .PARAMETER body
    Body that should be added to each request in the batch.

    .PARAMETER id
    Id of the request.
    Can only be specified only when 'url' parameter contains one value.
    If url with placeholder is used, suffix "_<randomnumber>" will be added to each generated request id. This way each one is unique and at the same time you are able to filter the request results based on it in case you merge multiple different requests in one final batch.

    By default random-generated-number.

    .EXAMPLE
    $batchRequest = New-GraphBatchRequest -url "/deviceManagement/managedDevices/38027eb9-1f3e-49ea-bf91-f7b7f07c3a63?`$select=id,devicename&`$expand=DetectedApps", "/deviceManagement/managedDevices/aaa932b4-5af4-4120-86b1-ab64b964a56s?`$select=id,devicename&`$expand=DetectedApps"

    Invoke-GraphBatchRequest -batchRequest $batchRequest -graphVersion beta

    Creates batch request object containing both urls & run it ('DetectedApps' property can be retrieved only when requested devices one by one).

    .EXAMPLE
    $deviceId = (Get-MgBetaDeviceManagementManagedDevice -Property id -All).Id

    New-GraphBatchRequest -url "/deviceManagement/managedDevices/<placeholder>?`$select=id,devicename&`$expand=DetectedApps" -placeholder $deviceId | Invoke-GraphBatchRequest -graphVersion beta

    Creates batch request object containing dynamically generated urls for every id in the $deviceId array & run it ('DetectedApps' property can be retrieved only when requested devices one by one).

    .EXAMPLE
    $devices = Get-MgBetaDeviceManagementManagedDevice -Property Id, AzureAdDeviceId, OperatingSystem -All

    $windowsClient = $devices | ? OperatingSystem -EQ 'Windows'
    $macOSClient = $devices | ? OperatingSystem -EQ 'macOS'

    $batchRequest = @(
        # get bitlocker keys for all windows devices
        New-GraphBatchRequest -url "/informationProtection/bitlocker/recoveryKeys?`$filter=deviceId eq '<placeholder>'" -id "bitlocker" -placeholder $windowsClient.AzureAdDeviceId
        # get fileVault keys for all macos devices
        New-GraphBatchRequest -url "/deviceManagement/managedDevices('<placeholder>')/getFileVaultKey" -id "fileVault" -placeholder $macOSClient.Id
    )

    $batchResult = Invoke-GraphBatchRequest -batchRequest $batchRequest -graphVersion beta

    $bitlockerKeyList = $batchResult | ? RequestId -like "bitlocker*"
    $fileVaultKeyList = $batchResult | ? RequestId -like "fileVault*"

    Merging multiple different batch queries together.

    .NOTES
    https://learn.microsoft.com/en-us/graph/json-batching
    #>

    [CmdletBinding()]
    param (
        [string] $method = "GET",

        [Parameter(Mandatory = $true)]
        [Alias("urlWithPlaceholder")]
        [string[]] $url,

        $placeholder,

        $header,

        $body,

        [string] $id
    )

    #region validity checks
    if ($id -and @($url).count -gt 1) {
        throw "'id' parameter cannot be used with multiple urls"
    }

    if ($placeholder -and $url -notlike "*<placeholder>*") {
        throw "You have specified 'placeholder' parameter, but 'url' parameter doesn't contain string '<placeholder>' for replace."
    }

    if (!$placeholder -and $url -like "*<placeholder>*") {
        throw "You have specified 'url' with '<placeholder>' in it, but not the 'placeholder' parameter itself."
    }
    #endregion validity checks

    if ($placeholder) {
        $url = $placeholder | % {
            $p = $_

            $url | % {
                $_ -replace "<placeholder>", $p
            }
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
            if ($placeholder -and $placeholder.count -gt 1) {
                $property.id = ($id + "_" + (Get-Random))
            } else {
                $property.id = $id
            }
        } else {
            $property.id = Get-Random
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