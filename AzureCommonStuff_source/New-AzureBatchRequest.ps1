function New-AzureBatchRequest {
    <#
    .SYNOPSIS
    Function creates PSObject(s) representing request(s) that can be used in Azure Resource Manager Api batching.

    .DESCRIPTION
    Function creates PSObject(s) representing request(s) that can be used in Azure Resource Manager Api batching.

    PSObject will look like this:
        @{
            Name       = "mggroupperm"
            HttpMethod = "GET"
            URL        = "https://management.azure.com/providers/Microsoft.Management/managementGroups/SOMEMGGROUP/providers/microsoft.authorization/permissions?api-version=2018-01-01-preview"
        }

        Name = de-facto ID that has to be unique across the batch requests
        HttpMethod = method that will be used when sending the request
        URL = ARM api URL that should be requested

    .PARAMETER method
    Request method.

    By default GET.

    .PARAMETER url
    Request URL in absolute (https://management.azure.com/providers/Microsoft.Management/managementGroups/SOMEMGGROUP/providers/microsoft.authorization/permissions?api-version=2018-01-01-preview) or relative form (/providers/Microsoft.Management/managementGroups/SOMEMGGROUP/providers/microsoft.authorization/permissions?api-version=2018-01-01-preview) a.k.a. without the "https://management.azure.com" prefix.

    .PARAMETER urlWithPlaceholder
    Request URL in absolute (https://management.azure.com/providers/Microsoft.Management/managementGroups/<placeholder>/providers/microsoft.authorization/permissions?api-version=2018-01-01-preview) or relative form (/providers/Microsoft.Management/managementGroups/<placeholder>/providers/microsoft.authorization/permissions?api-version=2018-01-01-preview) that contains "<placeholder>" string.
    Relative form means without the "https://management.azure.com" prefix.
    For each value in the 'placeholder' parameter, new request url will be generated with such value used instead of the "<placeholder>" string.

    .PARAMETER placeholder
    Array of items (string, integers, ..) that will be used in the request url (defined in 'urlWithPlaceholder' parameter) instead of the "<placeholder>" string.

    .PARAMETER requestHeaderDetails
    RequestHeaderDetails (header) as a hashtable that should be added to each request in the batch.

    "requestHeaderDetails" = @{
        "commandName" = "fx.Microsoft_Azure_AD.ServicesPermissions.getPermissions"
    }

    .PARAMETER name
    Name (Id) of the request.
    Can only be specified when only one URL is requested.

    By default random-generated-GUID.

    .EXAMPLE
    $batchRequest = New-AzureBatchRequest -url "/providers/Microsoft.Authorization/roleDefinitions?%24filter=type%20eq%20%27BuiltInRole%27&api-version=2022-05-01-preview", "/subscriptions/f3b08c7f-99a9-4a70-ba56-1e877abb77f7/providers/Microsoft.Authorization/roleEligibilitySchedules?api-version=2020-10-01"

    Invoke-AzureBatchRequest -batchRequest $batchRequest

    Creates batch request object containing both urls & run it.

    .EXAMPLE
    $subscriptionId = (Get-AzSubscription | ? State -EQ 'Enabled').Id

    New-AzureBatchRequest -urlWithPlaceholder "https://management.azure.com/subscriptions/<placeholder>/providers/Microsoft.Authorization/roleEligibilitySchedules?api-version=2020-10-01" -placeholder $subscriptionId | Invoke-AzureBatchRequest

    Creates batch request object containing dynamically generated urls for every id in the $subscriptionId array & run it.

    .EXAMPLE
    $subscriptionId = (Get-AzSubscription | ? State -EQ 'Enabled').Id

    $batchRequest = New-AzureBatchRequest -urlWithPlaceholder "https://management.azure.com/subscriptions/<placeholder>/providers/Microsoft.Authorization/roleEligibilitySchedules?api-version=2020-10-01" -placeholder $subscriptionId

    # you need to process all requests by chunks of 20 items
    $payload = @{
        requests = $batchRequest[0..19]
    }

    Invoke-AzRestMethod -Uri "https://management.azure.com/batch?api-version=2020-06-01" -Method POST -Payload ($payload | ConvertTo-Json -Depth 20)

    .NOTES
    Uses undocumented API https://github.com/Azure/azure-sdk-for-python/issues/9271 :).
    #>

    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param (
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE', 'HEAD', 'PATCH')]
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

        [hashtable] $requestHeaderDetails,

        [Alias("id")]
        [string] $name
    )

    if ($name -and @($url).count -gt 1) {
        throw "'name' parameter cannot be used with multiple urls"
    }

    if ($urlWithPlaceholder) {
        $url = $placeholder | % {
            $urlWithPlaceholder -replace "<placeholder>", $_
        }
    }

    $url | % {
        # fix common mistake where there are multiple slashes
        $_ = $_ -replace "/{1,}", "/"

        #region url validity checks
        if ($_ -notlike "https://management.azure.com/*" -and $_ -notlike "/*") {
            throw "url '$_' has to be in the relative (without the 'https://management.azure.com' prefix and starting with the '/') or absolute form!"
        }

        if ($_ -notlike "*/subscriptions/*" -and $_ -notlike "*/providers/Microsoft.Management/managementGroups/*" -and $_ -notlike "*/providers/Microsoft.ResourceGraph/*" -and $_ -notlike "*/resources/*" -and $_ -notlike "*/locations/*" -and $_ -notlike "*/tenants/*" -and $_ -notlike "*/bulkdelete/*") {
            throw "url '$_' is not valid. Is should starts with:`n'/subscriptions/{subscriptionId}'`n'/providers/Microsoft.Management/managementGroups/{entityId}'`n'/providers/Microsoft.ResourceGraph/{action}'`n'/resources, /locations, /tenants, /bulkdelete'!"
        }
        #endregion url validity checks

        $property = [ordered]@{
            HttpMethod = $method
            URL        = $_
        }

        if ($name) {
            $property.Name = $name
        } else {
            $property.Name = (New-Guid).Guid
        }

        if ($requestHeaderDetails) {
            $property.requestHeaderDetails = $requestHeaderDetails
        }

        New-Object -TypeName PSObject -Property $property
    }
}