function Get-AzureADSPPermissions {
    <#
    .SYNOPSIS
        Lists granted delegated (OAuth2PermissionGrants) and application (AppRoleAssignments) permissions.

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
        PS C:\> Get-AzureADSPPermissions -objectId f1c5b03c-6605-46ac-8ddb-453b953af1fc
        Generates report of all permissions granted to app f1c5b03c-6605-46ac-8ddb-453b953af1fc.

    .EXAMPLE
        PS C:\> Get-AzureADSPPermissions | Export-Csv -Path "permissions.csv" -NoTypeInformation
        Generates a CSV report of all permissions granted to all apps.

    .EXAMPLE
        PS C:\> Get-AzureADSPPermissions -ApplicationPermissions -ShowProgress | Where-Object { $_.Permission -eq "Directory.Read.All" }
        Get all apps which have application permissions for Directory.Read.All.

    .EXAMPLE
        PS C:\> Get-AzureADSPPermissions -UserProperties @("DisplayName", "UserPrincipalName", "Mail") -ServicePrincipalProperties @("DisplayName", "AppId")
        Gets all permissions granted to all apps and includes additional properties for users and service principals.

    .NOTES
        https://docs.microsoft.com/en-us/microsoft-365/security/office-365-security/detect-and-remediate-illicit-consent-grants?view=o365-worldwide
    #>

    [CmdletBinding()]
    [Alias("Get-AzureADPSPermissionGrants", "Get-AzureADPSPermissions", "Get-AzureADServicePrincipalPermissions")]
    param(
        [string] $objectId,

        [switch] $DelegatedPermissions,

        [switch] $ApplicationPermissions,

        [string[]] $UserProperties = @("DisplayName"),

        [string[]] $ServicePrincipalProperties = @("DisplayName"),

        [switch] $ShowProgress,

        [int] $PrecacheSize = 999
    )

    Connect-AzureAD2

    $sessionInfo = Get-AzureADCurrentSessionInfo -ea Stop

    # An in-memory cache of objects by {object ID} and by {object class, object ID}
    $script:ObjectByObjectId = @{}
    $script:ObjectByObjectClassId = @{}

    #region helper functions
    # Function to add an object to the cache
    function CacheObject ($Object) {
        if ($Object) {
            if (-not $script:ObjectByObjectClassId.ContainsKey($Object.ObjectType)) {
                $script:ObjectByObjectClassId[$Object.ObjectType] = @{}
            }
            $script:ObjectByObjectClassId[$Object.ObjectType][$Object.ObjectId] = $Object
            $script:ObjectByObjectId[$Object.ObjectId] = $Object
        }
    }

    # Function to retrieve an object from the cache (if it's there), or from Azure AD (if not).
    function GetObjectByObjectId ($ObjectId) {
        if (-not $script:ObjectByObjectId.ContainsKey($ObjectId)) {
            Write-Verbose ("Querying Azure AD for object '{0}'" -f $ObjectId)
            try {
                $object = Get-AzureADObjectByObjectId -ObjectId $ObjectId
                CacheObject -Object $object
            } catch {
                Write-Verbose "Object not found."
            }
        }
        return $script:ObjectByObjectId[$ObjectId]
    }

    # Function to retrieve all OAuth2PermissionGrants, either by directly listing them (-FastMode)
    # or by iterating over all ServicePrincipal objects. The latter is required if there are more than
    # 999 OAuth2PermissionGrants in the tenant, due to a bug in Azure AD.
    function GetOAuth2PermissionGrants ([switch]$FastMode) {
        if ($FastMode) {
            Get-AzureADOAuth2PermissionGrant -All $true
        } else {
            # clone to avoid "An error occurred while enumerating through a collection: Collection was modified; enumeration operation may not execute.."
            $($script:ObjectByObjectClassId['ServicePrincipal'].GetEnumerator().Clone()) | ForEach-Object { $i = 0 } {
                if ($ShowProgress) {
                    Write-Progress -Activity "Retrieving delegated permissions..." `
                        -Status ("Checked {0}/{1} apps" -f $i++, $servicePrincipalCount) `
                        -PercentComplete (($i / $servicePrincipalCount) * 100)
                }

                $client = $_.Value
                Get-AzureADServicePrincipalOAuth2PermissionGrant -ObjectId $client.ObjectId
            }
        }
    }
    #endregion helper functions

    $empty = @{} # Used later to avoid null checks

    # Get ServicePrincipal object(s) and add to the cache
    if ($objectId) {
        Write-Verbose "Retrieving $objectId ServicePrincipal object..."
        Get-AzureADServicePrincipal -ObjectId $objectId | ForEach-Object {
            CacheObject -Object $_
        }
    } else {
        Write-Verbose "Retrieving all ServicePrincipal objects..."
        Get-AzureADServicePrincipal -All $true | ForEach-Object {
            CacheObject -Object $_
        }
    }

    $servicePrincipalCount = $script:ObjectByObjectClassId['ServicePrincipal'].Count

    if ($DelegatedPermissions -or (!$DelegatedPermissions -and !$ApplicationPermissions)) {
        # Get one page of User objects and add to the cache
        if (!$objectId) {
            Write-Verbose ("Retrieving up to {0} User objects..." -f $PrecacheSize)
            Get-AzureADUser -Top $PrecacheSize | Where-Object {
                CacheObject -Object $_
            }

            Write-Verbose "Testing for OAuth2PermissionGrants bug before querying..."
            $fastQueryMode = $false
            try {
                # There's a bug in Azure AD Graph which does not allow for directly listing
                # oauth2PermissionGrants if there are more than 999 of them. The following line will
                # trigger this bug (if it still exists) and throw an exception.
                $null = Get-AzureADOAuth2PermissionGrant -Top 999
                $fastQueryMode = $true
            } catch {
                if ($_.Exception.Message -and $_.Exception.Message.StartsWith("Unexpected end when deserializing array.")) {
                    Write-Verbose ("Fast query for delegated permissions failed, using slow method...")
                } else {
                    throw $_
                }
            }
        } else {
            # false means grants will be searched for just cached service principals i.e. those we actually need
            $fastQueryMode = $false
        }

        # Get all existing OAuth2 permission grants, get the client, resource and scope details
        Write-Verbose "Retrieving OAuth2PermissionGrants..."
        GetOAuth2PermissionGrants -FastMode:$fastQueryMode | ForEach-Object {
            $grant = $_
            if ($grant.Scope) {
                $grant.Scope.Split(" ") | Where-Object { $_ } | ForEach-Object {

                    $scope = $_
                    $resource = GetObjectByObjectId -ObjectId $grant.ResourceId
                    $permission = $resource.OAuth2Permissions | Where-Object { $_.Value -eq $scope }

                    $grantDetails = [ordered]@{
                        "PermissionType"        = "Delegated"
                        "ClientObjectId"        = $grant.ClientId
                        "ResourceObjectId"      = $grant.ResourceId
                        "GrantId"               = $grant.ObjectId
                        "Permission"            = $scope
                        # "PermissionId"          = $permission.Id
                        "PermissionDisplayName" = $permission.AdminConsentDisplayName
                        "PermissionDescription" = $permission.AdminConsentDescription
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
        # clone to avoid "An error occurred while enumerating through a collection: Collection was modified; enumeration operation may not execute.."
        if ($objectId) {
            $spObjectId = $objectId
        } else {
            $spObjectId = $script:ObjectByObjectClassId['ServicePrincipal'].GetEnumerator() | % { $_.Value.ObjectId }
        }
        $spObjectId | ForEach-Object { $i = 0 } {
            Write-Progress "Processing $_ service principal"
            if ($ShowProgress) {
                Write-Progress -Activity "Retrieving application permissions..." `
                    -Status ("Checked {0}/{1} apps" -f $i++, $servicePrincipalCount) `
                    -PercentComplete (($i / $servicePrincipalCount) * 100)
            }

            if ($sessionInfo.Account.Type -eq 'user') {
                $serviceAppRoleAssignedTo = Get-AzureADServiceAppRoleAssignedTo -ObjectId $_ -All:$true
            } else {
                # running under service principal
                #FIXME this is some kind of bug, so probably will be fixed in the future
                # there is super weird bug when under service principal Get-AzureADServiceAppRoleAssignedTo behaves like Get-AzureADServiceAppRoleAssignment and vice versa (https://github.com/Azure/azure-docs-powershell-azuread/issues/766)!!!
                $serviceAppRoleAssignedTo = Get-AzureADServiceAppRoleAssignment -ObjectId $_ -All:$true
            }

            $serviceAppRoleAssignedTo | Where-Object { $_.PrincipalType -eq "ServicePrincipal" } | ForEach-Object {
                $assignment = $_

                $resource = GetObjectByObjectId -ObjectId $assignment.ResourceId
                $appRole = $resource.AppRoles | Where-Object { $_.Id -eq $assignment.Id }

                $grantDetails = [ordered]@{
                    "PermissionType"        = "Application"
                    "ClientObjectId"        = $assignment.PrincipalId
                    "ResourceObjectId"      = $assignment.ResourceId
                    "Permission"            = $appRole.Value
                    # "PermissionId"          = $assignment.appRoleId
                    "PermissionDisplayName" = $appRole.DisplayName
                    "PermissionDescription" = $appRole.Description
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