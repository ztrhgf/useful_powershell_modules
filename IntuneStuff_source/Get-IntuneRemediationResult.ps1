function Get-IntuneRemediationResult {
    <#
    .SYNOPSIS
    Get results for an Intune remediation script run.

    .DESCRIPTION
    Function gets results for a specified Intune remediation script.

    Results include device information, output, errors, and status.

    There is also ProcessedOutput property that contains the 'output' processed by ConvertFrom-CompressedString and ConvertFrom-Json functions. Usable in case the output was converted to compressed JSON (ConvertTo-Json -Compress) and/or converted to compressed string (ConvertTo-CompressedString)and you want the original output back.

    .PARAMETER id
    Optional ID of the remediation script to get results for.

    If not provided, a list of available remediations will be shown for interactive selection.

    .EXAMPLE
    Get-IntuneRemediationResult

    Shows a list of all available remediation scripts for interactive selection and then retrieves their results.

    .EXAMPLE
    Get-IntuneRemediationResult -id "12345678-1234-1234-1234-123456789012"

    Gets results for the specified remediation script.

    .NOTES
    Permission requirements:
    - DeviceManagementConfiguration.Read.All
    - DeviceManagementManagedDevices.Read.All
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [guid] $id
    )

    $ErrorActionPreference = "Stop"

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-MgGraph."
    }

    # Helper function to process output
    function _processOutput {
        param (
            [string] $string,
            [string] $dvcId,
            [string] $dvcName
        )

        if (!$string) {
            return
        }

        if (($string | Measure-Object -Character).Characters -ge 2048) {
            Write-Warning "Output for device $dvcName ($dvcId) exceeded 2048 chars a.k.a. is truncated."
        }

        # Decompress the string if it is compressed
        try {
            $decompressedString = ConvertFrom-CompressedString $string -ErrorAction Stop
            $string = $decompressedString
        } catch {
            Write-Verbose "Not a compressed string"
        }

        # Convert to object if the string is a JSON
        try {
            $string | ConvertFrom-Json -ErrorAction Stop
            return
        } catch {
            Write-Verbose "Not a JSON"
        }

        return
    }

    # If no id provided, show a list of available remediations
    if (!$id) {
        Write-Verbose "No remediation script ID provided, retrieving available remediations"

        try {
            $availableRemediations = Get-MgBetaDeviceManagementDeviceHealthScript -All -Property Id, DisplayName, Description, Publisher, CreatedDateTime | Sort-Object -Property CreatedDateTime -Descending

            if ($availableRemediations.Count -eq 0) {
                Write-Warning "No remediation scripts found"
                return
            }

            Write-Verbose "Found $($availableRemediations.Count) remediation scripts"

            $selectedRemediation = $availableRemediations |
                Select-Object @{Name = 'Id'; Expression = { $_.Id } },
                @{Name = 'Name'; Expression = { $_.DisplayName } },
                @{Name = 'Publisher'; Expression = { $_.Publisher } },
                @{Name = 'Created'; Expression = { $_.CreatedDateTime } } |
                Out-GridView -Title "Select a remediation script" -OutputMode Single

            if (!$selectedRemediation) {
                Write-Warning "No remediation script selected"
                return
            }

            $id = $selectedRemediation.Id
            Write-Verbose "Selected remediation script: $($selectedRemediation.Name) ($id)"
        } catch {
            throw "Failed to retrieve remediation scripts: $_"
        }
    }

    # Get remediation details
    try {
        Write-Verbose "Retrieving remediation script $($remediationScript.DisplayName) ($id)"
        $remediationScript = Get-MgBetaDeviceManagementDeviceHealthScript -DeviceHealthScriptId $id
        if (!$remediationScript) {
            throw "Remediation script with ID $id not found"
        }
    } catch {
        throw "Failed to retrieve remediation script: $_"
    }

    # Get all device results for this remediation
    try {
        Write-Verbose "Retrieving device run states for remediation script"
        $remediationResults = Get-MgBetaDeviceManagementDeviceHealthScriptDeviceRunState -DeviceHealthScriptId $id -All

        if ($remediationResults.Count -eq 0) {
            Write-Warning "No results found for remediation script $($remediationScript.DisplayName)"
            return
        }

        Write-Verbose "Found $($remediationResults.Count) device results"

        # Create a lookup of device IDs to names
        $deviceIds = $remediationResults | ForEach-Object { $_.Id.Split(":")[1] } | Select-Object -Unique

        # Use Graph API batching for better performance
        if ($deviceIds.Count -gt 0) {
            Write-Verbose "Getting device names using Graph API batching"

            # Execute batch request
            $batchResults = New-GraphBatchRequest -placeholder $deviceIds -url "deviceManagement/managedDevices/<placeholder>`?`$select=id,deviceName" | Invoke-GraphBatchRequest
        }

        # Process and output results
        $results = foreach ($result in $remediationResults) {
            $dvcId = $result.Id.Split(":")[1]
            $dvcName = $batchResults | ? id -EQ $dvcId | Select-Object -ExpandProperty deviceName

            [PSCustomObject]@{
                DeviceId            = $dvcId
                DeviceName          = $dvcName
                LastSyncDateTimeUTC = $result.LastStateUpdateDateTime
                Output              = $result.PreRemediationDetectionScriptOutput
                ProcessedOutput     = _processOutput -string $result.PreRemediationDetectionScriptOutput -dvcId $dvcId -dvcName $dvcName
                Error               = $result.PreRemediationDetectionScriptError
                Status              = $result.DetectionState
                RemediationName     = $remediationScript.DisplayName
                RemediationId       = $id
            }
        }

        return $results
    } catch {
        throw "Failed to retrieve remediation results: $_"
    }
}