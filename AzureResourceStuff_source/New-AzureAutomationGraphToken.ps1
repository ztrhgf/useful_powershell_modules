#requires -modules Az.Accounts
function New-AzureAutomationGraphToken {
    <#
    .SYNOPSIS
    Generating auth header for Azure Automation.

    .DESCRIPTION
    Generating auth header for Azure Automation.

    Expects that you are already connected to Azure using Connect-AzAccount command.

    .EXAMPLE
    Connect-AzAccount

    $header = New-AzureAutomationGraphToken

    $body = @{
        "properties" = @{
            "contentLink" = @{
                "uri" = $modulePkgUri
            }
            "version"     = $moduleVersion
        }
    }

    $body = $body | ConvertTo-Json

    Invoke-RestMethod2 -method Put -uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runtimeEnvironments/$runtimeName/packages/$moduleName`?api-version=2023-05-15-preview" -body $body -headers $header

    #>

    $secureToken = (Get-AzAccessToken -ResourceUrl "https://management.azure.com" -AsSecureString -ErrorAction Stop -WarningAction SilentlyContinue).Token
    $token = [PSCredential]::New('dummy', $secureToken).GetNetworkCredential().Password

    if ($token) {
        $header = @{
            'Content-Type'  = 'application/json'
            'Authorization' = "Bearer $token"
        }

        return $header
    } else {
        throw "Unable to obtain token. Are you connected using Connect-AzAccount?"
    }
}