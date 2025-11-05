function Connect-AzAccount2 {
    <#
    .SYNOPSIS
    Function for connecting to Azure using Connect-AzAccount command (Az.Accounts module).

    .DESCRIPTION
    Function for connecting to Azure using Connect-AzAccount command (Az.Accounts module).
    In case there is already existing valid connection, no new will be created.

    .PARAMETER credential
    Credentials (User or App) for connecting to Azure.
    For App credentials tenantId must be set too!

    .PARAMETER applicationId
    ID of the service principal that will be used for connection.

    .PARAMETER certificateThumbprint
    Thumbprint of the locally stored certificate that will be used for connection.
    Certificate has to be placed in personal machine store and user running this function has to have permission to read its private key.

    .PARAMETER servicePrincipal
    Switch for using App/Service Principal authentication instead of User auth.

    .PARAMETER tenantId
    Azure tenant ID.
    Mandatory when App authentication is used.

    .EXAMPLE
    Connect-AzAccount2

    Authenticate to Azure interactively using user credentials. Doesn't work for accounts with MFA!

    .EXAMPLE
    $credential = get-credential
    Connect-AzAccount2 -credential $credential

    Authenticate to Azure using given user credentials. Doesn't work for accounts with MFA!

    .EXAMPLE
    $credential = get-credential
    Connect-AzAccount2 -servicePrincipal -credential $credential -tenantId 1234-1234-1234

    Authenticate to Azure using given app credentials (service principal).

    .EXAMPLE
    $thumbprint = Get-ChildItem Cert:\LocalMachine\My | ? subject -EQ "CN=contoso.onmicrosoft.com" | select -ExpandProperty Thumbprint
    $null = Connect-AzAccount2 -ApplicationId 'cd2ae428-35f9-41b4-a527-71f2f8f1e5cf' -CertificateThumbprint $thumbprint -ServicePrincipal

    Authenticate using certificate.

    .NOTES
    Requires module Az.Accounts.
    #>

    [CmdletBinding()]
    param (
        [System.Management.Automation.PSCredential] $credential,

        [string] $applicationId,

        [string] $certificateThumbprint,

        [switch] $servicePrincipal,

        [string] $tenantId = $_tenantId
    )

    #region checks
    $azAccesstoken = Get-AzAccessToken -ErrorAction SilentlyContinue

    #region check whether there is valid existing session
    $tenantIsDomainName = $false
    $correctTenant = $false

    if ($azAccesstoken -and $azAccesstoken.ExpiresOn -gt [datetime]::now) {
        if ($tenantId -like "*.*") {
            $tenantIsDomainName = $true
        }
        if (($tenantIsDomainName -and $azAccesstoken.UserId -like "*@$tenantId") -or (!$tenantIsDomainName -and $azAccesstoken.TenantId -eq $tenantId)) {
            $correctTenant = $true
        }
    }
    #endregion check whether there is valid existing session

    #region check whether there is valid existing session created via required account
    $userId = $null
    $correctAccount = $false

    if ($azAccesstoken -and ($applicationId -or $credential) -and ($azAccesstoken.UserId -eq $applicationId -or $azAccesstoken.UserId -eq $credential.UserName)) {
        # there is an existing token that uses required account already
        $correctAccount = $true
    }
    if ($azAccesstoken -and !$applicationId -and !$credential) {
        # there is an existing token that can be used, because no explicit credentials were specified
        $correctAccount = $true
    }
    #endregion check whether there is valid existing session created via required account
    #endregion checks

    if ($azAccesstoken -and $correctTenant -and $correctAccount) {
        Write-Verbose "Already connected to the Azure using $($azAccesstoken.UserId)"
        return
    } else {
        if ($servicePrincipal -and !$tenantId) {
            throw "When servicePrincipal auth is used tenantId has to be set"
        }

        $param = @{}
        if ($servicePrincipal) { $param.servicePrincipal = $true }
        if ($tenantId) { $param.tenantId = $tenantId }
        if ($credential) { $param.credential = $credential }
        if ($applicationId) { $param.applicationId = $applicationId }
        if ($certificateThumbprint) { $param.certificateThumbprint = $certificateThumbprint }

        Connect-AzAccount @param
    }
}

