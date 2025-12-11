function New-PIMResourceEligibleRoleAssignment {
    <#
    .SYNOPSIS
    Creates a PIM eligible role assignment for a specified Azure resource.

    .DESCRIPTION
    This function creates a Privileged Identity Management (PIM) eligible role assignment for a user, group, or service principal
    on a specified Azure resource scope. It uses the Azure Resource Manager API to create role eligibility schedule requests.

    .PARAMETER scope
    The Azure resource scope where the role assignment will be created.
    Examples:
    - Subscription: "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    - Resource Group: "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/myRG"
    - Resource: "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/myRG/providers/Microsoft.Storage/storageAccounts/myStorage"

    .PARAMETER principalId
    The object ID of the principal (user, group, or service principal) to assign the role to.

    .PARAMETER roleName
    The name of the Azure role to assign. Use this parameter if you know the role name (e.g., "Reader", "Contributor", "Owner").
    Either roleName or roleDefinitionId must be specified.

    .PARAMETER roleDefinitionId
    The full resource ID of the role definition.
    Example: "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
    Either roleName or roleDefinitionId must be specified.

    .PARAMETER justification
    Optional justification for the role assignment request.

    .PARAMETER startDateTime
    The start date and time for the role eligibility. Defaults to current time.

    .PARAMETER duration
    The duration of the role eligibility in ISO 8601 duration format.
    Examples: "P365D" (365 days), "P1Y" (1 year), "P90D" (90 days).
    Defaults to "P365D".

    .PARAMETER permanent
    Switch to create a permanent (no expiration) role eligibility assignment.

    .PARAMETER configurePIMSettings
    Switch to run Set-PIMResourceRoleAssignmentSetting with default parameters for the role.
    This configures the PIM policy settings: no justification required, authentication context required, no approval required, permanent assignments allowed.

    .EXAMPLE
    New-PIMResourceEligibleRoleAssignment -scope "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -principalId "11111111-1111-1111-1111-111111111111" -roleName "Reader"

    Creates a Reader eligible role assignment for the specified principal on the subscription with default 365 days duration.

    .EXAMPLE
    New-PIMResourceEligibleRoleAssignment -scope "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/myRG" -principalId "11111111-1111-1111-1111-111111111111" -roleName "Contributor" -duration "P90D" -justification "Project access"

    Creates a Contributor eligible role assignment for 90 days with a justification.

    .EXAMPLE
    New-PIMResourceEligibleRoleAssignment -scope "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -principalId "11111111-1111-1111-1111-111111111111" -roleName "Owner" -permanent

    Creates a permanent Owner eligible role assignment.
    #>

    [CmdletBinding(DefaultParameterSetName = "roleName")]
    param (
        [Parameter(Mandatory = $true)]
        [string] $scope,

        [Parameter(Mandatory = $true)]
        [string] $principalId,

        [Parameter(ParameterSetName = "roleName")]
        [string] $roleName,

        [Parameter(Mandatory = $true, ParameterSetName = "roleDefinitionId")]
        [string] $roleDefinitionId,

        [string] $justification,

        [datetime] $startDateTime = (Get-Date),

        [string] $duration = "P365D",

        [switch] $permanent,

        [switch] $configurePIMSettings
    )

    #region Authentication check
    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction SilentlyContinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand)`: Authentication needed. Please call Connect-AzAccount."
    }
    #endregion Authentication check

    #region Normalize scope
    $scope = $scope.TrimStart('/')
    #endregion Normalize scope

    #region Get role definition ID
    $base = "https://management.azure.com"

    if (!$roleName -and !$roleDefinitionId) {
        # interactive role selection
        $restUri = "$base/$scope/providers/Microsoft.Authorization/roleDefinitions?api-version=2022-04-01"
        $allRolesResponse = (Invoke-AzRestMethod -Uri $restUri -ErrorAction Stop).Content | ConvertFrom-Json

        if (!$allRolesResponse.value -or $allRolesResponse.value.Count -eq 0) {
            throw "$($MyInvocation.MyCommand)`: No roles found at scope '/$scope'."
        }

        $selectedRole = $allRolesResponse.value | Select-Object @{N = 'RoleName'; E = { $_.properties.roleName } }, @{N = 'Description'; E = { $_.properties.description } }, @{N = 'Id'; E = { $_.name } } | Sort-Object RoleName | Out-GridView -Title "Select IAM role for scope: /$scope" -OutputMode Single

        if (!$selectedRole) {
            throw "$($MyInvocation.MyCommand)`: No role selected."
        }

        $roleName = $selectedRole.RoleName
    }

    if ($roleName) {
        $restUri = "$base/$scope/providers/Microsoft.Authorization/roleDefinitions?api-version=2022-04-01&`$filter=roleName eq '$roleName'"
        $roleDefResponse = (Invoke-AzRestMethod -Uri $restUri -ErrorAction Stop).Content | ConvertFrom-Json

        if (!$roleDefResponse.value -or $roleDefResponse.value.Count -eq 0) {
            throw "$($MyInvocation.MyCommand)`: Role '$roleName' not found at scope '/$scope'."
        }

        $roleDefinitionId = $roleDefResponse.value[0].id
    }
    #endregion Get role definition ID

    #region Configure PIM settings if requested
    if ($configurePIMSettings) {
        Write-Verbose "Configuring PIM settings for role '$roleName' at scope '/$scope'"
        Set-PIMResourceRoleAssignmentSetting -scope $scope -roleName $roleName
    }
    #endregion Configure PIM settings if requested

    #region Build request body
    $requestName = [guid]::NewGuid().ToString()

    $scheduleInfo = @{
        startDateTime = $startDateTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    }

    if ($permanent) {
        $scheduleInfo.expiration = @{
            type = "NoExpiration"
        }
    } else {
        $scheduleInfo.expiration = @{
            type     = "AfterDuration"
            duration = $duration
        }
    }

    $requestBody = @{
        properties = @{
            principalId      = $principalId
            roleDefinitionId = $roleDefinitionId
            requestType      = "AdminAssign"
            scheduleInfo     = $scheduleInfo
        }
    }

    if ($justification) {
        $requestBody.properties.justification = $justification
    }
    #endregion Build request body

    #region Send request
    $restUri = "$base/$scope/providers/Microsoft.Authorization/roleEligibilityScheduleRequests/$($requestName)?api-version=2020-10-01"

    $response = Invoke-AzRestMethod -Uri $restUri -Method PUT -Payload ($requestBody | ConvertTo-Json -Depth 10) -ErrorAction Stop

    if ($response.StatusCode -notin 200, 201) {
        $errorContent = $response.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
        $errorMessage = if ($errorContent.error.message) { $errorContent.error.message } else { $response.Content }
        throw "$($MyInvocation.MyCommand)`: Failed to create role eligibility assignment. Status: $($response.StatusCode). Error: $errorMessage"
    }

    $result = $response.Content | ConvertFrom-Json
    #endregion Send request

    #region Return result
    [PSCustomObject]@{
        Id                 = $result.id
        Name               = $result.name
        Status             = $result.properties.status
        PrincipalId        = $result.properties.principalId
        RoleDefinitionId   = $result.properties.roleDefinitionId
        Scope              = $result.properties.scope
        RequestType        = $result.properties.requestType
        StartDateTime      = $result.properties.scheduleInfo.startDateTime
        ExpirationType     = $result.properties.scheduleInfo.expiration.type
        ExpirationDuration = $result.properties.scheduleInfo.expiration.duration
        ExpirationEndDate  = $result.properties.scheduleInfo.expiration.endDateTime
        CreatedOn          = $result.properties.createdOn
    }
    #endregion Return result
}
