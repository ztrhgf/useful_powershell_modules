function Get-PIMMyActiveDirectoryRole {
    <#
    .SYNOPSIS
    Retrieves the currently active Azure Directory roles assigned to the current user (permanent and via Privileged Identity Management (PIM)).

    .DESCRIPTION
    Retrieves the currently active Azure Directory roles assigned to the current user (permanent and via Privileged Identity Management (PIM)).
    It helps users identify their active roles and manage their access accordingly.

    .EXAMPLE
    Get-PIMMyActiveDirectoryRole

    This example retrieves all currently active Azure Directory roles assigned to the current user.
    #>

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-MgGraph."
    }

    $batchRequest = [System.Collections.Generic.List[Object]]::new()

    $batchRequest.Add((New-GraphBatchRequest -url "roleManagement/directory/roleDefinitions?`$select=description,displayName,id" -id directoryRoleDefinition))
    $batchRequest.Add((New-GraphBatchRequest -url "roleManagement/directory/roleAssignmentSchedules/filterByCurrentUser(on='principal')" -id myDirectoryRole))

    $batchResponse = Invoke-GraphBatchRequest -batchRequest $batchRequest

    $roleDefinition = $batchResponse | Where-Object { $_.RequestId -eq "directoryRoleDefinition" }
    $myDirectoryRole = $batchResponse | Where-Object { $_.RequestId -eq "myDirectoryRole" }

    $myDirectoryRole | Select-Object @{Name = 'RoleName'; Expression = { $roleId = $_.roleDefinitionId; ($roleDefinition | Where-Object Id -EQ $roleId).DisplayName } }, * -ExcludeProperty RequestId
}