function Connect-PnPOnline2 {
    <#
    .SYNOPSIS
    Proxy function for Connect-PnPOnline with some enhancements like: automatic MFA auth if MFA detected, skipping authentication if already authenticated etc.

    .DESCRIPTION
    Proxy function for Connect-PnPOnline with some enhancements like: automatic MFA auth if MFA detected, skipping authentication if already authenticated etc.

    .PARAMETER credential
    Credential object you want to use to authenticate to Sharepoint Online

    .PARAMETER appAuth
    Switch for using application authentication instead of the user one.

    .PARAMETER asMFAUser
    Switch for using user with MFA enabled authentication (i.e. interactive auth)

    .PARAMETER useWebLogin
    Switch for using WebLogin instead of Interactive authentication.

    - weblogin auth
        Legacy cookie based authentication. Notice this type of authentication is limited in its functionality. We will for instance not be able to acquire an access token for the Graph, and as a result none of the Graph related cmdlets will work. Also some of the functionality of the provisioning engine (Get-PnPSiteTemplate, Get-PnPTenantTemplate, Invoke-PnPSiteTemplate, Invoke-PnPTenantTemplate) will not work because of this reason. The cookies will in general expire within a few days and if you use -UseWebLogin within that time popup window will appear that will disappear immediately, this is expected. Use -ForceAuthentication to reset the authentication cookies and force a new login.

    - interactive auth
        Connects to the Azure AD, acquires an access token and allows PnP PowerShell to access both SharePoint and the Microsoft Graph. By default it will use the PnP Management Shell multi-tenant application behind the scenes, so make sure to run `Register-PnPManagementShellAccess` first.

    .PARAMETER url
    Your sharepoint online url ("https://contoso-admin.sharepoint.com")

    .EXAMPLE
    Connect-PnPOnline2

    Connect to Sharepoint Online using user interactive authentication.

    .EXAMPLE
    Connect-PnPOnline2 -asMFAUser

    Connect to Sharepoint Online using (MFA-enabled) user interactive authentication.

    .EXAMPLE
    Connect-PnPOnline2 -appAuth

    Connect to Sharepoint Online using application interactive authentication.

    .EXAMPLE
    Connect-PnPOnline2 -appAuth -credential $cred

    Connect to Sharepoint Online using application non-interactive authentication.

    .EXAMPLE
    Connect-PnPOnline2 -credential $cred

    Connect to Sharepoint Online using (non-MFA enabled!) user non-interactive authentication.

    .NOTES
    Requires Pnp.PowerShell module.
    #>

    [CmdletBinding()]
    param (
        [System.Management.Automation.PSCredential] $credential,

        [switch] $appAuth,

        [switch] $asMFAUser,

        [switch] $useWebLogin,

        [ValidateNotNullOrEmpty()]
        [string] $url = $_SPOConnectionUri
    )

    if (!$url) {
        throw "Parameter 'url' cannot be empty."
    }

    if ($appAuth -and $asMFAUser) {
        Write-Warning "asMFAUser switch cannot be used with appAuth. Ignoring asMFAUser."
        $asMFAUser = $false
    }

    if ($credential -and $asMFAUser) {
        Write-Warning "When logging using MFA-enabled user, credentials cannot be passed i.e. it has to be interactive login"
        $credential = $null
    }

    if (!(Get-Module Pnp.PowerShell) -and !(Get-Module Pnp.PowerShell -ListAvailable)) {
        throw "Module Pnp.PowerShell is missing. Function $($MyInvocation.MyCommand) cannot continue"
    }

    try {
        $existingConnection = Get-PnPConnection -ea Stop
    } catch {
        Write-Verbose "There isn't any PNP connection"
    }

    if (!$existingConnection -or !($existingConnection | ? { $_.URL -like "$url*" }) -or ($useWebLogin -and $existingConnection.ConnectionType -ne "O365") -or (!$useWebLogin -and $existingConnection.ConnectionType -ne "TenantAdmin")) {
        Write-Verbose "Connecting to Sharepoint"
        if ($credential -and !$appAuth) {
            try {
                Connect-PnPOnline -Url $url -Credentials $credential -ea Stop
            } catch {
                if ($_ -match "you must use multi-factor authentication to access") {
                    Write-Error "Account $($credential.UserName) has MFA enabled, therefore interactive logon is needed"
                    Connect-PnPOnline -Url $url -Interactive -ForceAuthentication
                } else {
                    throw $_
                }
            }
        } elseif ($credential -and $appAuth) {
            Connect-PnPOnline -Url $url -ClientId $credential.UserName -ClientSecret $credential.GetNetworkCredential().password
        } else {
            # credential is missing
            if ($asMFAUser) {
                if ($useWebLogin) {
                    # weblogin acquires ACS generated token, which will not work for things like exporting the site header and footer as it won't be able to acquire an access token for Graph
                    Connect-PnPOnline -Url $url -UseWebLogin -ForceAuthentication
                } else {
                    # interactive uses PnP Management Shell Azure app registration to connect as delegated permissions
                    Connect-PnPOnline -Url $url -Interactive -ForceAuthentication
                }
            } elseif ($appAuth) {
                $credential = Get-Credential -Message "Using App auth. Enter ClientId and ClientSecret."
                Connect-PnPOnline -Url $url -ClientId $credential.UserName -ClientSecret $credential.GetNetworkCredential().password
            } else {
                Connect-PnPOnline -Url $url
            }
        }
    } else {
        Write-Verbose "Already connected to Sharepoint"
    }
}

function FilterBy-AzureScope {
    <#
    .SYNOPSIS
    Function for filtering of Azure resources based on their scope (typically saved in ResourceId).

    .DESCRIPTION
    Function for filtering of Azure resources based on their scope (typically saved in ResourceId).

    .PARAMETER pipelineInput
    Azure object(s).

    .PARAMETER scope
    Scope(s) that will be used to filter.

    .PARAMETER property
    Name of the Azure object property that contains its scope (typically ResourceId)

    .EXAMPLE
    $scope = "subscriptions/b6e5e819-g33c-4ecf-b021-5fbd3ff2fead/resourceGroups/local-azure-test", "/subscriptions/1a17a321-7c64-3050-8cc5-42329bdac82b/resourceGroups/AHCI-TEST"

    Search-AzGraph -Query $Query | FilterBy-AzureScope -scope $scope -Property ResourceId
    #>

    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline = $true)]
        $pipelineInput,

        [string[]] $scope,

        [Parameter(Mandatory = $true)]
        [string] $property
    )

    begin {
        # standardize the scope format
        $scope = $scope | ? { $_ } | % {
            $_.trim() -replace "\**$" -replace "/*$" -replace "^/*"
        }
    }

    process {
        foreach ($object in $pipelineInput) {
            $object | ? {
                if (!$scope) {
                    return $true
                } else {
                    foreach ($scp in $scope) {
                        $scp = "/" + $scp + "/*"

                        Write-Verbose "Comparing '$($_.$property)' against '$scp'"

                        if ($_.$property -like $scp) {
                            return $true
                        }
                    }

                    return $false
                }
            }
        }
    }
}

