# TODO upload WHL souboru pro PYTHON a zip pro PSH
function Set-AzureAutomationRuntimeModule {
    <#
    .SYNOPSIS
    Function add/replace selected module in specified Azure Automation runtime by importing it from the PowerShell Gallery.

    .DESCRIPTION
    Function add/replace selected module in specified Azure Automation runtime by importing it from the PowerShell Gallery.

    If module exists, it will be replaced by selected version, if it is not, it will be added.

    .PARAMETER runtimeName
    Name of the runtime environment you want to retrieve.

    If not provided, all runtimes will be returned.

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER moduleName
    Name of the module you want to add/(replace by other version).

    .PARAMETER moduleVersion
    Module version.

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Set-AzureAutomationRuntimeModule -moduleName CommonStuff -moduleVersion 1.0.18

    Add module CommonStuff with version 1.0.18 to specified Automation runtime.
    If module exists, it will be replaced by selected version, if it is not, it will be added.

    Missing function arguments like $resourceGroupName or $automationAccountName will be interactively gathered through Out-GridView GUI.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Set-AzureAutomationRuntimeModule -resourceGroupName "AdvancedLoggingRG" -automationAccountName "EnableO365AdvancedLogging" -runtimeName Custom_PSH_51 -moduleName CommonStuff -moduleVersion 1.0.18

    Add module CommonStuff with version 1.0.18 to specified Automation runtime.
    If module exists, it will be replaced by selected version, if it is not, it will be added.
    #>

    [CmdletBinding()]
    [Alias("Update-AzureAutomationRuntimeModule")]
    param (
        [string] $runtimeName,

        [string] $resourceGroupName,

        [string] $automationAccountName,

        [Parameter(Mandatory = $true)]
        [string] $moduleName,

        [Parameter(Mandatory = $true)]
        [string] $moduleVersion,

        [hashtable] $header
    )

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    #region get missing arguments
    if (!$header) {
        $header = New-AzureAutomationGraphToken
    }

    $subscriptionId = (Get-AzContext).Subscription.Id

    while (!$resourceGroupName) {
        $resourceGroupName = Get-AzResourceGroup | select -ExpandProperty ResourceGroupName | Out-GridView -OutputMode Single -Title "Select resource group you want to process"
    }

    while (!$automationAccountName) {
        $automationAccountName = Get-AzAutomationAccount -ResourceGroupName $resourceGroupName | select -ExpandProperty AutomationAccountName | Out-GridView -OutputMode Single -Title "Select automation account you want to process"
    }

    while (!$runtimeName) {
        $runtimeName = Get-AzureAutomationRuntimeEnvironment -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -header $header -programmingLanguage PowerShell | select -ExpandProperty Name | Out-GridView -OutputMode Single -Title "Select environment you want to process"
    }
    #endregion get missing arguments

    $modulePkgUri = "https://devopsgallerystorage.blob.core.windows.net/packages/$($moduleName.ToLower()).$moduleVersion.nupkg"

    $pkgStatus = Invoke-WebRequest -Uri $modulePkgUri -SkipHttpErrorCheck
    if ($pkgStatus.StatusCode -ne 200) {
        throw "Module $moduleName (version $moduleVersion) doesn't exist in PSGallery. Error was $($pkgStatus.StatusDescription)"
    }

    #region send web request
    $body = @{
        "properties" = @{
            "contentLink" = @{
                "uri" = $modulePkgUri
            }
            "version"     = $moduleVersion
        }
    }

    $body = $body | ConvertTo-Json

    Write-Verbose $body

    Invoke-RestMethod2 -method Put -uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runtimeEnvironments/$runtimeName/packages/$moduleName`?api-version=2023-05-15-preview" -body $body -headers $header
    #endregion send web request
}