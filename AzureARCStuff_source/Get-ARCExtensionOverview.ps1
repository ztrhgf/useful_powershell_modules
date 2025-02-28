function Get-ARCExtensionOverview {
    <#
    .SYNOPSIS
    Returns overview of all installed ARC extensions.

    .DESCRIPTION
    Returns overview of all installed ARC extensions.

    .EXAMPLE
    Get-ARCExtensionOverview

    Returns overview of all installed ARC extensions.
    #>

    [CmdletBinding()]
    param()

    if (!(Get-Module Az.ResourceGraph) -and !(Get-Module Az.ResourceGraph -ListAvailable)) {
        throw "Module Az.ResourceGraph is missing. Function $($MyInvocation.MyCommand) cannot continue"
    }

    $query = @'
resources
| where type =~ "microsoft.hybridcompute/machines/extensions"
'@
    # | project id, publisher = properties.publisher, type = properties.type, automaticUpgradesEnabled = properties.enableAutomaticUpgrade

    # execute the query
    Search-AzGraph -Query $Query
}