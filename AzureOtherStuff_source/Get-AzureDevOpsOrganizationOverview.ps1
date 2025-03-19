function Get-AzureDevOpsOrganizationOverview {
    <#
    .SYNOPSIS
    Function for getting list of all Azure DevOps organizations that uses your AzureAD directory.

    .DESCRIPTION
    Function for getting list of all Azure DevOps organizations that uses your AzureAD directory.
    It is the same data as downloaded csv from https://dev.azure.com/<organizationName>/_settings/organizationAad.

    .PARAMETER tenantId
    (optional) ID of your Azure tenant.
    Of omitted, tenantId from MSAL auth. ticket will be used.

    .EXAMPLE
    Get-AzureDevOpsOrganizationOverview

    Returns all DevOps organizations in your Azure tenant.

    .NOTES
    PowerShell module AzSK.ADO > ContextHelper.ps1 > GetCurrentContext
    https://stackoverflow.com/questions/56355274/getting-oauth-tokens-for-azure-devops-api-consumption
    https://stackoverflow.com/questions/52896114/use-azure-ad-token-to-authenticate-with-azure-devops
    #>

    [CmdletBinding()]
    param (
        [string] $tenantId = $_tenantId
    )

    $header = New-AzureDevOpsAuthHeader -ErrorAction Stop

    if (!$tenantId) {
        throw "'tenantId' parameter cannot be empty"
    }

    # URL retrieved thanks to developer mod at page https://dev.azure.com/<organizationName>/_settings/organizationAad
    Invoke-WebRequest -Uri "https://aexprodweu1.vsaex.visualstudio.com/_apis/EnterpriseCatalog/Organizations?tenantId=$tenantId" -Method get -ContentType "application/json" -Headers $header | select -ExpandProperty content | ConvertFrom-Csv | select @{name = 'OrganizationName'; expression = { $_.'Organization Name' } }, @{name = 'OrganizationId'; expression = { $_.'Organization Id' } }, Url, Owner, @{name = 'ExceptionType'; expression = { $_.'Exception Type' } }, @{name = 'ErrorMessage'; expression = { $_.'Error Message' } } -ExcludeProperty 'Organization Name', 'Organization Id', 'Exception Type', 'Error Message'
}