function Get-AuthenticatedSPIdentityAppId {
    <#
    .SYNOPSIS
    Function returns application ID of the app used for authenticating against an Azure.

    .DESCRIPTION
    Function returns application ID of the app used for authenticating against an Azure.

    .EXAMPLE
    Get-AuthenticatedSPIdentityAppId

    Function returns application ID of the app used for authenticating against an Azure.
    #>

    [CmdletBinding()]
    param ()

    function ConvertFrom-JWTToken {
        [cmdletbinding()]
        param([Parameter(Mandatory = $true)][string]$token)

        if ($token -match "^bearer ") {
            # get rid of "bearer " part
            $token = $token -replace "^bearer\s+"
        }

        #Validate as per https://tools.ietf.org/html/rfc7519
        #Access and ID tokens are fine, Refresh tokens will not work
        if (!$token.Contains(".") -or !$token.StartsWith("eyJ")) { Write-Error "Invalid token" -ErrorAction Stop }

        #Payload
        $tokenPayload = $token.Split(".")[1].Replace('-', '+').Replace('_', '/')
        #Fix padding as needed, keep adding "=" until string length modulus 4 reaches 0
        while ($tokenPayload.Length % 4) { Write-Verbose "Invalid length for a Base-64 char array or string, adding ="; $tokenPayload += "=" }
        #Convert to Byte array
        $tokenByteArray = [System.Convert]::FromBase64String($tokenPayload)
        #Convert to string array
        $tokenArray = [System.Text.Encoding]::ASCII.GetString($tokenByteArray)
        Write-Verbose "Decoded array in JSON format:"
        Write-Verbose $tokenArray
        #Convert from JSON to PSObject
        $tokobj = $tokenArray | ConvertFrom-Json
        Write-Verbose "Decoded Payload:"

        return $tokobj
    }

    $token = (Get-AzAccessToken -WarningAction SilentlyContinue).token
    $objectId = (ConvertFrom-JWTToken $token).oid

    Write-Verbose "Get AppId of app with $objectId ObjectId"

    (Get-AzADServicePrincipal -ObjectId $objectId -Select appid).AppId
}

function Get-AzureDirectoryObject {
    <#
    .SYNOPSIS
    Alternative for Get-MgDirectoryObjectById if you want to avoid Microsoft.Graph.DirectoryObjects module dependency.

    .DESCRIPTION
    Alternative for Get-MgDirectoryObjectById if you want to avoid Microsoft.Graph.DirectoryObjects module dependency.

    .PARAMETER id
    ID(s) of the Azure object(s).

    .EXAMPLE
    Get-AzureDirectoryObject -Id 'a5834928-0f19-292d-4a69-3fbc98fd84ef'
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Alias("ids")]
        [string[]] $id
    )

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-MgGraph."
    }

    # directoryObjects/microsoft.graph.getByIds can process only 1000 ids per request
    $chunkSize = 1000

    # calculate the total number of chunks
    $totalChunks = [Math]::Ceiling($id.Count / $chunkSize)

    # process each chunk
    for ($i = 0; $i -lt $totalChunks; $i++) {
        # calculate the start index of the current chunk
        $startIndex = $i * $chunkSize

        # extract the current chunk
        $currentChunk = $id[$startIndex..($startIndex + $chunkSize - 1)]

        # process the current chunk
        Write-Verbose "Processing chunk $($i + 1) with items: $($currentChunk -join ', ')"

        $body = @{
            "ids" = @($currentChunk)
        }

        Invoke-MgGraphRequest -Uri "v1.0/directoryObjects/microsoft.graph.getByIds" -Body ($body | ConvertTo-Json) -Method POST | Get-MgGraphAllPages | select *, @{Name = 'ObjectType'; Expression = { $_.'@odata.type' -replace "#microsoft.graph." } } -ExcludeProperty '@odata.type'
    }
}

function Get-AzureDirectoryObjectMemberOf {
    <#
    .SYNOPSIS
    Get permanent membership of given Azure account transitively.

    .DESCRIPTION
    Get permanent membership of given Azure account transitively.

    .PARAMETER id
    Id(s) of the Azure accounts you want membership for.

    .PARAMETER securityEnabledOnly
    Switch to return only security enabled groups.

    .EXAMPLE
    Get-AzureDirectoryObjectMemberOf -id 90daa3a7-7fed-4fa7-b979-db74bcd7cbd1

    Get membership of given Azure account.

    .NOTES
    https://learn.microsoft.com/en-us/graph/api/directoryobject-getmembergroups?view=graph-rest-1.0&tabs=http
    #>

    [CmdletBinding()]
    [Alias("Get-AzureAccountMemberOf", "Get-AzureAccountPermanentMemberOf")]
    param (
        [Parameter(Mandatory = $true)]
        [guid[]] $id,

        [switch] $securityEnabledOnly
    )

    $body = @{
        securityEnabledOnly = $securityEnabledOnly.ToBool()
    }

    $header = @{'Content-Type' = "application/json" }

    New-GraphBatchRequest -url "/directoryObjects/<placeholder>/getMemberGroups" -body $body -header $header -method POST -placeholder $id -placeholderAsId | Invoke-GraphBatchRequest -graphVersion beta | % {
        [PSCustomObject]@{
            Id       = $_.RequestId
            MemberOf = (Get-AzureDirectoryObject -id $_.Value)
        }
    }
}

