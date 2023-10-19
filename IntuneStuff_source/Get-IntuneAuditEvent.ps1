#requires -modules Microsoft.Graph.DeviceManagement.Administration, Microsoft.Graph.Authentication
function Get-IntuneAuditEvent {
    <#
    .SYNOPSIS
    Proxy function for Get-MgDeviceManagementAuditEvent for returning Intune audit events based on given criteria.

    .DESCRIPTION
    Proxy function for Get-MgDeviceManagementAuditEvent for returning Intune audit events based on given criteria.

    Requires you to have DeviceManagementApps.Read.All scope.

    .PARAMETER actorUPN
    Search by UPN of the user who made the change.

    UPN is CaSe SEnsitiVE!

    .PARAMETER resourceId
    Search by ID of the resource which was modified.

    .PARAMETER from
    Date when the search should start.

    .PARAMETER to
    Date when the search should end.

    .PARAMETER operationType
    Filter by operation type.

    Action
    Create
    Delete
    Get
    Patch
    RemoveReference
    SetReference

    .PARAMETER category
    Filter by operation category.

    Application
    AssignmentFilter
    Compliance
    Device
    DeviceConfiguration
    DeviceIntent
    Enrollment
    Other
    Role
    SoftwareUpdates

    .EXAMPLE
    Connect-MgGraph -Scopes DeviceManagementApps.Read.All
    Get-IntuneAuditEvent

    Return all Intune audit events.

    .EXAMPLE
    Connect-MgGraph -Scopes DeviceManagementApps.Read.All
    Get-IntuneAuditEvent -actorUPN test@contoso.com -resourceId b7e42574-2b0e-41ed-8007-2634 -from 1.1.2022

    Return all Intune audit events made by test@contoso.com to resource with given ID from 1.1.2022.

    .EXAMPLE
    Connect-MgGraph -Scopes DeviceManagementApps.Read.All
    Get-IntuneAuditEvent -category compliance

    Return all Intune compliance related audit events.

    .NOTES
    Requires DeviceManagementApps.Read.All scope.

    https://learn.microsoft.com/en-us/graph/api/intune-auditing-auditevent-list?view=graph-rest-1.0&tabs=powershell
    https://www.computerystuff.com/search-intune-audit-events-by-device-name/
    #>

    [CmdletBinding()]
    param (
        [string] $actorUPN,

        [string] $resourceId,

        [ValidateScript({
                if (($_.getType().name -eq "string" -and [DateTime]::Parse($_)) -or ($_.getType().name -eq "dateTime")) {
                    $true
                } else {
                    throw "Enter in format per your culture. For cs-CZ: 15.2.2019 15:00. For en-US: 2.15.2019 15:00."
                }
            })]
        $from,

        [ValidateScript({
                if (($_.getType().name -eq "string" -and [DateTime]::Parse($_)) -or ($_.getType().name -eq "dateTime")) {
                    $true
                } else {
                    throw "Enter in format per your culture. For cs-CZ: 15.2.2019 15:00. For en-US: 2.15.2019 15:00."
                }
            })]
        $to,

        [ValidateSet('Action', 'Create', 'Delete', 'Get', 'Patch', 'RemoveReference', 'SetReference')]
        [string] $operationType,

        [ValidateSet('Application', 'AssignmentFilter', 'Compliance', 'Device', 'DeviceConfiguration', 'DeviceIntent', 'Enrollment', 'Other', 'Role', 'SoftwareUpdates')]
        [string] $category
    )

    if ($from -and $from.getType().name -eq "string") { $from = [DateTime]::Parse($from) }
    if ($to -and $to.getType().name -eq "string") { $to = [DateTime]::Parse($to) }

    if ($from -and $to -and $from -gt $to) {
        throw "From cannot be after To"
    }

    $filter = @()

    if ($actorUPN) {
        Write-Warning "Beware that filtering by UPN is case sensitive!"
        $filter += "Actor/UserPrincipalName eq '$actorUPN'"
    }
    if ($resourceId) {
        $filter += "Resources/any(c: c/ResourceId eq '$resourceId')"
    }
    if ($from) {
        # Intune logs use UTC time
        $from = $from.ToUniversalTime()
        $filterDateTime = Get-Date -Date $from -Format "yyyy-MM-ddTHH:mm:ss"
        $filter += "ActivityDateTime ge $filterDateTime`Z"
    }
    if ($to) {
        # Intune logs use UTC time
        $to = $to.ToUniversalTime()
        $filterDateTime = Get-Date -Date $to -Format "yyyy-MM-ddTHH:mm:ss"
        $filter += "ActivityDateTime le $filterDateTime`Z"
    }
    if ($operationType) {
        $filter += "ActivityOperationType eq '$operationType'"
    }
    if ($category) {
        $filter += "Category eq '$category'"
    }

    $finalFilter = $filter -join ' and '
    Write-Verbose "filter: $finalFilter"
    Get-MgDeviceManagementAuditEvent -Filter $finalFilter -All | sort ActivityDateTime | % {
        [PSCustomObject]@{
            DateTimeUTC        = $_.ActivityDateTime
            ResourceId         = $_.Resources.ResourceId
            ResourceName       = $_.Resources.DisplayName
            OperationType      = $_.ActivityOperationType
            Result             = $_.ActivityResult
            Type               = $_.ActivityType
            ActorUPN           = $_.Actor.UserPrincipalName
            ActorID            = $_.Actor.UserId
            ActorSPN           = $_.Actor.ServicePrincipalName
            ActorApplication   = $_.Actor.ApplicationDisplayName
            Category           = $_.Category
            # ComponentName      = $_.ComponentName
            ModifiedProperties = $_.Resources.ModifiedProperties | ? { $_.OldValue -ne $_.NewValue }
            OriginalObject     = $_
        }
    }
}