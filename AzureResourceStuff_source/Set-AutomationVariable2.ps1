function Set-AutomationVariable2 {
    <#
    .SYNOPSIS
    Function for setting Azure RunBook variable value by exporting given value using Export-CliXml and saving the text result.

    .DESCRIPTION
    Function for setting Azure RunBook variable value by exporting given value using Export-CliXml and saving the text result.
    Compared to original Set-AutomationVariable this one is able to save original PSObjects as they were and not as Newtonsoft.Json.Linq.
    Variable set using this function has to be read using Get-AutomationVariable2!

    As original Set-AutomationVariable can be used only inside RunBook!

    .PARAMETER name
    Name of the RunBook variable you want to set.

    (to later retrieve such variable, use Get-AutomationVariable2!)

    .PARAMETER value
    Value you want to export to RunBook variable.
    Can be of any type.

    .EXAMPLE
    Set-AutomationVariable2 -name myVar -value @{name = 'John'; surname = 'Doe'}

    # to retrieve the variable
    #$hashTable = Get-AutomationVariable2 -name myVar

    Save given hashtable to variable myVar.

    .NOTES
    Same as original Get-AutomationVariable command, can be used only inside a Runbook!
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $name,

        $value
    )

    if (!(Get-Command 'Get-AzAccessToken -AsSecureString' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -AsSecureString -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "Authentication needed. Please call 'Connect-AzAccount -Identity'."
    }

    if ($value) {
        # in-memory export to CliXml (similar to Export-Clixml)
        $processedValue = [string]([System.Management.Automation.PSSerializer]::Serialize($value, 2))
    } else {
        $processedValue = ''
    }

    try {
        Set-AutomationVariable -Name $name -Value $processedValue -ErrorAction Stop
    } catch {
        throw "Unable to set automation variable $name. Set value is probably too big. Error was: $_"
    }
}