function Invoke-AzureBatchRequest {
    <#
    .SYNOPSIS
    Function to invoke Azure Resource Manager Api batch request(s).

    .DESCRIPTION
    Function to invoke Azure Resource Manager Api batch request(s).

    Handles throttling and server-side errors.

    .PARAMETER batchRequest
    PSobject(s) representing the requests to be run in a batch.

    Can be created manually or via New-AzureBatchRequest.

    https://github.com/Azure/azure-sdk-for-python/issues/9271

    .PARAMETER dontBeautifyResult
    Switch for returning original/non-modified batch request(s) results.

    By default batch-request-related properties like batch status, headers, nextlink, etc are stripped.

    To be able to filter returned objects by their originated request, new property 'RequestName' is added.

    .PARAMETER dontAddRequestName
    Switch to avoid adding extra 'RequestName' property to the "beautified" results.

    .PARAMETER separateErrors
    Switch to return batch request errors one by one instead of all at once.
    Moreover returned errors will contain 'TargetObject' property with original request and response objects for easier troubleshooting.

    .EXAMPLE
    $batch = (
        @{
            Name       = "group"
            HttpMethod = "GET"
            URL        = "https://management.azure.com/providers/Microsoft.Management/managementGroups/SOMEMGGROUP/providers/microsoft.authorization/permissions?api-version=2018-01-01-preview"
        },

        @{
            Name       = "subPim"
            HttpMethod = "GET"
            URL        = "/subscriptions/f3b08c7f-99a9-4a70-ba56-1e877abb77f7/providers/Microsoft.Authorization/roleEligibilitySchedules?api-version=2020-10-01"
        }
    )

    Invoke-AzureBatchRequest -batchRequest $batch

    Invokes both requests in one batch.

    .EXAMPLE
    $batchRequest = New-AzureBatchRequest -url "/providers/Microsoft.Authorization/roleDefinitions?%24filter=type%20eq%20%27BuiltInRole%27&api-version=2022-05-01-preview", "/subscriptions/f3b08c7f-99a9-4a70-ba56-1e877abb77f7/providers/Microsoft.Authorization/roleEligibilitySchedules?api-version=2020-10-01"

    Invoke-AzureBatchRequest -batchRequest $batchRequest

    Creates batch request object containing both urls & run it.

    .EXAMPLE
    $subscriptionId = (Get-AzSubscription | ? State -EQ 'Enabled').Id

    New-AzureBatchRequest -url "https://management.azure.com/subscriptions/<placeholder>/providers/Microsoft.Authorization/roleEligibilitySchedules?api-version=2020-10-01" -placeholder $subscriptionId | Invoke-AzureBatchRequest

    Creates batch request object containing dynamically generated urls for every id in the $subscriptionId array & run it.

    .EXAMPLE
    $subscriptionId = (Get-AzSubscription | ? State -EQ 'Enabled').Id

    New-AzureBatchRequest -url "https://management.azure.com/subscriptions/<placeholder>/providers/Microsoft.Authorization/roleEligibilitySchedules?api-version=2020-10-01" -placeholder $subscriptionId | Invoke-AzureBatchRequest -separateErrors -ErrorAction SilentlyContinue -ErrorVariable requestErrors

    $requestErrors | % {
        if ($_.Exception.Source -eq "BatchRequest") {
            # batch request errors

            if ($_.TargetObject.response.status -in 404) {
                Write-Verbose "Ignoring request with id '$($_.TargetObject.request.id)' ($($_.TargetObject.request.url)) as it returned status code $($_.TargetObject.response.status)"
            } else {
                throw $_
            }
        } else {
            # other non-batch-related errors

            throw $_
        }
    }

    Creates batch request object containing dynamically generated urls for every id in the $subscriptionId array & run it & process errors.

    .EXAMPLE
    [System.Collections.Generic.List[object]] $batchRequest = @()
    $queryUrl = "https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2021-03-01"

    $diskQuery = @"
ExtensibilityResources
    | where type =~ "microsoft.azurestackhci/virtualmachineinstances"
"@
    $batchRequest.add((New-AzureBatchRequest -method POST -url $queryUrl -content @{ query = $diskQuery } -name "diskInfo" ))

    $nicQuery = @"
resources
| where type =~ "Microsoft.AzureStackHCI/networkinterfaces" and
    properties.provisioningState =~ "succeeded"
"@

    $batchRequest.add((New-AzureBatchRequest -method POST -url $queryUrl -content @{ query = $nicQuery } -name "nicInfo"))

    $batchResult = Invoke-AzureBatchRequest -batchRequest $batchRequest

    $vmListDiskInfo = $batchResult | ? RequestName -EQ "diskInfo"
    $vmListNicInfo = $batchResult | ? RequestName -EQ "nicInfo"

    Invoking two KQL queries in a batch to get Azure Stack HCI VM disk and NIC information.

    .NOTES
    Uses undocumented API https://github.com/Azure/azure-sdk-for-python/issues/9271 :).
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject[]]$batchRequest,

        [switch] $dontBeautifyResult,

        [Alias("dontAddRequestId")]
        [switch] $dontAddRequestName,

        [switch] $separateErrors
    )

    begin {
        #region helper functions
        function ConvertTo-FlatArray {
            # flattens input in case, that primitive(s) and array(s) are entered at the same time
            [CmdletBinding()]
            param (
                [Parameter(Mandatory = $true)]
                $inputArray
            )

            foreach ($item in $inputArray) {
                if ($null -ne $item) {
                    # recurse for arrays
                    if ($item.GetType().BaseType -eq [System.Array]) {
                        ConvertTo-FlatArray $item
                    } else {
                        # output non-arrays
                        $item
                    }
                }
            }
        }

        function _processChunk {
            <#
                .SYNOPSIS
                Helper function with the main chunk-processing logic that invokes batch request.

                Based on request return code and availability of nextlink url it:
                 - creates another request to get missing data
                 - retry the request (with wait time in case of throttled request)
            #>

            [CmdletBinding()]
            param (
                [Parameter(Mandatory = $true)]
                [System.Collections.Generic.List[Object]] $requestChunk
            )

            $duplicityId = $requestChunk | Select-Object -ExpandProperty Name | Group-Object | Where-Object { $_.Count -gt 1 }
            if ($duplicityId) {
                throw "Batch requests must have unique names. Name $(($duplicityId | Select-Object -Unique) -join ', ') is there more than once"
            }

            Write-Debug ($requestChunk | ConvertTo-Json)

            Write-Verbose "Processing batch of $($requestChunk.count) request(s):`n$(($requestChunk | Sort-Object Url | ForEach-Object {" - $($_.Name) - $($_.Url)"} ) -join "`n")"

            #region process given chunk of batch requests
            $start = Get-Date

            $payload = @{
                requests = [array]$requestChunk
            }

            # invoke the batch
            $result = Invoke-AzRestMethod -Uri "https://management.azure.com/batch?api-version=2020-06-01" -Method POST -Payload ($payload | ConvertTo-Json -Depth 20) -ErrorAction Stop

            $responses = ($result.content | ConvertFrom-Json).responses

            #region return the output
            if ($dontBeautifyResult) {
                # return original response

                $responses
            } else {
                # return just actually requested data without batch-related properties and enhance the returned object with 'RequestName' property for easier filtering

                foreach ($response in $responses) {
                    $noteProperty = $null
                    if ($response.content) { $noteProperty = $response.content | Get-Member -MemberType NoteProperty }

                    # there was some error, no real values were returned, skipping
                    if ($response.httpStatusCode -in (400..509)) {
                        continue
                    }

                    # properties to return
                    $property = @("*")
                    if (!$dontAddRequestName) {
                        $property += @{n = 'RequestName'; e = { $response.Name } }
                    }

                    if ($response.content.value) {
                        # the result is in the 'value' property
                        $response.content.value | Select-Object -Property $property
                    } elseif ($response.content -and $noteProperty.Name -contains 'value') {
                        # the result is stored in 'value' property, but no results were returned, skipping
                    } elseif ($response.content -and $response.contentLength) {
                        # the result is in the 'content' property itself
                        if ($response.content.data -and $response.content.totalRecords -and $response.content.resultTruncated) {
                            # the result is in the 'data' property (Resource Graph KQL response)
                            $response.content.data | Select-Object -Property $property
                        } else {
                            $response.content | Select-Object -Property $property
                        }
                    } else {
                        # no results were returned, skipping
                    }
                }
            }
            #endregion return the output

            #region handle the responses based on their status code
            # load the next pages, retry throttled requests, repeat failed requests, ...

            $failedBatchJob = [System.Collections.Generic.List[Object]]::new()

            foreach ($response in $responses) {
                if ($response.httpStatusCode -in 200, 201, 204) {
                    # success

                    # not sure where the nextLink might be stored, so checking both 'body' and 'content'
                    $nextLink = $null
                    if ($response.body.nextLink) {
                        $nextLink = $response.body.nextLink
                    } elseif ($response.content.nextLink) {
                        $nextLink = $response.content.nextLink
                    }

                    if ($nextLink) {
                        # paginated (get remaining results by query returned NextLink URL)

                        Write-Verbose "Batch result for request '$($response.Name)' is paginated. Nextlink will be processed in the next batch"

                        # make a request object copy, so I can modify it without interfering with the original object
                        $nextLinkRequest = $requestChunk | Where-Object Name -EQ $response.Name | ConvertTo-Json -Depth 10 | ConvertFrom-Json
                        # replace original URL with the nextLink
                        $nextLinkRequest.Url = $nextLink
                        # add the request for later processing
                        $extraRequestChunk.Add($nextLinkRequest)
                    }

                    $skipToken = $null
                    if ($skipToken = $response.content.'$skipToken') {
                        # paginated (get remaining results by using '$skipToken')

                        Write-Verbose "Batch result for request '$($response.Name)' is paginated (total records: $($response.content.totalRecords)). Request will be repeated with the returned `$skipToken"

                        # make a request object copy, so I can modify it without interfering with the original object
                        $nextPageRequest = $requestChunk | Where-Object Name -EQ $response.Name | ConvertTo-Json -Depth 10 | ConvertFrom-Json
                        # set '$skipToken' option
                        if ($nextPageRequest.content.Options) {
                            if ($nextPageRequest.content.Options.'$skipToken') {
                                $nextPageRequest.content.Options.'$skipToken' = $skipToken
                            } else {
                                $nextPageRequest.content.Options | Add-Member -MemberType NoteProperty -Name '$skipToken' -Value $skipToken
                            }
                        } else {
                            $nextPageRequest.content | Add-Member -MemberType NoteProperty -Name Options -Value @{'$skipToken' = $skipToken }
                        }
                        # add the request for later processing
                        $extraRequestChunk.Add($nextPageRequest)
                    }
                } elseif ($response.httpStatusCode -eq 429) {
                    # throttled (will be repeated after given time)

                    $jobRetryAfter = $response.Headers.'Retry-After'
                    $throttledBatchRequest = $requestChunk | Where-Object Name -EQ $response.Name

                    Write-Verbose "Batch request with Id: '$($throttledBatchRequest.Name)', Url:'$($throttledBatchRequest.Url)' was throttled, hence will be repeated after $jobRetryAfter seconds"

                    if ($jobRetryAfter -eq 0) {
                        # request can be repeated without any delay
                        #TIP for performance reasons adding to $extraRequestChunk batch (to avoid invocation of unnecessary batch job)
                        $extraRequestChunk.Add($throttledBatchRequest)
                    } else {
                        # request can be repeated after delay
                        # add the request for later processing
                        $throttledRequestChunk.Add($throttledBatchRequest)
                    }

                    # get highest retry-after wait time
                    if ($jobRetryAfter -gt $script:retryAfter) {
                        Write-Verbose "Setting $jobRetryAfter retry-after time"
                        $script:retryAfter = $jobRetryAfter
                    }
                } elseif ($response.httpStatusCode -in 500, 502, 503, 504) {
                    # some internal error on remote side (will be repeated)

                    $problematicBatchRequest = $requestChunk | Where-Object Name -EQ $response.Name

                    Write-Verbose "Batch request with Id: '$($problematicBatchRequest.Name)', Url:'$($problematicBatchRequest.Url)' had internal error '$($response.httpStatusCode)', hence will be repeated"

                    $extraRequestChunk.Add($problematicBatchRequest)
                } else {
                    # failed

                    $failedBatchRequest = $requestChunk | Where-Object Name -EQ $response.Name

                    $failedBatchJob.Add(
                        @{
                            Name       = $response.Name
                            Url        = $failedBatchRequest.Url
                            StatusCode = $response.httpStatusCode
                            Error      = $response.content.error.message
                            Object     = [ordered]@{
                                request  = $failedBatchRequest
                                response = $response
                            }
                        }
                    )
                }
            }

            # exit if critical failure occurred
            if ($failedBatchJob) {
                if ($separateErrors) {
                    # output errors one by one, so you can handle them separately if needed
                    $failedBatchJob | ForEach-Object {
                        #TIP only the first one will be returned if $ErrorActionPreference is set to stop!
                        $errorMsg = "`nFailed batch request:`n$(" - Name: '$($_.Name)'", " - Url: '$($_.Url)'", " - StatusCode: '$($_.StatusCode)'", " - Error: '$($_.Error)'`n`n" -join "`n")"
                        $exception = New-Object System.InvalidOperationException $errorMsg
                        $exception.Source = "BatchRequest"

                        Write-Error -ErrorRecord (New-Object System.Management.Automation.ErrorRecord($exception, $null, "InvalidOperation", $_.Object))
                    }
                } else {
                    #TIP all errors at once, because batch can contain non-related requests and if errorAction is set to stop, only the first error would be returned, which can be confusing
                    $errorMsg = "`nFollowing batch request(s) failed:`n`n$(($failedBatchJob | ForEach-Object {
                        " - Name: '$($_.Name)'", " - Url: '$($_.Url)'", " - StatusCode: '$($_.StatusCode)'", " - Error: '$($_.Error)'" -join "`n"
                    }) -join "`n`n")"
                    $exception = New-Object System.InvalidOperationException $errorMsg
                    $exception.Source = "BatchRequest"

                    Write-Error -ErrorRecord (New-Object System.Management.Automation.ErrorRecord($exception, $null, "InvalidOperation", $failedBatchJob.Object))
                }
            }
            #endregion handle the responses based on their status code

            $end = Get-Date

            Write-Verbose "It took $((New-TimeSpan -Start $start -End $end).TotalSeconds) seconds to process the batch"
            #endregion process given chunk of batch requests
        }
        #endregion helper functions

        # flatten the batch request array
        if ($batchRequest | Where-Object { $_ -and $_.GetType().BaseType -eq [System.Array] }) {
            $batchRequest = ConvertTo-FlatArray -inputArray $batchRequest
        }

        if ($PSCmdlet.MyInvocation.PipelineLength -eq 1) {
            Write-Verbose "Total number of requests to process is $($batchRequest.count)"
        }

        if ($dontBeautifyResult -and $dontAddRequestName) {
            Write-Verbose "'dontAddRequestName' parameter will be ignored, 'RequestName' property is not being added when 'dontBeautifyResult' parameter is used"
        }

        # api batch requests are limited to 20 requests
        $chunkSize = 20
        # buffer to hold chunks of requests
        $requestChunk = [System.Collections.Generic.List[Object]]::new()
        # paginated or remotely failed requests that should be processed too, to get all the results
        $extraRequestChunk = [System.Collections.Generic.List[Object]]::new()
        # throttled requests that have to be repeated after given time
        $throttledRequestChunk = [System.Collections.Generic.List[Object]]::new()
    }

    process {
        # flatten the batch request array
        if ($batchRequest | Where-Object { $_ -and $_.GetType().BaseType -eq [System.Array] }) {
            $batchRequest = ConvertTo-FlatArray -inputArray $batchRequest
        }

        # check url validity
        $batchRequest.URL | ForEach-Object {
            if ($_ -notlike "https://management.azure.com/*" -and $_ -notlike "/*") {
                throw "url '$_' has to be relative (without the whole 'https://management.azure.com' part) or absolute!"
            }

            if ($_ -notmatch "/subscriptions/|\?" -and $_ -notmatch "/providers/|\?" -and $_ -notmatch "/resources/|\?" -and $_ -notmatch "/locations/|\?" -and $_ -notmatch "/tenants/|\?" -and $_ -notmatch "/bulkdelete/|\?") {
                throw "url '$_' is not valid. Is should starts with:`n/subscriptions, /providers, /resources, /locations, /tenants or /bulkdelete!"
            }
        }

        foreach ($request in $batchRequest) {
            $requestChunk.Add($request)

            # check if the buffer has reached the required chunk size
            if ($requestChunk.count -eq $chunkSize) {
                [int] $script:retryAfter = 0
                _processChunk $requestChunk

                # clear the buffer
                $requestChunk.Clear()

                # process requests that need to be repeated (paginated, failed on remote server,...)
                if ($extraRequestChunk) {
                    Write-Warning "Processing $($extraRequestChunk.count) paginated or server-side-failed request(s)"
                    Invoke-AzureBatchRequest -batchRequest $extraRequestChunk -dontBeautifyResult:$dontBeautifyResult

                    $extraRequestChunk.Clear()
                }

                # process throttled requests
                if ($throttledRequestChunk) {
                    Write-Warning "Processing $($throttledRequestChunk.count) throttled request(s) with $script:retryAfter seconds wait time"
                    Start-Sleep -Seconds $script:retryAfter
                    Invoke-AzureBatchRequest -batchRequest $throttledRequestChunk -dontBeautifyResult:$dontBeautifyResult

                    $throttledRequestChunk.Clear()
                }
            }
        }
    }

    end {
        # process any remaining requests in the buffer

        if ($requestChunk.Count -gt 0) {
            [int] $script:retryAfter = 0
            _processChunk $requestChunk

            # process requests that need to be repeated (paginated, failed on remote server,...)
            if ($extraRequestChunk) {
                Write-Warning "Processing $($extraRequestChunk.count) paginated or server-side-failed request(s)"
                Invoke-AzureBatchRequest -batchRequest $extraRequestChunk -dontBeautifyResult:$dontBeautifyResult
            }

            # process throttled requests
            if ($throttledRequestChunk) {
                Write-Warning "Processing $($throttledRequestChunk.count) throttled request(s) with $script:retryAfter seconds wait time"
                Start-Sleep -Seconds $script:retryAfter
                Invoke-AzureBatchRequest -batchRequest $throttledRequestChunk -dontBeautifyResult:$dontBeautifyResult
            }
        }
    }
}

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

    When the 'placeholder' parameter is specified, for each value it contains, new request url will be generated with such value used instead of the '<placeholder>' string.

    It needs to contain the api-version parameter, otherwise it will throw an error!
    For example: 'https://management.azure.com/subscriptions/.../roleEligibilitySchedules?api-version=2020-10-01'.
    If you are unsure what api you can use:
     - use the one from the example above and in case the request fails with 400 error, check the error message for the correct api version.
     - use official corresponding Az cmdlet with -debug parameter (Get-AzStorageAccount -debug) and check the 'Absolute uri' output.
     - developer tools (F12) in your browser when using Azure Portal and check the request url there.

    .PARAMETER placeholder
    Array of items (string, integers, ..) that will be used in the request url (defined in 'url' parameter) instead of the "<placeholder>" string.

    .PARAMETER requestHeaderDetails
    RequestHeaderDetails (header) as a hashtable that should be added to each request in the batch.

    "requestHeaderDetails" = @{
        "commandName" = "fx.Microsoft_Azure_AD.ServicesPermissions.getPermissions"
    }

    .PARAMETER content
    Content hashtable that should be added to each request in the batch.

    .PARAMETER name
    Name (Id) of the request.
    If created request will be invoked via 'Invoke-AzureBatchRequest' function, this Id will be saved in the returned object's 'RequestName' property.
    If 'placeholder' parameter is also specified, suffix "_<randomNumber>" will be added to each generated request id (a.k.a final ID will be: <name>_<randomNumber>). This way each one is unique and at the same time you are able to filter the request results based on it in case you merge multiple different requests in one final batch.

    By default random-generated-number.

    .PARAMETER placeholderAsId
    Switch to use current 'placeholder' value used in the request URL as a request ID.

    BEWARE that request ID has to be unique across the pools of all batch requests, therefore use this switch with a caution!

    .EXAMPLE
    $batchRequest = New-AzureBatchRequest -url "/providers/Microsoft.Authorization/roleDefinitions?%24filter=type%20eq%20%27BuiltInRole%27&api-version=2022-05-01-preview", "/subscriptions/f3b08c7f-99a9-4a70-ba56-1e877abb77f7/providers/Microsoft.Authorization/roleEligibilitySchedules?api-version=2020-10-01"

    Invoke-AzureBatchRequest -batchRequest $batchRequest

    Creates batch request object containing both urls & run it.

    .EXAMPLE
    $subscriptionId = (Get-AzSubscription | ? State -EQ 'Enabled').Id

    New-AzureBatchRequest -url "https://management.azure.com/subscriptions/<placeholder>/providers/Microsoft.Authorization/roleEligibilitySchedules?api-version=2020-10-01" -placeholder $subscriptionId | Invoke-AzureBatchRequest

    Creates batch request object containing dynamically generated urls for every id in the $subscriptionId array & run it.

    .EXAMPLE
    $subscriptionId = (Get-AzSubscription | ? State -EQ 'Enabled').Id

    $batchRequest = New-AzureBatchRequest -url "https://management.azure.com/subscriptions/<placeholder>/providers/Microsoft.Authorization/roleEligibilitySchedules?api-version=2020-10-01" -placeholder $subscriptionId

    # you need to process all requests by chunks of 20 items
    $payload = @{
        requests = $batchRequest[0..19]
    }

    Invoke-AzRestMethod -Uri "https://management.azure.com/batch?api-version=2020-06-01" -Method POST -Payload ($payload | ConvertTo-Json -Depth 20)

    .EXAMPLE
    $arcMachines = Get-ArcMachineOverview

    New-AzureBatchRequest -url "<placeholder>/providers/Microsoft.HybridConnectivity/endpoints/default?api-version=2023-03-15" -placeholder $arcMachines.resourceId -placeholderAsId | Invoke-AzureBatchRequest

    Check connectivity endpoints for all ARC machines, where returned object's Name property will contain the resource ID of the corresponding ARC machine for easy identification of results.

    .EXAMPLE
    $query = @'
        resources
        | where isnotnull(properties.accessPolicies) and array_length(properties.accessPolicies) > 0
        | mv-expand accessPolicy = properties.accessPolicies
        | project
            id,
            resourceName = name,
            resourceType = type,
            resourceGroup,
            subscriptionId,
            accessPolicy
