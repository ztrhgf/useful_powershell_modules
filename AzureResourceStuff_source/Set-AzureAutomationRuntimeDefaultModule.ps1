function Set-AzureAutomationRuntimeDefaultModule {
    <#
    .SYNOPSIS
    Function sets Runtime Default Module(s) to given version(s) in selected Azure Automation Account PowerShell Runbook.
    Default modules are currently 'az' and 'azure cli' (just in PowerShell 7.2).

    .DESCRIPTION
    Function sets Runtime Default Module(s) to given version(s) in selected Azure Automation Account PowerShell Runbook.
    Default modules are currently 'az' and 'azure cli' (just in PowerShell 7.2).

    .PARAMETER runtimeName
    Name of the runtime environment you want to update.

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER defaultPackage
    Hashtable where keys are default module names ('az' (both PSHs), 'azure cli' (only in PSH 7.2)) and values are module versions.

    If empty hashtable is provided, currently set default module(s) will be removed (set to 'not configured' in GUI terms).

    .PARAMETER replace
    Switch for replacing current default modules with the ones in 'defaultPackage' parameter.
    Hence what is not defined, will be removed.

    By default default modules not specified in the 'defaultPackage' parameter are ignored.

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    $defaultPackage = @{
        'az'        = '8.3.0'
        'azure cli' = '2.56.0'
    }

    Set-AzureAutomationRuntimeDefaultModule -defaultPackage $defaultPackage

    Set default modules to versions specified in $defaultPackage.
    Missing function arguments like $resourceGroupName or $automationAccountName will be interactively gathered through Out-GridView GUI.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    $defaultPackage = @{
        'azure cli' = '2.56.0'
    }

    Set-AzureAutomationRuntimeDefaultModule -defaultPackage $defaultPackage

    Set default module 'azure cli' to version '2.56.0'.
    In case that any other default module ('az') is set in the modified Runtime too, it will stay intact.
    Missing function arguments like $resourceGroupName or $automationAccountName will be interactively gathered through Out-GridView GUI.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    $defaultPackage = @{
        'azure cli' = '2.56.0'
    }

    Set-AzureAutomationRuntimeDefaultModule -defaultPackage $defaultPackage -replace

    Set default module 'azure cli' to version '2.56.0'.
    In case that any other default module ('az') is set in the modified Runtime too, it will be removed.
    Missing function arguments like $resourceGroupName or $automationAccountName will be interactively gathered through Out-GridView GUI.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Set-AzureAutomationRuntimeDefaultModule -defaultPackage @{}

    All default modules in selected Runtime will be removed.
    Missing function arguments like $resourceGroupName or $automationAccountName will be interactively gathered through Out-GridView GUI.
    #>

    [CmdletBinding()]
    param (
        [string] $runtimeName,

        [string] $resourceGroupName,

        [string] $automationAccountName,

        [Parameter(Mandatory = $true)]
        [hashtable] $defaultPackage,

        [switch] $replace,

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
        $runtimeName = Get-AzureAutomationRuntime -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -header $header -programmingLanguage PowerShell | select -ExpandProperty Name | Out-GridView -OutputMode Single -Title "Select environment you want to process"
    }
    #endregion get missing arguments

    #region checks
    $runtime = Get-AzureAutomationRuntime -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -runtimeName $runtimeName -header $header

    if (!$runtime) {
        throw "Runtime '$runtimeName' wasn't found"
    }

    # what default modules are currently set
    $currentDefaultModule = Get-AzureAutomationRuntimeSelectedDefaultModule -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -runtimeName $runtimeName -header $header

    # check default modules defined in given hashtable vs allowed/currently set ones
    $defaultPackage.GetEnumerator() | % {
        $defaultModuleName = $_.Key
        $defaultModuleVersion = $_.Value

        $currentDefaultModuleVersion = $currentDefaultModule.$defaultModuleName

        if ($defaultModuleVersion -eq $currentDefaultModuleVersion) {
            Write-Warning "Module '$defaultModuleName' already has version $defaultModuleVersion"
        }
    }
    #endregion checks

    #region send web request
    if ($defaultPackage.Count -eq 0) {
        # remove all default modules

        Write-Verbose "Removing all default modules"

        $body = @{
            properties = @{
                runtime         = @{
                    language = $runtime.properties.runtime.language
                    version  = $runtime.properties.runtime.version
                }
                defaultPackages = @{}
            }
        }

        $method = "Put"
    } else {
        # modify current default modules

        Write-Verbose "Replacing current default modules with the defined ones"

        if ($replace) {
            # replace

            $body = @{
                properties = @{
                    runtime         = @{
                        language = $runtime.properties.runtime.language
                        version  = $runtime.properties.runtime.version
                    }
                    defaultPackages = $defaultPackage
                }
            }

            $method = "Put"
        } else {
            # modify

            Write-Verbose "Updating defined default modules"

            $body = @{
                properties = @{
                    defaultPackages = $defaultPackage
                }
            }

            $method = "Patch"
        }
    }

    $body = $body | ConvertTo-Json

    Write-Verbose $body

    Invoke-RestMethod2 -method $method -uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runtimeEnvironments/$runtimeName`?api-version=2023-05-15-preview" -body $body -headers $header
    #endregion send web request
}