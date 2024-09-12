#requires -modules Az.Storage
function Export-VariableToStorage {
    <#
    .SYNOPSIS
    Function for saving PowerShell variable as XML file in Azure Blob storage.
    That way you can easily later download & convert it back to original state using Import-VariableFromStorage.

    .DESCRIPTION
    Function for saving PowerShell variable as XML file in Azure Blob storage.
    That way you can easily later download & convert it back to original state using Import-VariableFromStorage.

    Uses native Export-CliXml to convert variable to a XML.

    .PARAMETER value
    Variable you want to save to blob storage.

    .PARAMETER fileName
    Name that will be used for uploaded file.
    To place file to the folder structure, give name like "folder\file".
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

    .PARAMETER standardBlobTier
    Tier type.

    By default 'Hot'.

    .PARAMETER showProgress
    Switch for showing upload progress.
    Can slow down the upload!

    .EXAMPLE
    Connect-AzAccount

    $processes = Get-Process

    Export-VariableToStorage -value $processes -fileName "processes"

    Converts $processes to XML (using Export-CliXml) and saves it to the default Storage Account and default container as a file "processes.xml".

    .EXAMPLE
    Connect-AzAccount

    $processes = Get-Process

    Export-VariableToStorage -value $processes -fileName "variables\processes"

    Converts $processes to XML (using Export-CliXml) and saves it to the default Storage Account and default container to folder "variables" as a file "processes.xml".

    .NOTES
    Required permissions: Role 'Storage Account Contributor' has to be granted to the used Storage account
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $value,

        [Parameter(Mandatory = $true)]
        [ValidateScript( {
                if ($_ -match "\.|/") {
                    throw "$_ is not a valid variable name. Don't use ., / chars."
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

        [ValidateSet('Hot', 'Cold')]
        [string] $standardBlobTier = "Hot",

        [switch] $showProgress
    )

    if (!(Get-Command 'Get-AzAccessToken -AsSecureString' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -AsSecureString -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
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
    $value | Export-Clixml $CliXmlFile.FullName

    if (!$showProgress) {
        $ProgressPreference = "silentlycontinue"
    }

    # upload the file
    $param = @{
        File             = $cliXmlFile
        Container        = $containerName
        Blob             = "$fileName.xml"
        StandardBlobTier = $standardBlobTier
        Force            = $true
        ErrorAction      = "Stop"
    }
    Write-Verbose "Upload variable xml representation to the '$($fileName.xml)' file"
    $null = Set-AzStorageBlobContent @param

    # remove temp file
    Remove-Item $cliXmlFile -Force
}