'@

    $content = @{
        query = $query
        subscriptions = @()
        options = @{
            '$top'=1000
            '$skipToken' = "ew0KICAiJGlkIjogIjEiLA0KICAiTWF4Um93cyI6IDEwMDAsDQogICJSb3dzVG9Ta2lwIjogMTAwMCwNCiAgIkt1c3RvQ2x1c3RlclVybCI6ICJodHRwczovL2FyZy1uZXUtMTMtc2YuYXJnLmNvcmUud2luZG93cy5uZXQiDQp9"
        }
    }

    New-AzureBatchRequest -method POST -url "https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2021-03-01" -content $content | Invoke-AzureBatchRequest

    Invoke KQL query against Azure Resource Graph using batch request.

    .NOTES
    Uses undocumented API https://github.com/Azure/azure-sdk-for-python/issues/9271 :).
    #>

    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param (
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE', 'HEAD', 'PATCH')]
        [string] $method = "GET",

        [Parameter(Mandatory = $true)]
        [Alias("urlWithPlaceholder", "uri")]
        [string[]] $url,

        $placeholder,

        [hashtable] $requestHeaderDetails,

        [hashtable] $content,

        [Parameter(ParameterSetName = "Id")]
        [Alias("id")]
        [string] $name,

        [Parameter(ParameterSetName = "PlaceholderAsId")]
        [switch] $placeholderAsId
    )

    #region validity checks
    if ($name -and @($url).count -gt 1) {
        throw "'name' parameter cannot be used with multiple urls"
    }

    if ($name -and $placeholderAsId) {
        throw "'name' and 'placeholderAsId' parameters cannot be used together"
    }

    if ($placeholder -and $url -notlike "*<placeholder>*") {
        throw "You have specified 'placeholder' parameter, but 'url' parameter doesn't contain string '<placeholder>' for replace."
    }

    if (!$placeholder -and $url -like "*<placeholder>*") {
        throw "You have specified 'url' with '<placeholder>' in it, but not the 'placeholder' parameter itself."
    }

    if ($placeholderAsId -and !$placeholder) {
        throw "'placeholderAsId' parameter cannot be used without specifying 'placeholder' parameter"
    }

    if ($placeholderAsId -and $placeholder -and @($url).count -gt 1) {
        throw "'placeholderAsId' parameter cannot be used with multiple urls"
    }

    # api version check
    $url | ForEach-Object {
        if ($_ -notlike "*api-version=*") {
            throw "URL '$_' is missing what api to use (api-version=2025-01-01 or similar). For example: 'https://management.azure.com/subscriptions/.../roleEligibilitySchedules?api-version=2020-10-01'. If you are unsure what api you can use, use the one from the example above and in case the request fails with 400 error, check the error message for the correct api version. Or use official Az cmdlet with -debug parameter and check the 'Absolute uri' output."
        }
    }
    #endregion validity checks

    if ($placeholder) {
        $url = $placeholder | ForEach-Object {
            $p = $_

            $url | ForEach-Object {
                $_ -replace "<placeholder>", $p
            }
        }
    }

    $index = 0

    $url | ForEach-Object {
        # fix common mistake where there are multiple slashes
        $_ = $_ -replace "(?<!^https:)/{2,}", "/"

        #region url validity checks
        if ($_ -notlike "https://management.azure.com/*" -and $_ -notlike "/*") {
            throw "url '$_' has to be in the relative (without the 'https://management.azure.com' prefix and starting with the '/') or absolute form!"
        }

        if ($_ -notmatch "/subscriptions/|\?" -and $_ -notmatch "/providers/|\?" -and $_ -notmatch "/resources/|\?" -and $_ -notmatch "/locations/|\?" -and $_ -notmatch "/tenants/|\?" -and $_ -notmatch "/bulkdelete/|\?") {
            throw "url '$_' is not valid. Is should starts with:`n/subscriptions, /providers, /resources, /locations, /tenants or /bulkdelete!"
        }
        #endregion url validity checks

        $property = [ordered]@{
            HttpMethod = $method
            URL        = $_
        }

        if ($name) {
            if ($placeholder) {
                $property.Name = ($name + "_" + (Get-Random))
            } else {
                $property.Name = $name
            }
        } elseif ($placeholderAsId) {
            $property.Name = @($placeholder)[$index]
        } else {
            $property.Name = Get-Random
        }

        if ($requestHeaderDetails) {
            $property.requestHeaderDetails = $requestHeaderDetails
        }

        if ($content) {
            $property.content = $content
        }

        New-Object -TypeName PSObject -Property $property

        ++$index
    }
}

