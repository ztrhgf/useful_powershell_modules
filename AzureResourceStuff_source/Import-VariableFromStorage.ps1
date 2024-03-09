#requires -modules Az.Storage
function Import-VariableFromStorage {
    <#
    .SYNOPSIS
    Function for downloading Azure Blob storage XML file and converting it back to original PowerShell variable.

    .DESCRIPTION
    Function for downloading Azure Blob storage XML file and converting it back to original PowerShell variable.

    Uses native Import-CliXml to convert variable from a XML.

    .PARAMETER fileName
    Name of the file you want to download and convert back to the original variable.
    '.xml' will be appended automatically.

    .PARAMETER resourceGroupName
    Name of the Resource Group Name.

    By default 'PersistentRunbookVariables'

    .PARAMETER storageAccount
    Name of the Storage Account.

    It is case sensitive!

    By default 'persistentvariablesstore'.

    .PARAMETER containerName
    Name of the Storage Account Container.

    By default 'variables'.

    .PARAMETER showProgress
    Switch for showing upload progress.
    Can slow down the upload!

    .EXAMPLE
    Connect-AzAccount

    $processes = Import-VariableFromStorage -fileName "processes"

    .NOTES
    Required permissions: Role 'Storage Account Contributor' has to be granted to the used Storage account
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript( {
                if ($_ -match "\.|\\|/") {
                    throw "$_ is not a valid variable name. Don't use ., \, / chars."
                } else {
                    $true
                }
            })]
        $fileName,

        $resourceGroupName = "PersistentRunbookVariables",


        [ValidateScript( {
                if ($_ -cmatch '^[a-z0-9]+$') {
                    $true
                } else {
                    throw "$_ is not a valid storage account name (does not match expected pattern '^[a-z0-9]+$')."
                }
            })]
        $storageAccount = "persistentvariablesstore",

        $containerName = "variables",

        [switch] $showProgress
    )

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    if (!$showProgress) {
        $ProgressPreference = "silentlycontinue"
    }

    try {
        Write-Verbose "Set Storage Account"
        $null = Set-AzCurrentStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccount -ErrorAction Stop
    } catch {
        if ($_ -like "*does not have authorization to perform action 'Microsoft.Storage/storageAccounts/read' over scope*" -or $_ -like "*'this.Client.SubscriptionId' cannot be null*") {
            throw "Access denied. Role 'Storage Account Contributor' has to be granted to the '$storageAccount' Storage account"
        } else {
            throw $_
        }
    }

    # create temp file
    $cliXmlFile = New-TemporaryFile

    # download blob
    $param = @{
        Blob        = "$fileName.xml"
        Container   = $containerName
        Destination = $cliXmlFile
        Force       = $true
        ErrorAction = "Stop"
    }
    try {
        $null = Get-AzStorageBlobContent @param
    } catch {
        if ($_ -like "*Can not find blob*" ) {
            # probably file is just not yet created (Export-VariableToStorage wasn't run yet)
            Write-Warning $_

            # remove temp file
            $null = Remove-Item $cliXmlFile -Force

            return
        } else {
            throw $_
        }
    }

    # convert xml back to original object
    $cliXmlFile | Import-Clixml

    # remove temp file
    $null = Remove-Item $cliXmlFile -Force
}