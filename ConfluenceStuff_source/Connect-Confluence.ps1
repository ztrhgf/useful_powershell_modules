function Connect-Confluence {
    <#
    .SYNOPSIS
    Function for connecting to Confluence a.k.a. setting default ApiUri and Credential parameters for every Confluence cmdlet.

    .DESCRIPTION
    Function for connecting to Confluence a.k.a. setting default ApiUri and Credential parameters for every Confluence cmdlet.

    Detects already existing connection and validates provided credentials.

    .PARAMETER baseUri
    Base URI of your cloud Confluence page. It should look like 'https://contoso.atlassian.net/wiki'.

    .PARAMETER credential
    Credentials for connecting to your cloud Confluence API.
    Use login and generated PAT (not password!).

    .PARAMETER pageSize
    The default page size for all commands is 25. Using the -PageSize parameter changes the default for all commands in your current session.

    .EXAMPLE
    Connect-Confluence -baseUri 'https://contoso.atlassian.net/wiki' -credential (Get-Credential)

    Connects to 'https://contoso.atlassian.net/wiki' cloud Confluence base page using provided credentials.

    .NOTES
    Has to be used instead of the official Set-ConfluenceInfo because of scoping problem when setting PSDefaultParameterValues!
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
        [string] $baseUri = $_baseUri,

        [System.Management.Automation.PSCredential] $credential,

        [UInt32] $pageSize
    )

    if (!$baseUri) {
        throw "BaseUri parameter has to be set. Something like 'https://contoso.atlassian.net/wiki'"
    }

    #region helper functions
    # this function originates from the official ConfluencePS module
    # it needs to be call from inside my module so the PSDefaultParameterValues default parameters are set in the correct scope
    function Set-Info {
        [CmdletBinding()]
        param (
            [Parameter(
                HelpMessage = 'Example = https://brianbunke.atlassian.net/wiki (/wiki for Cloud instances)'
            )]
            [uri]$BaseURi,

            [PSCredential]$Credential,

            [UInt32]$PageSize,

            [switch]$PromptCredentials
        )

        BEGIN {

            function Add-ConfluenceDefaultParameter {
                param(
                    [Parameter(Mandatory = $true)]
                    [string]$Command,

                    [Parameter(Mandatory = $true)]
                    [string]$Parameter,

                    [Parameter(Mandatory = $true)]
                    $Value
                )

                PROCESS {
                    Write-Verbose "[$($MyInvocation.MyCommand.Name)] Setting [$command : $parameter] = $value"

                    # Needs to set both global and module scope for the private functions:
                    # http://stackoverflow.com/questions/30427110/set-psdefaultparametersvalues-for-use-within-module-scope
                    $PSDefaultParameterValues["${command}:${parameter}"] = $Value
                    $global:PSDefaultParameterValues["${command}:${parameter}"] = $Value
                }
            }

            $moduleCommands = Get-Command -Module 'ConfluencePS'

            if ($PromptCredentials) {
                $Credential = (Get-Credential)
            }
        }

        PROCESS {
            foreach ($command in $moduleCommands) {

                $parameter = "ApiUri"
                if ($BaseURi -and ($command.Parameters.Keys -contains $parameter)) {
                    Add-ConfluenceDefaultParameter -Command $command.name -Parameter $parameter -Value ($BaseURi.AbsoluteUri.TrimEnd('/') + '/rest/api')
                }

                $parameter = "Credential"
                if ($Credential -and ($command.Parameters.Keys -contains $parameter)) {
                    Add-ConfluenceDefaultParameter -Command $command.name -Parameter $parameter -Value $Credential
                }

                $parameter = "PageSize"
                if ($PageSize -and ($command.Parameters.Keys -contains $parameter)) {
                    Add-ConfluenceDefaultParameter -Command $command.name -Parameter $parameter -Value $PageSize
                }
            }
        }
    }
    #endregion helper functions

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

        # set default Confluence command parameters (ApiUri, Credential,..)
        $param = @{
            BaseURi    = $baseUri
            Credential = $credential
        }
        if ($pageSize) {
            $param.PageSize = $pageSize
        }
        Set-Info @param
    }
}