function New-AzureDevOpsAuthHeader {
    <#
    .SYNOPSIS
    Function for getting authentication header for web requests against Azure DevOps.

    .DESCRIPTION
    Function for getting authentication header for web requests against Azure DevOps.

    .PARAMETER useMsal
    Switch to use MSAL authentication.

    Function uses Az token by default.

    .EXAMPLE
    $header = New-AzureDevOpsAuthHeader
    Invoke-WebRequest -Uri $uri -Headers $header

    .NOTES
    https://docs.microsoft.com/en-us/rest/api/azure/devops/?view=azure-devops-rest-7.1
    PowerShell module AzSK.ADO > ContextHelper.ps1 > GetCurrentContext
    https://stackoverflow.com/questions/56355274/getting-oauth-tokens-for-azure-devops-api-consumption
    https://stackoverflow.com/questions/52896114/use-azure-ad-token-to-authenticate-with-azure-devops
    #>

    [CmdletBinding()]
    param (
        [switch] $useMsal
    )

    # TODO oAuth auth https://github.com/microsoft/azure-devops-auth-samples/tree/master/OAuthWebSample
    # $msalToken = Get-MsalToken -TenantId $TenantID -ClientId $ClientID -UserCredential $Credential -Scopes ([String]::Concat($($ApplicationIdUri), '/user_impersonation')) -ErrorAction Stop

    $clientId = "872cd9fa-d31f-45e0-9eab-6e460a02d1f1" # Visual Studio
    $adoResourceId = "499b84ac-1321-427f-aa17-267ca6975798" # Azure DevOps app ID

    if ($useMsal) {
        if (!(Get-Module MSAL.PS) -and !(Get-Module MSAL.PS -ListAvailable)) {
            throw "Module MSAL.PS is missing. Function $($MyInvocation.MyCommand) cannot continue"
        }

        $msalToken = Get-MsalToken -Scopes "$adoResourceId/.default" -ClientId $clientId

        if ($msalToken.accessToken) {
            $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f "", $msalToken.accessToken)))
            $header = @{
                'Authorization' = "Basic $base64AuthInfo"
                'Content-Type'  = 'application/json'
            }
        } else {
            throw "Unable to obtain DevOps MSAL token"
        }
    } else {
        if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
            throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
        }

        $secureToken = (Get-AzAccessToken -ResourceUrl $adoResourceId -AsSecureString).Token
        $token = [PSCredential]::New('dummy', $secureToken).GetNetworkCredential().Password
        $header = @{
            'Authorization' = 'Bearer ' + $token
            'Content-Type'  = 'application/json'
        }
    }

    return $header
}

