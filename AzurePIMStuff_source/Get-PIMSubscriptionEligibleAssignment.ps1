function Get-PIMSubscriptionEligibleAssignment {
    <#
    .SYNOPSIS
    Retrieves eligible role assignments for selected Azure subscriptions and their resources using PIM.

    .DESCRIPTION
    This function finds all Privileged Identity Management (PIM) eligible role assignments for the specified Azure subscriptions and their resources. If no subscription IDs are provided, it processes all enabled subscriptions in the tenant. The output includes principal, role, scope, and assignment details for each eligible assignment found.

    .PARAMETER id
    One or more Azure subscription IDs to process. If not provided, all enabled subscriptions will be processed automatically.

    .EXAMPLE
    Get-PIMSubscriptionEligibleAssignment
    Retrieves PIM eligible assignments for all enabled subscriptions and their resources.

    .EXAMPLE
    Get-PIMSubscriptionEligibleAssignment -id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    Retrieves PIM eligible assignments for the specified subscription and its resources.

    #>

    [CmdletBinding()]
    param (
        [string[]] $id
    )

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    if ($id) {
        $subscriptionId = $id
    } else {
        $subscriptionId = (Get-AzSubscription | ? State -EQ 'Enabled').Id
    }

    New-AzureBatchRequest -url "/subscriptions/<placeholder>/providers/Microsoft.Authorization/roleEligibilitySchedules?api-version=2020-10-01" -placeholder $subscriptionId | Invoke-AzureBatchRequest | ? { $_.Properties.MemberType -eq 'Direct' -and $_.Properties.ExpandedProperties.Scope.Type -ne "managementgroup" } | % {
        $id = $_.id

        $_.properties | % {
            if (!$_.endDateTime) { $end = "permanent" } else { $end = $_.endDateTime }

            [PSCustomObject] @{
                "PrincipalName"  = $_.expandedproperties.principal.displayName
                "PrincipalEmail" = $_.expandedproperties.principal.email
                "PrincipalType"  = $_.expandedproperties.principal.type
                "PrincipalId"    = $_.expandedproperties.principal.id
                "RoleName"       = $_.expandedproperties.roleDefinition.displayName
                "RoleType"       = $_.expandedproperties.roleDefinition.type
                "RoleId"         = $_.expandedproperties.roleDefinition.id
                "ScopeId"        = $_.expandedproperties.scope.id
                "ScopeName"      = $_.expandedproperties.scope.displayName
                "ScopeType"      = $_.expandedproperties.scope.type
                "Status"         = $_.Status
                "createdOn"      = $_.createdOn
                "startDateTime"  = $_.startDateTime
                "endDateTime"    = $end
                "updatedOn"      = $_.updatedOn
                "memberType"     = $_.memberType
                "id"             = $id
            }
        }
    }
}