function New-AzureAutomationRuntimeZIPModule {
    <#
    .SYNOPSIS
    Function imports given archived PowerShell module (as a ZIP file) to the given Automation Runtime Environment.

    .DESCRIPTION
    Function imports given archived PowerShell module (as a ZIP file) to the given Automation Runtime Environment.

    .PARAMETER runtimeName
    Name of the runtime environment you want to retrieve.

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER moduleZIPPath
    Path to the ZIP file containing archived module folder.

    Name of the ZIP will be used as name of the imported module!

    If the module folder contains psd1 manifest file, specified version will be set automatically as a module version in Runtime modules list. Otherwise the version will be 'unknown'.

    .PARAMETER dontWait
    Switch for not waiting on module import to finish.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    New-AzureAutomationRuntimeZIPModule -moduleZIPPath "C:\DATA\helperFunctions.zip"

    Imports module 'helperFunctions' to the specified Automation runtime.

    If module exists, it will be replaced, if it is not, it will be added.

    If module contains psd1 manifest file with specified version, such version will be set as module version in the Runtime module list. Otherwise the version will be 'unknown'.

    Missing function arguments like $resourceGroupName or $automationAccountName will be interactively gathered through Out-GridView GUI.
    #>

    [CmdletBinding()]
    [Alias("Set-AzureAutomationRuntimeZIPModule")]
    param (
        [string] $runtimeName,

        [string] $resourceGroupName,

        [string] $automationAccountName,

        [Parameter(Mandatory = $true)]
        [string] $moduleZIPPath,

        [switch] $dontWait
    )

    $ErrorActionPreference = "Stop"
    $InformationPreference = "Continue"

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    #region get missing arguments
    $moduleName = (Split-Path $moduleZIPPath -Leaf) -replace "\.zip$"

    $subscriptionId = (Get-AzContext).Subscription.Id

    # create auth token
    $header = New-AzureAutomationGraphToken

    while (!$resourceGroupName) {
        $resourceGroupName = Get-AzResourceGroup | select -ExpandProperty ResourceGroupName | Out-GridView -OutputMode Single -Title "Select resource group you want to process"
    }

    while (!$automationAccountName) {
        $automationAccountName = Get-AzAutomationAccount -ResourceGroupName $resourceGroupName | select -ExpandProperty AutomationAccountName | Out-GridView -OutputMode Single -Title "Select automation account you want to process"
    }

    while (!$runtimeName) {
        $runtimeName = Get-AzureAutomationRuntime -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -programmingLanguage PowerShell -runtimeSource Custom -header $header | select -ExpandProperty Name | Out-GridView -OutputMode Single -Title "Select environment you want to process"
    }
    #endregion get missing arguments

    #region get upload URL
    Write-Verbose "Getting upload URL"
    $body = @{
        "assetType" = "Module"
    }
    $uploadUrl = Invoke-RestMethod -Method POST "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/generateSasLinkUri?api-version=2021-04-01" -Headers $header -Body ($body | ConvertTo-Json)
    Write-Verbose $uploadUrl
    #endregion get upload URL

    #region upload module (ZIP) using upload URL
    $uploadHeader = @{
        'X-Ms-Blob-Type'                = "BlockBlob"
        'X-Ms-Blob-Content-Disposition' = "filename=`"$(Split-Path $moduleZIPPath -Leaf)`""
        'X-Ms-Blob-Content-Type'        = 'application/x-gzip'
    }

    Write-Information "Uploading ZIP file"
    Invoke-RestMethod -Method PUT $uploadUrl -InFile $moduleZIPPath -Headers $uploadHeader
    #endregion upload module (ZIP) using upload URL

    #region importing uploaded module to the runtime
    $body = @{
        "properties" = @{
            "contentLink" = @{
                "uri" = $uploadUrl
            }
            "version"     = "" # ignored when uploading a ZIP
        }
    }
    $body = $body | ConvertTo-Json

    Write-Information "Importing uploaded module (ZIP) to the Runtime"
    Invoke-RestMethod -Method PUT "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runtimeEnvironments/$runtimeName/packages/$moduleName`?api-version=2023-05-15-preview" -Body $body -Headers $header
    #endregion importing uploaded module to the runtime

    #region output dots while waiting on import to finish
    if ($dontWait) {
        Write-Information "Skipping waiting on the ZIP file import to finish"
        return
    } else {
        $i = 0
        Write-Verbose "."
        do {
            Start-Sleep 5

            if ($i % 3 -eq 0) {
                Write-Verbose "."
            }

            ++$i
        } while (!($requiredModule = Get-AzureAutomationRuntimeCustomModule -automationAccountName $automationAccountName -ResourceGroup $resourceGroupName -runtimeName $runtimeName -moduleName $moduleName -header $header | ? { $_.Properties.ProvisioningState -in "Succeeded", "Failed" }))
    }
    #endregion output dots while waiting on import to finish

    if ($requiredModule.Properties.ProvisioningState -ne "Succeeded") {
        Write-Error "Import failed. Check Azure Portal >> Automation Account >> Runtime Environments >> $runtimeName >> $moduleName details to get the reason."
    } else {
        Write-Information "DONE"
    }
}