function Start-AzureSync {
    <#
        .SYNOPSIS
        Invoke Azure AD sync cycle command (Start-ADSyncSyncCycle) on the server where 'Azure AD Connect' is installed.

        .DESCRIPTION
        Invoke Azure AD sync cycle command (Start-ADSyncSyncCycle) on the server where 'Azure AD Connect' is installed.

        .PARAMETER Type
        Type of sync.

        Initial (full) or just delta.

        Delta is default.

        .PARAMETER ADSynchServer
        Name of the server where 'Azure AD Connect' is installed

        .EXAMPLE
        Start-AzureSync -ADSynchServer ADSYNCSERVER
        Invokes synchronization between on-premises AD and AzureAD on server ADSYNCSERVER by running command Start-ADSyncSyncCycle there.
    #>

    [Alias("Sync-ADtoAzure", "Start-AzureADSync")]
    [cmdletbinding()]
    param (
        [ValidateSet('delta', 'initial')]
        [string] $type = 'delta',

        [ValidateNotNullOrEmpty()]
        [string] $ADSynchServer
    )

    $ErrState = $false
    do {
        try {
            Invoke-Command -ScriptBlock { Start-ADSyncSyncCycle -PolicyType $using:type } -ComputerName $ADSynchServer -ErrorAction Stop | Out-Null
            $ErrState = $false
        } catch {
            $ErrState = $true
            Write-Warning "Start-AzureSync: Error in Sync:`n$_`nRetrying..."
            Start-Sleep 5
        }
    } while ($ErrState -eq $true)
}

Export-ModuleMember -function Connect-AzAccount2, Connect-PnPOnline2, FilterBy-AzureScope, Get-AuthenticatedSPIdentityAppId, Get-AzureDirectoryObject, Get-AzureDirectoryObjectMemberOf, Invoke-AzureBatchRequest, New-AzureBatchRequest, New-AzureDevOpsAuthHeader, Start-AzureSync

Export-ModuleMember -alias Get-AzureAccountMemberOf, Get-AzureAccountPermanentMemberOf, Start-AzureADSync, Sync-ADtoAzure
