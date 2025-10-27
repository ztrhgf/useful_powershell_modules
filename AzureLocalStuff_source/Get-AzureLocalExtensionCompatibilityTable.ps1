function Get-AzureLocalExtensionCompatibilityTable {
    <#
    .SYNOPSIS
    Fetches the Azure CLI stack-hci-vm extension compatibility table.
    To know which versions of the Azure CLI stack-hci-vm extension are compatible with specific Azure Local versions.

    .DESCRIPTION
    This function retrieves the compatibility table for Azure CLI stack-hci-vm extensions from a markdown file hosted on GitHub at https://raw.githubusercontent.com/Azure-Samples/AzureLocal/refs/heads/main/Arc%20VMs%20Extension%20Compatibility.md.

    .OUTPUTS
    Returns a list of custom objects representing the compatibility data.

    .EXAMPLE
    Get-AzureHCIExtensionCompatibilityTable
    #>

    [CmdletBinding()]
    param ()

    $url = "https://raw.githubusercontent.com/Azure-Samples/AzureLocal/refs/heads/main/Arc%20VMs%20Extension%20Compatibility.md"

    try {
        # Fetch the raw content of the markdown file
        $markdownContent = Invoke-RestMethod -Uri $url -ErrorAction Stop
    } catch {
        throw "Failed to download the compatibility file from '$url'. Error: $_"
    }

    $lines = $markdownContent -split "`r?`n"
    $tableLines = @()
    $inTable = $false

    # Identify the table (header line) and collect all rows
    foreach ($line in $lines) {
        if ($line -match '^\|\s*Release Build\s*\|\s*Release Series\s*\|\s*vmss-hci\s*\|\s*stack-hci-vm\s*\|\s*API Version\s*\|') {
            $inTable = $true
            $tableLines += $line
            continue
        }
        if ($inTable) {
            if ($line -match '^\|') {
                $tableLines += $line
            } else {
                break
            }
        }
    }

    if ($tableLines.Count -lt 2) {
        throw "Can't find the Markdown table with the expected header."
    }

    # Skip header and separator lines to extract data rows
    $dataRows = $tableLines | Select-Object -Skip 2

    # Parse each row
    $results = foreach ($row in $dataRows) {
        $cols = $row -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        [PSCustomObject]@{
            ReleaseBuild  = $cols[0]
            ReleaseSeries = $cols[1]
            VmssHci       = $cols[2]
            StackHciVm    = $cols[3]
            ApiVersion    = $cols[4]
        }
    }

    # Output the full mapping table
    $results
}