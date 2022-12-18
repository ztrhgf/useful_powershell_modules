#requires -module ConfluencePS
function Connect-Confluence {
    <#
    .SYNOPSIS
    Function for connecting to Confluence a.k.a. setting default ApiUri and Credential parameters for every Confluence cmdlet.

    .DESCRIPTION
    Function for connecting to Confluence a.k.a. setting default ApiUri and Credential parameters for every Confluence cmdlet.

    Detects already existing connection. Validates provided credentials.

    .PARAMETER baseUri
    Base URI of your cloud Confluence page. It should look like 'https://contoso.atlassian.net/wiki'.

    .PARAMETER credential
    Credentials for connecting to your cloud Confluence API.
    Use login and generated PAT (not password!).

    .EXAMPLE
    Connect-Confluence -baseUri 'https://contoso.atlassian.net/wiki' -credential (Get-Credential)

    Connects to 'https://contoso.atlassian.net/wiki' cloud Confluence base page using provided credentials.

    .NOTES
    Requires official module ConfluencePS.
    #>

    [CmdletBinding()]
    param (
        [ValidateScript( {
                if ($_ -match "^https://.+/wiki$") {
                    $true
                } else {
                    throw "$_ is not a valid Confluence wiki URL. Should be something like 'https://contoso.atlassian.net/wiki'"
                }
            })]
        [string] $baseUri = $_baseUri
        ,
        [System.Management.Automation.PSCredential] $credential
    )

    if (!$baseUri) {
        throw "BaseUri parameter has to be set. Something like 'https://contoso.atlassian.net/wiki'"
    }

    if (!(Get-Command Set-ConfluenceInfo)) {
        throw "Module ConfluencePS is missing. Unable to authenticate to the Confluence using Set-ConfluenceInfo."
    }

    # check whether already connected
    $setApiUri = $PSDefaultParameterValues.GetEnumerator() | ? Name -EQ "Get-ConfluencePage:ApiUri" | select -ExpandProperty Value

    # authenticate to Confluence
    if ($setApiUri -and $setApiUri -like "$baseUri*") {
        Write-Verbose "Already connected to $baseUri" # I assume that provided credentials are correct
        return
    } else {
        Write-Verbose "Setting ApiUri and Credential parameters for every Confluence cmdlet a.k.a. connecting to Confluence"

        Add-Type -AssemblyName System.Web

        while (!$credential) {
            $credential = Get-Credential -Message "Enter login and API key (instead of password!) for connecting to the Confluence"
        }

        # check whether provided credentials are valid
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        # create basic auth. header
        $Headers = @{"Authorization" = "Basic " + [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($credential.UserName + ":" + [System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($credential.Password)) ))) }
        try {
            $null = Invoke-WebRequest -Method GET -Headers $Headers -Uri "$baseUri/rest/api/content" -UseBasicParsing -ErrorAction Stop
        } catch {
            if ($_ -like "*(401) Unauthorized*") {
                throw "Provided Confluence credentials aren't valid (have you provided PAT instead of password?). Error was: $_"
            } else {
                throw $_
            }
        }

        # set default variables ApiUri and Credential parameters for every Confluence cmdlet
        Set-ConfluenceInfo -BaseURi $baseUri -Credential $credential
    }
}