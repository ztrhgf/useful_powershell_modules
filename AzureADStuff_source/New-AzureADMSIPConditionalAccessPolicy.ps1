function New-AzureADMSIPConditionalAccessPolicy {
    <#
    .SYNOPSIS
    Function for creating new Azure Conditional Policy where access for given users/group/roles will be allowed only from given IP range(s) (Named Location(s)).

    .DESCRIPTION
    Function for creating new Azure Conditional Policy where access for given users/group/roles will be allowed only from given IP range(s) (Named Location(s)).

    .PARAMETER ruleName
    Name of new Conditional Access policy.
    Prefix '_' will be automatically added.
    Same name will be used for new Named Location if needed.

    .PARAMETER includeUsers
    Azure GUID of the user(s) to include in this policy.

    .PARAMETER excludeUsers
    Azure GUID of the user(s) to exclude from this policy.

    .PARAMETER includeGroups
    Azure GUID of the group(s) to include in this policy.

    .PARAMETER excludeGroups
    Azure GUID of the group(s) to exclude from this policy.

    .PARAMETER includeRoles
    Azure GUID of the role(s) to include in this policy.

    .PARAMETER excludeRoles
    Azure GUID of the role(s) to exclude from this policy.

    .PARAMETER ipRange
    List of IP ranges in CIDR notation (for example 1.1.1.1/32).
    New Named Location will be created and used.

    .PARAMETER ipRangeIsTrusted
    Switch for setting defined ipRange(s) as trusted.

    .PARAMETER namedLocation
    Name or ID of the existing Named Location that should be used.
    Can be used instead of ipRange parameter.

    .PARAMETER justReport
    Switch for using 'enabledForReportingButNotEnforced' instead of forcing application of the new policy.
    Therefore violations against the policy will be audited instead of denied.

    .PARAMETER force
    Switch for omitting warning in case justReport parameter wasn't specified.

    .EXAMPLE
    New-AzureADMSIPConditionalAccessPolicy -ruleName otestik -includeUsers 'e5834928-0f19-492d-8a69-3fbc98fd84eb' -ipRange 192.168.1.1/32

    New Named Location named _otestik will be created with IP range 192.168.1.1/32.
    New Conditional Policy named _otestik in forced mode will be created with these conditions:
     - user condition: user with ID 'e5834928-0f19-492d-8a69-3fbc98fd84eb'
     - location condition: created Named Location

    .EXAMPLE
    New-AzureADMSIPConditionalAccessPolicy -justReport -ruleName otestik -includeUsers 'e5834928-0f19-492d-8a69-3fbc98fd84eb', 'a3c58ecb-924c-4ae9-b90c-a5a423f8bd5d' -namedLocation HQ_Brno

    New Conditional Policy named _otestik in audit mode will be created with these conditions:
     - user condition: users with ID 'e5834928-0f19-492d-8a69-3fbc98fd84eb', 'a3c58ecb-924c-4ae9-b90c-a5a423f8bd5d'
     - location condition: existing Named Location 'HQ_Brno'

    .NOTES
    https://github.com/Azure-Samples/azure-ad-conditional-access-apis/tree/main/01-configure/powershell

    pokud bych chtel nastavovat 'workload identities' (ale vyzaduji P2 licenci!) tak zrejme pres JSON protoze $conditions to neukazuje https://github.com/MicrosoftDocs/azure-docs/blob/master/articles/active-directory/conditional-access/workload-identity.md viz https://github.com/Azure-Samples/azure-ad-conditional-access-apis/tree/main/01-configure/graphapi
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $ruleName,

        [guid[]] $includeUsers,

        [guid[]] $excludeUsers,

        [guid[]] $includeGroups,

        [guid[]] $excludeGroups,

        [guid[]] $includeRoles,

        [guid[]] $excludeRoles,

        [ValidateScript( {
                if ($_ -match "/") {
                    $true
                } elseif ($_ -match '^[0-9a-d:.]+/\d+$') {
                    $true
                } else {
                    throw "IpRange $_ is not in correct form. It has to be in CIDR format (for example 1.2.3.4/32)"
                }
            })]
        [string[]] $ipRange,

        [switch] $ipRangeIsTrusted,

        [string] $namedLocation,

        [switch] $justReport,

        [switch] $force
    )

    $ErrorActionPreference = 'Stop'

    # required for creation of [Microsoft.Open.MSGraph.Model]
    Import-Module AzureADPreview

    #region validations
    if (!$ipRange -and !$namedLocation) {
        throw "You have to specify ipRange or namedLocation parameter."
    }
    if ($ipRange -and $namedLocation) {
        throw "You have to specify ipRange or namedLocation parameter. Not both!"
    }

    $ipRange | ? { $_ } | % {
        $ip = $_.Split("/")[0]
        $mask = $_.Split("/")[-1]

        if ($ip -ne [IPAddress]$ip) {
            throw "IP $ip isn't correct IP"
        }

        if ($mask -lt 24 -or $mask -gt 32) {
            throw "Mask ($mask) for IP $ip is too big or too small"
        }
    }

    if (!$includeUsers -and !$includeGroups -and !$includeRoles) {
        throw "You have to enter some user, group or role to apply this conditional rule for"
    }

    if (!$justReport -and !$force) {
        Write-Warning "You are going to create new Conditional Policy that will restrict access of selected users/groups/roles to all applications just from selected IPs/location."
        $choice = ""
        while ($choice -notmatch "^[Y|N]$") {
            $choice = Read-Host "Continue? (Y|N)"
        }
        if ($choice -eq "N") {
            return
        }
    }
    #endregion validations

    Connect-AzureAD2

    #region helper functions
    function _getObject {
        param ($id, $type)

        try {
            if (Get-AzureADObjectByObjectId -ObjectIds $id -ErrorAction Stop | ? ObjectType -EQ $type) {
                # ok
            } else {
                throw "'$id' Object Id doesn't exist in Azure"
            }
        } catch {
            throw "'$id' isn't correct Azure Object Id."
        }
    }

    #region named location
    #region validations
    if (Get-AzureADMSNamedLocationPolicy | ? DisplayName -EQ "_$ruleName") {
        throw "Named location with name '_$ruleName' already exists! Choose a different name."
    }
    if (Get-AzureADMSConditionalAccessPolicy | ? DisplayName -EQ "_$ruleName") {
        throw "Conditional policy with name '_$ruleName' already exists! Choose a different name."
    }
    if ($includeUsers -or $excludeUsers) {
        $includeUsers, $excludeUsers | ? { $_ } | % {
            _getObject -id $_ -type 'User'
        }
    }
    if ($includeGroups -or $excludeGroups) {
        $includeGroups, $excludeGroups | ? { $_ } | % {
            _getObject -id $_ -type 'Group'
        }
    }
    if ($includeRoles -or $excludeRoles) {
        $includeRoles, $excludeRoles | ? { $_ } | % {
            _getObject -id $_ -type 'Role'
        }
    }
    #endregion validations

    if ($namedLocation) {
        # use existing named location
        $namedLocationObj = Get-AzureADMSNamedLocationPolicy | ? { $_.id -eq $namedLocation -or $_.DisplayName -eq $namedLocation }
        #region validations
        if ($namedLocationObj.count -gt 1) {
            throw "There are multiple matching Named Locations ($($namedLocationObj.count)). Use ID instead."
        }
        if (!$namedLocationObj) {
            throw "Unable to find named location with name/id $namedLocation"
        }
        #endregion validations
    } else {
        # create new named location
        "Creating Named location '_$ruleName'"
        if ($ipRangeIsTrusted) {
            $namedLocationObj = New-AzureADMSNamedLocationPolicy -DisplayName "_$ruleName" -OdataType '#microsoft.graph.ipNamedLocation' -IpRanges $ipRange -IsTrusted:$true
        } else {
            $namedLocationObj = New-AzureADMSNamedLocationPolicy -DisplayName "_$ruleName" -OdataType '#microsoft.graph.ipNamedLocation' -IpRanges $ipRange -IsTrusted:$false
        }
    }
    #endregion named location

    #region conditional policy
    "Creating Conditional Rule '_$ruleName'"

    #region define conditions
    $conditions = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessConditionSet
    $conditions.ClientAppTypes = 'All'

    # conditions apps settings
    $conditions.Applications = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessApplicationCondition
    $conditions.Applications.IncludeApplications = "All"

    # conditions users settings
    $conditions.Users = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessUserCondition
    if ($includeUsers) {
        $conditions.Users.includeUsers = $includeUsers
    }
    if ($excludeUsers) {
        $conditions.Users.excludeUsers = $excludeUsers
    }
    if ($includeGroups) {
        $conditions.Users.includeGroups = $includeGroups
    }
    if ($excludeGroups) {
        $conditions.Users.excludeGroups = $excludeGroups
    }
    if ($includeRoles) {
        $conditions.Users.includeRoles = $includeRoles
    }
    if ($excludeRoles) {
        $conditions.Users.excludeRoles = $excludeRoles
    }

    # conditions location settings
    $conditions.Locations = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessLocationCondition
    Write-Verbose "Using named location $($namedLocationObj.id)"
    $conditions.Locations.IncludeLocations = "All"
    $conditions.Locations.ExcludeLocations = $namedLocationObj.id
    #endregion define conditions

    #region define controls
    $controls = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessGrantControls
    $controls._Operator = "OR"
    $controls.BuiltInControls = "Block"
    #endregion define controls

    if ($justReport) {
        $state = "enabledForReportingButNotEnforced"
    } else {
        $state = "enabled"
    }

    $null = New-AzureADMSConditionalAccessPolicy -DisplayName "_$ruleName" -State $state -Conditions $conditions -GrantControls $controls
    #endregion conditional policy
}