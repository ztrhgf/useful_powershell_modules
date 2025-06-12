function Invoke-GraphBatchRequest {
    <#
    .SYNOPSIS
    Function to invoke Graph Api batch request(s).

    .DESCRIPTION
    Function to invoke Graph Api batch request(s).

    Handles pagination, throttling and server-side errors.

    .PARAMETER batchRequest
    PSobject(s) representing the requests to be run in a batch.

    Can be created manually or via New-GraphBatchRequest.

    https://learn.microsoft.com/en-us/graph/json-batching?tabs=http#creating-a-batch-request

    .PARAMETER graphVersion
    What api version should be requested.

    Possible values: 'v1.0', 'beta'.

    By default 'v1.0'.

    .PARAMETER dontBeautifyResult
    Switch for returning original/non-modified batch request(s) results.

    By default batch-request-related properties like batch status, headers, nextlink, etc are stripped.

    To be able to filter returned objects by their originated request, new property 'RequestId' is added.

    .PARAMETER dontAddRequestId
    Switch to avoid adding extra 'RequestId' property to the "beautified" results.

    .EXAMPLE
    $batchRequest = @((New-GraphBatchRequest -Url "applications"), (New-GraphBatchRequest -Url "servicePrincipals"))

    Invoke-GraphBatchRequest -batchRequest $batchRequest -dontBeautifyResult

    Creates batch request object for getting all Azure applications and Service Principals & run it.
    You won't get directly the results, but batch objects instead, where results are stored in body.value (or just body) property.

    .EXAMPLE
    $batchRequest = @(
        [PSCustomObject]@{
            id     = "app"
            method = "GET"
            URL    = "applications"
        },
        [PSCustomObject]@{
            id     = "sp"
            method = "GET"
            URL    = "servicePrincipals"
        }
    )

    $allResults = Invoke-GraphBatchRequest -batchRequest $batchRequest

    $servicePrincipalList = $allResults | ? RequestId -eq "sp"
    $applicationList = $allResults | ? RequestId -eq "app"

    Creates batch request object for getting all Azure applications and Service Principals & run it.
    The result will be beautified so you get the all results in one array, where each object is enhanced by RequestId property to easily identify the source request.

    .EXAMPLE
    $batchRequest = New-GraphBatchRequest -url "/deviceManagement/managedDevices/38027eb9-1f3e-49ea-bf91-f7b7f07c3a63?`$select=id,devicename&`$expand=DetectedApps", "/deviceManagement/managedDevices/aaa932b4-5af4-4120-86b1-ab64b964a56s?`$select=id,devicename&`$expand=DetectedApps"

    Invoke-GraphBatchRequest -batchRequest $batchRequest -graphVersion beta

    Creates batch request object containing both urls & run it.

    .EXAMPLE
    $deviceId = (Get-MgBetaDeviceManagementManagedDevice -Property id -All).Id

    New-GraphBatchRequest -url "/deviceManagement/managedDevices/<placeholder>?`$select=id,devicename&`$expand=DetectedApps" -placeholder $deviceId | Invoke-GraphBatchRequest -graphVersion beta

    Creates batch request object containing dynamically generated urls for every id in the $deviceId array & run it.

    .NOTES
    https://learn.microsoft.com/en-us/graph/json-batching
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject[]]$batchRequest,

        [ValidateSet('v1.0', 'beta')]
        [string] $graphVersion = "v1.0",

        [switch] $dontBeautifyResult,

        [switch] $dontAddRequestId
    )

    begin {
        if ($PSCmdlet.MyInvocation.PipelineLength -eq 1) {
            Write-Verbose "Total number of requests to process is $($batchRequest.count)"
        }

        if ($dontBeautifyResult -and $dontAddRequestId) {
            Write-Verbose "'dontAddRequestId' parameter will be ignored, 'RequestId' property is not being added when 'dontBeautifyResult' parameter is used"
        }

        # api batch requests are limited to 20 requests
        $chunkSize = 20
        # base graph api uri
        $uri = "https://graph.microsoft.com"
        # batch uri
        $requestUri = "$uri/$graphVersion/`$batch"
        # buffer to hold chunks of requests
        $requestChunk = [System.Collections.ArrayList]::new()
        # paginated or remotely failed requests that should be processed too, to get all the results
        $extraRequestChunk = [System.Collections.ArrayList]::new()
        # throttled requests that have to be repeated after given time
        $throttledRequestChunk = [System.Collections.ArrayList]::new()

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
                [System.Collections.ArrayList] $requestChunk
            )

            $duplicityId = $requestChunk | Select-Object -ExpandProperty id | Group-Object | ? { $_.Count -gt 1 }
            if ($duplicityId) {
                throw "Batch requests must have unique ids. Id $(($duplicityId | select -Unique) -join ', ') is there more than once"
            }

            Write-Debug ($requestChunk | ConvertTo-Json)

            Write-Verbose "Processing batch of $($requestChunk.count) request(s):`n$(($requestChunk | sort Url | % {" - $($_.Id) - $($_.Url)"} ) -join "`n")"

            #region process given chunk of batch requests
            $start = Get-Date

            $body = @{
                requests = [array]$requestChunk
            }

            Invoke-MgRestMethod -Method Post -Uri $requestUri -Body ($body | ConvertTo-Json -Depth 50) -ContentType "application/json" -OutputType Json | ConvertFrom-Json | % {
                $responses = $_.responses

                #region return the output
                if ($dontBeautifyResult) {
                    # return original response

                    $responses
                } else {
                    # return just actually requested data without batch-related properties and enhance the returned object with 'RequestId' property for easier filtering

                    foreach ($response in $responses) {
                        # properties to return
                        $property = @("*")
                        if (!$dontAddRequestId) {
                            $property += @{n = 'RequestId'; e = { $response.Id } }
                        }

                        if ($response.body.value) {
                            # the result is stored in 'value' property
                            $response.body.value | select -Property $property -ExcludeProperty '@odata.context', '@odata.nextLink'
                        } elseif ($response.body -and ($response.body | Get-Member -MemberType NoteProperty).count -eq 2 -and ($response.body | Get-Member -MemberType NoteProperty).Name -contains '@odata.context' -and ($response.body | Get-Member -MemberType NoteProperty).Name -contains 'value') {
                            # the result is stored in 'value' property, but no results were returned, skipping
                        } elseif ($response.body) {
                            # the result is in the 'body' property itself
                            $response.body | select -Property $property -ExcludeProperty '@odata.context', '@odata.nextLink'
                        } else {
                            # no results in 'body.value' nor 'body' property itself
                        }
                    }
                }
                #endregion return the output

                # check responses status
                $failedBatchJob = [System.Collections.ArrayList]::new()

                foreach ($response in $responses) {
                    # https://learn.microsoft.com/en-us/graph/errors#http-status-codes
                    if ($response.Status -eq 200) {
                        # success

                        if ($response.body.'@odata.nextLink') {
                            # paginated (get remaining results by query returned NextLink URL)

                            Write-Verbose "Batch result for request '$($response.Id)' is paginated. Nextlink will be processed in the next batch"

                            $relativeNextLink = $response.body.'@odata.nextLink' -replace [regex]::Escape("https://graph.microsoft.com/$graphVersion/")
                            # make a request object copy, so I can modify it without interfering with the original object
                            $nextLinkRequest = $requestChunk | ? Id -EQ $response.Id | ConvertTo-Json -Depth 10 | ConvertFrom-Json
                            # replace original URL with the nextLink
                            $nextLinkRequest.URL = $relativeNextLink
                            # add the request for later processing
                            $null = $extraRequestChunk.Add($nextLinkRequest)
                        }
                    } elseif ($response.Status -in 429, 509) {
                        # throttled (will be repeated after given time)

                        $jobRetryAfter = $response.Headers.'Retry-After'
                        $throttledBatchRequest = $requestChunk | ? Id -EQ $response.Id

                        Write-Verbose "Batch request with Id: '$($throttledBatchRequest.Id)', Url:'$($throttledBatchRequest.Url)' was throttled, hence will be repeated after $jobRetryAfter seconds"

                        if ($jobRetryAfter -eq 0) {
                            # request can be repeated without any delay
                            #TIP for performance reasons adding to $extraRequestChunk batch (to avoid invocation of unnecessary batch job)
                            $null = $extraRequestChunk.Add($throttledBatchRequest)
                        } else {
                            # request can be repeated after delay
                            # add the request for later processing
                            $null = $throttledRequestChunk.Add($throttledBatchRequest)
                        }

                        # get highest retry-after wait time
                        if ($jobRetryAfter -gt $script:retryAfter) {
                            Write-Verbose "Setting $jobRetryAfter retry-after time"
                            $script:retryAfter = $jobRetryAfter
                        }
                    } elseif ($response.Status -in 500, 502, 503, 504) {
                        # some internal error on remote side (will be repeated)

                        $problematicBatchRequest = $requestChunk | ? Id -EQ $response.Id

                        Write-Verbose "Batch request with Id: '$($problematicBatchRequest.Id)', Url:'$($problematicBatchRequest.Url)' had internal error '$($problematicBatchRequest.Status)', hence will be repeated"

                        $null = $extraRequestChunk.Add($problematicBatchRequest)
                    } else {
                        # failed

                        $failedBatchRequest = $requestChunk | ? Id -EQ $response.Id

                        $null = $failedBatchJob.Add("- Id: '$($response.Id)', Url:'$($failedBatchRequest.Url)', StatusCode: '$($response.Status)', Error: '$($response.body.error.message)'")
                    }
                }

                # exit if critical failure occurred
                if ($failedBatchJob) {
                    Write-Error "Following batch request(s) failed:`n$($failedBatchJob -join "`n")"
                }
            }

            $end = Get-Date

            Write-Verbose "It took $((New-TimeSpan -Start $start -End $end).TotalSeconds) seconds to process the batch"
            #endregion process given chunk of batch requests
        }
    }

    process {
        # check url validity
        $batchRequest.URL | % {
            if ($_ -like "http*" -or $_ -like "*/beta/*" -or $_ -like "*/v1.0/*" -or $_ -like "*/graph.microsoft.com/*") {
                throw "url '$_' has to be relative (without the whole 'https://graph.microsoft.com/<apiversion>' part)!"
            }
        }

        foreach ($request in $batchRequest) {
            $null = $requestChunk.Add($request)

            # check if the buffer has reached the required chunk size
            if ($requestChunk.count -eq $chunkSize) {
                [int] $script:retryAfter = 0
                _processChunk $requestChunk

                # clear the buffer
                $requestChunk.Clear()

                # process requests that need to be repeated (paginated, failed on remote server,...)
                if ($extraRequestChunk) {
                    Write-Warning "Processing $($extraRequestChunk.count) paginated or server-side-failed request(s)"
                    Invoke-GraphBatchRequest -batchRequest $extraRequestChunk -graphVersion $graphVersion -dontBeautifyResult:$dontBeautifyResult

                    $extraRequestChunk.Clear()
                }

                # process throttled requests
                if ($throttledRequestChunk) {
                    Write-Warning "Processing $($throttledRequestChunk.count) throttled request(s) with $script:retryAfter seconds wait time"
                    Start-Sleep -Seconds $script:retryAfter
                    Invoke-GraphBatchRequest -batchRequest $throttledRequestChunk -graphVersion $graphVersion -dontBeautifyResult:$dontBeautifyResult

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
                Invoke-GraphBatchRequest -batchRequest $extraRequestChunk -graphVersion $graphVersion -dontBeautifyResult:$dontBeautifyResult
            }

            # process throttled requests
            if ($throttledRequestChunk) {
                Write-Warning "Processing $($throttledRequestChunk.count) throttled request(s) with $script:retryAfter seconds wait time"
                Start-Sleep -Seconds $script:retryAfter
                Invoke-GraphBatchRequest -batchRequest $throttledRequestChunk -graphVersion $graphVersion -dontBeautifyResult:$dontBeautifyResult
            }
        }
    }
}