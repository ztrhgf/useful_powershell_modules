function Get-AutomationVariable2 {
    <#
    .SYNOPSIS
    Function for getting Azure RunBook variable exported using Set-AutomationVariable2 function (a.k.a. using Export-CliXml).

    .DESCRIPTION
    Function for getting Azure RunBook variable exported using Set-AutomationVariable2 function (a.k.a. using Export-CliXml).
    Compared to original Get-AutomationVariable this one is able to get original PSObjects as they were and not as Newtonsoft.Json.Linq.

    As original Get-AutomationVariable can be used only inside RunBook!

    .PARAMETER name
    Name of the RunBook variable you want to retrieve.

    (such variable had to be set using Set-AutomationVariable2!)

    .EXAMPLE
    # save given hashtable to variable myVar
    #Set-AutomationVariable2 -name myVar -value @{name = 'John'; surname = 'Doe'}

    Get-AutomationVariable2 myVar

    Get variable myVar.

    .NOTES
    Same as original Get-AutomationVariable command, can be used only inside a Runbook!
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $name
    )

    if (!(Get-Command 'Get-AzAccessToken -AsSecureString' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -AsSecureString -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "Authentication needed. Please call 'Connect-AzAccount -Identity'."
    }

    try {
        [string] $xml = Get-AutomationVariable -Name $name -ErrorAction Stop
    } catch {
        Write-Error $_
        return
    }

    if ($xml) {
        # in-memory import of CliXml string (similar to Import-Clixml)
        [System.Management.Automation.PSSerializer]::Deserialize($xml)
    } else {
        return
    }
}