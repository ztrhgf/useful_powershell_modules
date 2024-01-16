function Get-AzureServicePrincipalPermissions {
    <#
    .SYNOPSIS
        Lists granted delegated (OAuth2PermissionGrants) and application (AppRoleAssignments) permissions of the service principal (ent. app).

    .PARAMETER objectId
        Service principal objectId. If not specified, all service principals will be processed.

    .PARAMETER DelegatedPermissions
        If set, will return delegated permissions. If neither this switch nor the ApplicationPermissions switch is set,
        both application and delegated permissions will be returned.

    .PARAMETER ApplicationPermissions
        If set, will return application permissions. If neither this switch nor the DelegatedPermissions switch is set,
        both application and delegated permissions will be returned.

    .PARAMETER UserProperties
        The list of properties of user objects to include in the output. Defaults to DisplayName only.

    .PARAMETER ServicePrincipalProperties
        The list of properties of service principals (i.e. apps) to include in the output. Defaults to DisplayName only.

    .PARAMETER ShowProgress
        Whether or not to display a progress bar when retrieving application permissions (which could take some time).

    .PARAMETER PrecacheSize
        The number of users to pre-load into a cache. For tenants with over a thousand users,
        increasing this may improve performance of the script.
    .EXAMPLE
        PS C:\> Get-AzureServicePrincipalPermissions -objectId f1c5b03c-6605-46ac-8ddb-453b953af1fc
        Generates report of all permissions granted to app f1c5b03c-6605-46ac-8ddb-453b953af1fc.

    .EXAMPLE
        PS C:\> Get-AzureServicePrincipalPermissions | Export-Csv -Path "permissions.csv" -NoTypeInformation
        Generates a CSV report of all permissions granted to all apps.

    .EXAMPLE
        PS C:\> Get-AzureServicePrincipalPermissions -ApplicationPermissions -ShowProgress | Where-Object { $_.Permission -eq "Directory.Read.All" }
        Get all apps which have application permissions for Directory.Read.All.

    .EXAMPLE
        PS C:\> Get-AzureServicePrincipalPermissions -UserProperties @("DisplayName", "UserPrincipalName", "Mail") -ServicePrincipalProperties @("DisplayName", "AppId")
        Gets all permissions granted to all apps and includes additional properties for users and service principals.

    .NOTES
        https://docs.microsoft.com/en-us/microsoft-365/security/office-365-security/detect-and-remediate-illicit-consent-grants?view=o365-worldwide
    #>

    [CmdletBinding()]
    [Alias("Get-AzureSPPermissions")]
    param(
        [string] $objectId,

        [switch] $DelegatedPermissions,

        [switch] $ApplicationPermissions,

        [string[]] $UserProperties = @("DisplayName"),

        [string[]] $ServicePrincipalProperties = @("DisplayName"),

        [switch] $ShowProgress,

        [int] $PrecacheSize = 999
    )

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): The context is invalid. Please login using Connect-MgGraph."
    }

    # An in-memory cache of objects by {object ID} and by {object class, object ID}
    $script:ObjectByObjectId = @{}
    $script:ObjectByObjectClassId = @{}

    #region helper functions
    # Function to add an object to the cache
    function CacheObject ($Object, $ObjectType) {
        if ($Object) {
            if (-not $script:ObjectByObjectClassId.ContainsKey($ObjectType)) {
                $script:ObjectByObjectClassId[$ObjectType] = @{}
            }
            $script:ObjectByObjectClassId[$ObjectType][$Object.Id] = $Object
            $script:ObjectByObjectId[$Object.Id] = $Object
        }
    }

    # Function to retrieve an object from the cache (if it's there), or from Azure AD (if not).
    function GetObjectByObjectId ($ObjectId) {
        if (-not $script:ObjectByObjectId.ContainsKey($ObjectId)) {
            Write-Verbose ("Querying Azure AD for object '{0}'" -f $ObjectId)
            try {
                $object = Get-MgDirectoryObjectById -Ids $ObjectId | Expand-MgAdditionalProperties
                CacheObject -Object $object -ObjectType $object.ObjectType
            } catch {
                Write-Verbose "Object not found."
                $_
            }
        }
        return $script:ObjectByObjectId[$ObjectId]
    }

    # Function to retrieve OAuth2PermissionGrants
    function GetOAuth2PermissionGrants {
        if ($objectId) {
            Get-MgServicePrincipalOauth2PermissionGrant -ServicePrincipalId $objectId -All
        } else {
            Get-MgOauth2PermissionGrant -All
        }
    }
    #endregion helper functions

    $empty = @{} # Used later to avoid null checks

    # Get ServicePrincipal object(s) and add to the cache
    if ($objectId) {
        Write-Verbose "Retrieving $objectId ServicePrincipal object..."
        Get-MgServicePrincipal -ServicePrincipalId $objectId | ForEach-Object {
            CacheObject -Object $_ -ObjectType "servicePrincipal"
        }
    } else {
        Write-Verbose "Retrieving all ServicePrincipal objects..."
        Get-MgServicePrincipal -All | ForEach-Object {
            CacheObject -Object $_ -ObjectType "servicePrincipal"
        }
    }

    $servicePrincipalCount = $script:ObjectByObjectClassId['ServicePrincipal'].Count

    if ($DelegatedPermissions -or (!$DelegatedPermissions -and !$ApplicationPermissions)) {
        # Get one page of User objects and add to the cache
        if (!$objectId) {
            Write-Verbose ("Retrieving up to {0} User objects..." -f $PrecacheSize)
            Get-MgUser -Top $PrecacheSize | Where-Object {
                CacheObject -Object $_ -ObjectType "user"
            }
        }

        # Get all existing OAuth2 permission grants, get the client, resource and scope details
        Write-Verbose "Retrieving OAuth2PermissionGrants..."

        GetOAuth2PermissionGrants | ForEach-Object {
            $grant = $_
            if ($grant.Scope) {
                $grant.Scope.Split(" ") | Where-Object { $_ } | ForEach-Object {
                    $scope = $_
                    $resource = GetObjectByObjectId -ObjectId $grant.ResourceId

                    $permission = $resource.oauth2PermissionScopes | Where-Object { $_.value -eq $scope }

                    $grantDetails = [ordered]@{
                        "PermissionType"        = "Delegated"
                        "ClientObjectId"        = $grant.ClientId
                        "ResourceObjectId"      = $grant.ResourceId
                        "GrantId"               = $grant.Id
                        "Permission"            = $scope
                        # "PermissionId"          = $permission.Id
                        "PermissionDisplayName" = $permission.adminConsentDisplayName
                        "PermissionDescription" = $permission.adminConsentDescription
                        "ConsentType"           = $grant.ConsentType
                        "PrincipalObjectId"     = $grant.PrincipalId
                    }

                    # Add properties for client and resource service principals
                    if ($ServicePrincipalProperties.Count -gt 0) {

                        $client = GetObjectByObjectId -ObjectId $grant.ClientId
                        $resource = GetObjectByObjectId -ObjectId $grant.ResourceId

                        $insertAtClient = 2
                        $insertAtResource = 3
                        foreach ($propertyName in $ServicePrincipalProperties) {
                            $grantDetails.Insert($insertAtClient++, "Client$propertyName", $client.$propertyName)
                            $insertAtResource++
                            $grantDetails.Insert($insertAtResource, "Resource$propertyName", $resource.$propertyName)
                            $insertAtResource ++
                        }
                    }

                    # Add properties for principal (will all be null if there's no principal)
                    if ($UserProperties.Count -gt 0) {

                        $principal = $empty
                        if ($grant.PrincipalId) {
                            $principal = GetObjectByObjectId -ObjectId $grant.PrincipalId
                        }

                        foreach ($propertyName in $UserProperties) {
                            $grantDetails["Principal$propertyName"] = $principal.$propertyName
                        }
                    }

                    New-Object PSObject -Property $grantDetails
                }
            }
        }
    }

    if ($ApplicationPermissions -or (!$DelegatedPermissions -and !$ApplicationPermissions)) {
        # Iterate over all ServicePrincipal objects and get app permissions
        Write-Verbose "Retrieving AppRoleAssignments..."

        if ($objectId) {
            $spObjectId = $objectId
        } else {
            $spObjectId = $script:ObjectByObjectClassId['ServicePrincipal'].GetEnumerator() | % { $_.Value.Id }
        }

        $spObjectId | ForEach-Object { $i = 0 } {
            Write-Progress "Processing $_ service principal"
            if ($ShowProgress) {
                Write-Progress -Activity "Retrieving application permissions..." `
                    -Status ("Checked {0}/{1} apps" -f $i++, $servicePrincipalCount) `
                    -PercentComplete (($i / $servicePrincipalCount) * 100)
            }

            $serviceAppRoleAssignedTo = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $_ -All

            $serviceAppRoleAssignedTo | Where-Object { $_.PrincipalType -eq "ServicePrincipal" } | ForEach-Object {
                $assignment = $_

                $resource = GetObjectByObjectId -ObjectId $assignment.ResourceId
                $appRole = $resource.AppRoles | Where-Object { $_.id -eq $assignment.AppRoleId }

                $grantDetails = [ordered]@{
                    "PermissionType"        = "Application"
                    "ClientObjectId"        = $assignment.PrincipalId
                    "ResourceObjectId"      = $assignment.ResourceId
                    "Permission"            = $appRole.value
                    # "PermissionId"          = $assignment.appRoleId
                    "PermissionDisplayName" = $appRole.displayName
                    "PermissionDescription" = $appRole.description
                }

                # Add properties for client and resource service principals
                if ($ServicePrincipalProperties.Count -gt 0) {

                    $client = GetObjectByObjectId -ObjectId $assignment.PrincipalId

                    $insertAtClient = 2
                    $insertAtResource = 3
                    foreach ($propertyName in $ServicePrincipalProperties) {
                        $grantDetails.Insert($insertAtClient++, "Client$propertyName", $client.$propertyName)
                        $insertAtResource++
                        $grantDetails.Insert($insertAtResource, "Resource$propertyName", $resource.$propertyName)
                        $insertAtResource ++
                    }
                }

                New-Object PSObject -Property $grantDetails
            }
        }
    }
}