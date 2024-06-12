function Copy-AzureAutomationRuntime {
    <#
    .SYNOPSIS
    Make a copy of existing Azure Automation Runtime Environment.

    .DESCRIPTION
    Make a copy of existing Azure Automation Runtime Environment.

    Copy will have:
    - same default and custom modules
    - same language, version and description

    Copy is by default created in the same Automation Account, but can be placed in different one too.

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER runtimeName
    Name of the runtime to copy.

    .PARAMETER newResourceGroupName
    Destination Resource group name.
    If not specified, source one will be used.

    .PARAMETER newAutomationAccountName
    Destination Automation account name.

    If not specified, source one will be used.

    .PARAMETER newRuntimeName
    Name of the new runtime.

    If not specified, it will be "copy_<sourceRuntimeName>".

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Copy-AzureAutomationRuntime

    Creates a copy of the selected Runtime in the same Automation Account. It will be named like "copy_<sourceRuntimeName>".

    Missing function arguments like $runtimeName, $resourceGroupName or $automationAccountName will be interactively gathered through Out-GridView GUI.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Copy-AzureAutomationRuntime -runtimeName "Runtime51" -newRuntimeName "Runtime51_v2" -resourceGroupName "AdvancedLoggingRG" -automationAccountName "EnableO365AdvancedLogging"

    Creates a copy of the selected Runtime in the same Automation Account.
    #>

    [CmdletBinding()]
    param (
        [string] $resourceGroupName,

        [string] $automationAccountName,

        [string] $runtimeName,

        [string] $newResourceGroupName,

        [string] $newAutomationAccountName,

        [string] $newRuntimeName,

        [hashtable] $header
    )

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    if (($newResourceGroupName -and !$newAutomationAccountName) -or (!$newResourceGroupName -and $newAutomationAccountName)) {
        throw "Either both 'newResourceGroupName' and 'newAutomationAccountName' parameters have to be set or neither of them"
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
        $runtimeName = Get-AzureAutomationRuntime -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -programmingLanguage PowerShell -runtimeSource Custom -header $header | select -ExpandProperty Name | Out-GridView -OutputMode Single -Title "Select environment you want to process"
    }
    #endregion get missing arguments

    # get all custom modules
    Write-Verbose "Get Runtime '$runtimeName' custom modules"
    $customModule = Get-AzureAutomationRuntimeCustomModule -runtimeName $runtimeName -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -header $header -ErrorAction Stop

    # get all default modules
    Write-Verbose "Get Runtime '$runtimeName' default modules"
    $defaultPackageObj = Get-AzureAutomationRuntimeSelectedDefaultModule -runtimeName $runtimeName -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -header $header -ErrorAction Stop

    # get runtime language, version, description
    Write-Verbose "Get Runtime '$runtimeName' information"
    $runtime = Get-AzureAutomationRuntime -runtimeName $runtimeName -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -header $header -ErrorAction Stop

    $runtimeLanguage = $runtime.properties.runtime.language
    $runtimeVersion = $runtime.properties.runtime.version
    $runtimeDescription = $runtime.properties.description

    #region create new runtime with language, version and default modules
    if (!$newResourceGroupName) {
        $newResourceGroupName = $resourceGroupName
    }
    if (!$newAutomationAccountName) {
        $newAutomationAccountName = $automationAccountName
    }
    if (!$newRuntimeName) {
        $newRuntimeName = "copy_$runtimeName"
    }

    if ($defaultPackageObj) {
        # transform $defaultPackageObj to hashtable
        $defaultPackage = @{}

        $moduleNameList = $defaultPackageObj | Get-Member -MemberType NoteProperty | select -ExpandProperty Name
        $moduleNameList | % {
            $defaultPackage.$_ = $defaultPackageObj.$_
        }
    } else {
        # no default modules needed
        $defaultPackage = @{}
    }

    "Creating new runtime '$newRuntimeName'"
    $null = New-AzureAutomationRuntime -runtimeName $newRuntimeName -resourceGroupName $newResourceGroupName -automationAccountName $newAutomationAccountName -runtimeLanguage $runtimeLanguage -runtimeVersion $runtimeVersion -defaultPackage $defaultPackage -description $runtimeDescription -header $header
    #region create new runtime with language, version and default modules

    # add custom modules
    foreach ($custModule in $customModule) {
        $name = $custModule.name
        $version = $custModule.properties.version
        $provisioningState = $custModule.properties.provisioningState

        if ($provisioningState -ne 'Succeeded') {
            Write-Verbose "Skipping adding custom module '$name', because it is in '$provisioningState' provisioning state"
            continue
        }

        "Adding custom module '$name' $version"
        New-AzureAutomationRuntimeModule -runtimeName $newRuntimeName -resourceGroupName $newResourceGroupName -automationAccountName $newAutomationAccountName -moduleName $name -moduleVersion $version -header $header
    }
}

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

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
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

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
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

function Get-AzureAutomationRunbookRuntime {
    <#
    .SYNOPSIS
    Get Runtime Environment name of the selected Azure Automation Account Runbook.

    .DESCRIPTION
    Get Runtime Environment name of the selected Azure Automation Account Runbook.

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER runbookName
    Runbook name.

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Get-AzureAutomationRunbookRuntime

    Get name of the Runtime Environment used in selected Runbook.
    Missing function arguments like $resourceGroupName, $automationAccountName or $runbookName will be interactively gathered through Out-GridView GUI.
    #>

    [CmdletBinding()]
    param (
        [string] $resourceGroupName,

        [string] $automationAccountName,

        [string] $runbookName,

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

    while (!$runbookName) {
        $runbookName = Get-AzAutomationRunbook -AutomationAccountName $automationAccountName -ResourceGroupName $resourceGroupName | select -ExpandProperty Name | Out-GridView -OutputMode Single -Title "Select runbook you want to process"
    }
    #endregion get missing arguments

    Invoke-RestMethod2 "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runbooks/$runbookName`?api-version=2023-05-15-preview" -headers $header | select -ExpandProperty properties | select -ExpandProperty runtimeEnvironment
}

function Get-AzureAutomationRuntime {
    <#
    .SYNOPSIS
    Function returns selected/all Azure Automation runtime environment/s.

    .DESCRIPTION
    Function returns selected/all Azure Automation runtime environment/s.

    .PARAMETER runtimeName
    Name of the runtime environment you want to retrieve.

    If not provided, all runtimes will be returned.

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER programmingLanguage
    Filter runtimes to just ones using selected language.

    Possible values: All, PowerShell, Python.

    By default: All

    .PARAMETER runtimeSource
    Filter runtimes by source of creation.

    Possible values: All, Default, Custom.

    By default: All

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Get-AzureAutomationRuntime -resourceGroupName "AdvancedLoggingRG" -automationAccountName "EnableO365AdvancedLogging"

    Get all Automation Runtimes in given Automation Account.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Get-AzureAutomationRuntime -programmingLanguage PowerShell -runtimeSource Custom

    Get just PowerShell based manually created Automation Runtimes in given Automation Account.

    Missing function arguments like $resourceGroupName or $automationAccountName will be interactively gathered through Out-GridView GUI.

    .NOTES
    https://learn.microsoft.com/en-us/rest/api/automation/runtime-environments/get?view=rest-automation-2023-05-15-preview&tabs=HTTP
    #>

    [CmdletBinding()]
    param (
        [string] $runtimeName,

        [string] $resourceGroupName,

        [string] $automationAccountName,

        [ValidateSet('PowerShell', 'Python', 'All')]
        [string] $programmingLanguage = 'All',

        [ValidateSet('Default', 'Custom', 'All')]
        [string] $runtimeSource = 'All',

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
    #endregion get missing arguments

    $result = Invoke-RestMethod2 -method Get -uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runtimeEnvironments/$runtimeName/?api-version=2023-05-15-preview" -headers $header -ErrorAction $ErrorActionPreference

    #region filter results
    if ($result -and $programmingLanguage -ne 'All') {
        $result = $result | ? { $_.Properties.Runtime.language -eq $programmingLanguage }
    }

    if ($result -and $runtimeSource -ne 'All') {
        switch ($runtimeSource) {
            'Default' {
                $result = $result | ? { $_.Properties.Description -like "System-generated Runtime Environment for your Automation account with Runtime language:*" }
            }

            'Custom' {
                $result = $result | ? { $_.Properties.Description -notlike "System-generated Runtime Environment for your Automation account with Runtime language:*" }
            }

            default {
                throw "Undefined runtimeSource ($runtimeSource)"
            }
        }
    }
    #endregion filter results

    $result
}

function Get-AzureAutomationRuntimeAvailableDefaultModule {
    <#
    .SYNOPSIS
    Function returns default modules (Az) available to select in selected/all PSH runtime(s).

    .DESCRIPTION
    Function returns default modules (Az) available to select in selected/all PSH runtime(s).

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER runtimeName
    (optional) runtime name you want to get default modules for.

    If not provided, all default modules for all PSH runtimes in given automation account will be outputted.

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Get-AzureAutomationRuntimeAvailableDefaultModule

    You will get list of all resource groups and automation accounts (in current subscription) to pick the one you are interested in.
    And the output will be all default modules (Az) that are available to select there.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Get-AzureAutomationRuntimeAvailableDefaultModule -resourceGroupName "AdvancedLoggingRG" -automationAccountName "EnableO365AdvancedLogging" -runtimeName "PSH51_Custom"

    And the output will be default modules (Az) that are available to select in given Runtime Environment.
    #>

    [CmdletBinding()]
    param (
        [string] $resourceGroupName,

        [string] $automationAccountName,

        [string] $runtimeName,

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
    #endregion get missing arguments

    if ($runtimeName) {
        # get available default modules for this specific runtime
        # for this we need to get used PowerShell version
        $runtime = Get-AzureAutomationRuntime -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -header $header -runtimeName $runtimeName -programmingLanguage PowerShell -ErrorAction Stop

        if (!$runtime) {
            throw "Runtime Environment wasn't found. Name is misspelled or it is not a PSH runtime"
        }

        $runtimeVersion = $runtime.properties.runtime.version

        if ($runtimeVersion -eq '5.1') {
            $runtimeLanguageVersion = 'powershell'
        } elseif ($runtimeVersion -eq '7.1') {
            $runtimeLanguageVersion = 'powershell7'
        } else {
            # hopefully MS will stick with this format
            $runtimeLanguageVersion = ('powershell' + ($runtimeVersion -replace '\.'))
        }

        Write-Verbose "Available default modules will be limited to $runtimeLanguageVersion runtime language"
    } else {
        $runtimeLanguageVersion = '*'
    }

    $result = Invoke-RestMethod2 -method Post -uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/listbuiltinmodules?api-version=2023-05-15-preview" -headers $header

    if ($result) {
        # instead of one object containing all runtimes return one object per runtime
        $result | Get-Member -MemberType NoteProperty | select -ExpandProperty Name | ? { $_ -like $runtimeLanguageVersion } | % {
            $runtimeLanguage = $_
            $result.$runtimeLanguage | select @{n = 'RuntimeLanguage'; e = { $runtimeLanguage } }, *
        }
    }
}

function Get-AzureAutomationRuntimeCustomModule {
    <#
    .SYNOPSIS
    Function gets all (or just selected) custom modules (packages) that are imported in the specified PowerShell Azure Automation runtime.

    .DESCRIPTION
    Function gets all (or just selected) custom modules (packages) that are imported in the specified PowerShell Azure Automation runtime.

    Custom modules are added by user, default ones are built-in (Az) and user just select version to use.

    .PARAMETER runtimeName
    Name of the runtime environment you want to retrieve.

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER moduleName
    Name of the custom module you want to get.

    If not provided, all custom modules will be returned.

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Get-AzureAutomationRuntimeCustomModule

    You will get list of all (in current subscription) resource groups, automation accounts and runtimes to pick the one you are interested in.
    And the output will be all custom modules imported in the specified Automation runtime.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Get-AzureAutomationRuntimeCustomModule -resourceGroupName "AdvancedLoggingRG" -automationAccountName "EnableO365AdvancedLogging" -runtimeName Custom_PSH_51 -moduleName CommonStuff

    Get custom module CommonStuff imported in the specified Automation runtime.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Get-AzureAutomationRuntimeCustomModule -resourceGroupName "AdvancedLoggingRG" -automationAccountName "EnableO365AdvancedLogging" -runtimeName Custom_PSH_51

    Get all custom modules imported in the specified Automation runtime.
    #>

    [CmdletBinding()]
    param (
        [string] $runtimeName,

        [string] $resourceGroupName,

        [string] $automationAccountName,

        [string] $moduleName,

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
        $runtimeName = Get-AzureAutomationRuntime -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -header $header -programmingLanguage PowerShell | select -ExpandProperty Name | Out-GridView -OutputMode Single -Title "Select runtime you want to process"
    }
    #endregion get missing arguments

    Invoke-RestMethod2 -method Get -uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runtimeEnvironments/$runtimeName/packages/$moduleName`?api-version=2023-05-15-preview" -headers $header
}

function Get-AzureAutomationRuntimeSelectedDefaultModule {
    <#
    .SYNOPSIS
    Function get default module (Az) that is selected in the specified Azure Automation runtime.

    .DESCRIPTION
    Function get default module (Az) that is selected in the specified Azure Automation runtime.

    Custom modules are added by user, default ones are built-in (Az) and user just select version to use.

    .PARAMETER runtimeName
    Name of the runtime environment you want to retrieve.

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Get-AzureAutomationRuntimeSelectedDefaultModule

    You will get list of all (in current subscription) resource groups, automation accounts and runtimes to pick the one you are interested in.
    And you will get default module name (AZ) and its version that is selected in the specified Automation runtime.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Get-AzureAutomationRuntimeSelectedDefaultModule -resourceGroupName "AdvancedLoggingRG" -automationAccountName "EnableO365AdvancedLogging" -runtimeName Custom_PSH_51

    Get default module (Az) version in the specified Automation runtime.
    #>

    [CmdletBinding()]
    [Alias("Get-AzureAutomationRuntimeAzModule")]
    param (
        [string] $runtimeName,

        [string] $resourceGroupName,

        [string] $automationAccountName,

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

    Get-AzureAutomationRuntime -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -runtimeName $runtimeName -header $header | select -ExpandProperty properties | select -ExpandProperty defaultPackages
}

function Get-AzureResource {
    <#
    .SYNOPSIS
    Returns resources for all or just selected Azure subscription(s).

    .DESCRIPTION
    Returns resources for all or just selected Azure subscription(s).

    .PARAMETER subscriptionId
    ID of subscription you want to get resources for.

    .PARAMETER selectCurrentSubscription
    Switch for getting data just for currently set subscription.

    .EXAMPLE
    Get-AzureResource

    Returns resources for all subscriptions.

    .EXAMPLE
    Get-AzureResource -subscriptionId 1234-1234-1234-1234

    Returns resources for subscription with ID 1234-1234-1234-1234.

    .EXAMPLE
    Get-AzureResource -selectCurrentSubscription

    Returns resources just for current subscription.
    #>

    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param (
        [Parameter(ParameterSetName = "subscriptionId")]
        [string] $subscriptionId,

        [Parameter(ParameterSetName = "currentSubscription")]
        [switch] $selectCurrentSubscription
    )

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    # get Current Context
    $currentContext = Get-AzContext

    # get Azure Subscriptions
    if ($selectCurrentSubscription) {
        Write-Verbose "Only running for current subscription $($currentContext.Subscription.Name)"
        $subscriptions = Get-AzSubscription -SubscriptionId $currentContext.Subscription.Id -TenantId $currentContext.Tenant.Id
    } elseif ($subscriptionId) {
        Write-Verbose "Only running for selected subscription $subscriptionId"
        $subscriptions = Get-AzSubscription -SubscriptionId $subscriptionId -TenantId $currentContext.Tenant.Id
    } else {
        Write-Verbose "Running for all subscriptions in tenant"
        $subscriptions = Get-AzSubscription -TenantId $currentContext.Tenant.Id
    }

    Write-Verbose "Getting information about Role Definitions..."
    $allRoleDefinition = Get-AzRoleDefinition

    foreach ($subscription in $subscriptions) {
        Write-Verbose "Changing to Subscription $($subscription.Name)"

        $Context = Set-AzContext -TenantId $subscription.TenantId -SubscriptionId $subscription.Id -Force

        # getting information about Role Assignments for chosen subscription
        Write-Verbose "Getting information about Role Assignments..."
        $allRoleAssignment = Get-AzRoleAssignment

        Write-Verbose "Getting information about Resources..."

        Get-AzResource | % {
            $resourceId = $_.ResourceId
            Write-Verbose "Processing $resourceId"

            $roleAssignment = $allRoleAssignment | ? { $resourceId -match [regex]::escape($_.scope) -or $_.scope -like "/providers/Microsoft.Authorization/roleAssignments/*" -or $_.scope -like "/providers/Microsoft.Management/managementGroups/*" } | select RoleDefinitionName, DisplayName, Scope, SignInName, ObjectType, ObjectId, @{n = 'CustomRole'; e = { ($allRoleDefinition | ? Name -EQ $_.RoleDefinitionName).IsCustom } }, @{n = 'Inherited'; e = { if ($_.scope -eq $resourceId) { $false } else { $true } } }

            $_ | select *, @{n = "SubscriptionName"; e = { $subscription.Name } }, @{n = "SubscriptionId"; e = { $subscription.SubscriptionId } }, @{n = 'IAM'; e = { $roleAssignment } } -ExcludeProperty SubscriptionId, ResourceId, ResourceType
        }
    }
}

function Import-VariableFromStorage {
    <#
    .SYNOPSIS
    Function for downloading Azure Blob storage XML file and converting it back to original PowerShell object.

    .DESCRIPTION
    Function for downloading Azure Blob storage XML file and converting it back to original PowerShell object.

    Uses native Import-CliXml command for converting XML back to an object hence expects that such PowerShell object was previously saved using Export-VariableToStorage.

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

    Invoke-RestMethod2 -method Put -uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runtimeEnvironments/$runtimeEnvironmentName/packages/$moduleName`?api-version=2023-05-15-preview" -body $body -headers $header

    #>

    $accessToken = Get-AzAccessToken -ResourceUrl "https://management.azure.com" -ErrorAction Stop
    if ($accessToken.Token) {
        $header = @{
            'Content-Type'  = 'application/json'
            'Authorization' = "Bearer {0}" -f $accessToken.Token
        }

        return $header
    } else {
        throw "Unable to obtain token. Are you connected using Connect-AzAccount?"
    }
}

function New-AzureAutomationModule {
    <#
    .SYNOPSIS
    Function for importing new (or updating existing) Azure Automation PSH module.

    Any module dependencies will be automatically installed too.

    .DESCRIPTION
    Function for importing new (or updating existing) Azure Automation PSH module.

    Any module dependencies will be automatically installed too.

    By default newest supported version is imported (if 'moduleVersion' is not set). If module exists, but with different version, it will be replaced (including its dependencies).

    According the dependencies. If version that can be used exist, it is not updated to the newest possible one, but is used at it is. Reason for this is to avoid unnecessary updates that can lead to unstable/untested environment.

    Supported version means, version that support given runtime ('runtimeVersion' parameter).

    .PARAMETER moduleName
    Name of the PSH module.

    .PARAMETER moduleVersion
    (optional) version of the PSH module.
    If not specified, newest supported version for given runtime will be gathered from PSGallery.

    .PARAMETER moduleVersionType
    Type of the specified module version.

    Possible values are: 'RequiredVersion', 'MinimumVersion', 'MaximumVersion'.

    By default 'RequiredVersion'.

    .PARAMETER resourceGroupName
    Name of the Azure Resource Group.

    .PARAMETER automationAccountName
    Name of the Azure Automation Account.

    .PARAMETER runtimeVersion
    PSH runtime version.

    Possible values: 5.1, 7.2.

    By default 5.1.

    .PARAMETER overridePSGalleryModuleVersion
    Hashtable of hashtables where you can specify what module version should be used for given runtime if no specific version is required.

    This is needed in cases, where module newest available PSGallery version isn't compatible with your runtime because of incorrect manifest.

    By default:

    $overridePSGalleryModuleVersion = @{
        # 2.x.x PnP.PowerShell versions (2.1.1, 2.2.0) requires PSH 7.2 even though manifest doesn't say it
        # so the wrong module version would be picked up which would cause an error when trying to import
        "PnP.PowerShell" = @{
            "5.1" = "1.12.0"
        }
    }

    .EXAMPLE
    Connect-AzAccount -Tenant "contoso.onmicrosoft.com" -SubscriptionName "AutomationSubscription"

    New-AzureAutomationModule -resourceGroupName test -automationAccountName test -moduleName "Microsoft.Graph.Groups"

    Imports newest supported version (for given runtime) of the "Microsoft.Graph.Groups" module including all its dependencies.
    In case module "Microsoft.Graph.Groups" with such version is already imported, nothing will happens.
    Otherwise module will be imported/replaced (including all dependencies that are required for this specific version).

    .EXAMPLE
    Connect-AzAccount -Tenant "contoso.onmicrosoft.com" -SubscriptionName "AutomationSubscription"

    New-AzureAutomationModule -resourceGroupName test -automationAccountName test -moduleName "Microsoft.Graph.Groups" -moduleVersion "2.11.1"

    Imports "2.11.1" version of the "Microsoft.Graph.Groups" module including all its dependencies.
    In case module "Microsoft.Graph.Groups" with version "2.11.1" is already imported, nothing will happens.
    Otherwise module will be imported/replaced (including all dependencies that are required for this specific version).

    .NOTES
    1. Because this function depends on Find-Module command heavily, it needs to have communication with the PSGallery enabled. To automate this, you can use following code:

    "Install a package manager"
    $null = Install-PackageProvider -Name nuget -Force -ForceBootstrap -Scope allusers

    "Set PSGallery as a trusted repository"
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

    'PackageManagement', 'PowerShellGet', 'PSReadline', 'PSScriptAnalyzer' | % {
        "Install module $_"
        Install-Module $_ -Repository PSGallery -Force -AllowClobber
    }

    "Uninstall old version of PowerShellGet"
    Get-Module PowerShellGet -ListAvailable | ? version -lt 2.0.0 | select -exp ModuleBase | % { Remove-Item -Path $_ -Recurse -Force }

    2. Modules saved in Azure Automation Account have only "main" version saved and suffixes like "beta", "rc" etc are always cut off!
    A.k.a. if you import module with version "1.0.0-rc4". Version that will be shown in the GUI will be just "1.0.0" hence if you try to import such module again, it won't be correctly detected hence will be imported once again.
    #>

    [CmdletBinding()]
    [Alias("New-AzAutomationModule2", "Set-AzureAutomationModule")]
    param (
        [Parameter(Mandatory = $true)]
        [string] $moduleName,

        [string] $moduleVersion,

        [ValidateSet('RequiredVersion', 'MinimumVersion', 'MaximumVersion')]
        [string] $moduleVersionType = 'RequiredVersion',

        [Parameter(Mandatory = $true)]
        [string] $resourceGroupName,

        [Parameter(Mandatory = $true)]
        [string] $automationAccountName,

        [ValidateSet('5.1', '7.2')]
        [string] $runtimeVersion = '5.1',

        [int] $indent = 0,

        [hashtable[]] $overridePSGalleryModuleVersion = @{
            # 2.x.x PnP.PowerShell versions (2.1.1, 2.2.0) requires PSH 7.2 even though manifest doesn't say it
            # so the wrong module version would be picked up which would cause an error when trying to import
            "PnP.PowerShell" = @{
                "5.1" = "1.12.0"
            }
        }
    )

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    $indentString = "     " * $indent

    #region helper functions
    function _write {
        param ($string, $color, [switch] $noNewLine, [switch] $noIndent)

        $param = @{}
        if ($noIndent) {
            $param.Object = $string
        } else {
            $param.Object = ($indentString + $string)
        }
        if ($color) {
            $param.ForegroundColor = $color
        }
        if ($noNewLine) {
            $param.noNewLine = $true
        }

        Write-Host @param
    }

    function Compare-VersionString {
        # module version can be like "1.0.0", but also like "2.0.0-preview8", "2.0.0-rc3"
        # hence this comparison function
        param (
            [Parameter(Mandatory = $true)]
            $version1,

            [Parameter(Mandatory = $true)]
            $version2,

            [Parameter(Mandatory = $true)]
            [ValidateSet('equal', 'notEqual', 'greaterThan', 'lessThan')]
            $operator
        )

        function _convertResultToBoolean {
            # function that converts 0,1,-1 to true/false based on comparison operator
            param (
                [ValidateSet('equal', 'notEqual', 'greaterThan', 'lessThan')]
                $operator,

                $result
            )

            switch ($operator) {
                "equal" {
                    if ($result -eq 0) {
                        return $true
                    }
                }

                "notEqual" {
                    if ($result -ne 0) {
                        return $true
                    }
                }

                "greaterThan" {
                    if ($result -eq 1) {
                        return $true
                    }
                }

                "lessThan" {
                    if ($result -eq -1) {
                        return $true
                    }
                }

                default { throw "Undefined operator" }
            }

            return $false
        }

        # Split version and suffix
        $v1, $suffix1 = $version1 -split '-', 2
        $v2, $suffix2 = $version2 -split '-', 2

        # Compare versions
        $versionComparison = ([version]$v1).CompareTo([version]$v2)
        if ($versionComparison -ne 0) {
            return (_convertResultToBoolean -operator $operator -result $versionComparison)
        }

        # If versions are equal, compare suffixes
        if ($suffix1 -and !$suffix2) {
            return (_convertResultToBoolean -operator $operator -result -1)
        } elseif (!$suffix1 -and $suffix2) {
            return (_convertResultToBoolean -operator $operator -result 1)
        } elseif (!$suffix1 -and !$suffix2) {
            return (_convertResultToBoolean -operator $operator -result 0)
        } else {
            return (_convertResultToBoolean -operator $operator -result ([string]::Compare($suffix1, $suffix2)))
        }
    }
    #endregion helper functions

    if ($moduleVersion) {
        $moduleVersionString = "($moduleVersion)"
    } else {
        $moduleVersionString = ""
    }

    _write "Processing module $moduleName $moduleVersionString" "Magenta"

    #region get PSGallery module data
    $param = @{
        # IncludeDependencies = $true # cannot be used, because always returns newest usable module version, I want to use existing modules if possible (to minimize the runtime & risk that something will stop working)
        Name        = $moduleName
        ErrorAction = "Stop"
    }
    if ($moduleVersion) {
        $param.$moduleVersionType = $moduleVersion
        if (!($moduleVersion -as [version])) {
            # version is something like "2.2.0.rc4" a.k.a. pre-release version
            $param.AllowPrerelease = $true
        }
    } elseif ($runtimeVersion -eq '5.1') {
        $param.AllVersions = $true
    }

    $moduleGalleryInfo = Find-Module @param
    #endregion get PSGallery module data

    # get newest usable module version for given runtime
    if (!$moduleVersion -and $runtimeVersion -eq '5.1') {
        # no specific version was selected and older PSH version is used, make sure module that supports it, will be found
        # for example (currently newest) pnp.powershell 2.3.0 supports only PSH 7.2
        $moduleGalleryInfo = $moduleGalleryInfo | ? { $_.AdditionalMetadata.PowerShellVersion -le $runtimeVersion } | select -First 1
    }

    if (!$moduleGalleryInfo) {
        Write-Error "No supported $moduleName module was found in PSGallery"
        return
    }

    #region override module version
    # range instead of specific module version was specified
    if ($moduleVersion -and $moduleVersionType -ne 'RequiredVersion' -and $moduleVersion -ne $moduleGalleryInfo.Version) {
        _write " (version $($moduleGalleryInfo.Version) will be used instead of $moduleVersionType $moduleVersion)"
        $moduleVersion = $moduleGalleryInfo.Version
    }

    # no version was specified and module is in override list
    if (!$moduleVersion -and $moduleName -in $overridePSGalleryModuleVersion.Keys -and $overridePSGalleryModuleVersion.$moduleName.$runtimeVersion) {
        $overriddenModule = $overridePSGalleryModuleVersion.$moduleName
        $overriddenModuleVersion = $overriddenModule.$runtimeVersion
        if ($overriddenModuleVersion) {
            _write " (no version specified and override for version exists, hence will be used ($overriddenModuleVersion))"
            $moduleVersion = $overriddenModuleVersion
        }
    }

    # no version was specified, use the newest one
    if (!$moduleVersion) {
        $moduleVersion = $moduleGalleryInfo.Version
        _write " (no version specified, newest supported version from PSGallery will be used ($moduleVersion))"
    }
    #endregion override module version

    Write-Verbose "Getting current Automation modules"
    $currentAutomationModules = Get-AzAutomationModule -AutomationAccountName $automationAccountName -ResourceGroup $resourceGroupName -RuntimeVersion $runtimeVersion -ErrorAction Stop

    # check whether required module is present
    # there can be module in Failed state, just because update of such module failed, but if it has SizeInBytes set, it means its in working state
    $moduleExists = $currentAutomationModules | ? { $_.Name -eq $moduleName -and ($_.ProvisioningState -eq "Succeeded" -or $_.SizeInBytes) }
    if ($moduleExists) {
        $moduleExistsVersion = $moduleExists.Version
        if ($moduleVersion -and $moduleVersion -ne $moduleExistsVersion) {
            $moduleExists = $null
        }

        if ($moduleExists) {
            return ($indentString + "Module $moduleName ($moduleExistsVersion) is already present")
        } elseif (!$moduleExists -and $indent -eq 0) {
            # some module with that name exists, but not in the correct version and this is not a recursive call (because of dependency processing) hence user was not yet warned about replacing the module
            _write " - Existing module $moduleName ($moduleExistsVersion) will be replaced" "Yellow"
        }
    }

    _write " - Getting module $moduleName dependencies"
    $moduleDependency = $moduleGalleryInfo.Dependencies | Sort-Object { $_.name }

    # dependency must be installed first
    if ($moduleDependency) {
        #TODO znacit si jake moduly jsou required (at uz tam jsou nebo musim doinstalovat) a kontrolovat, ze jeden neni required s ruznymi verzemi == konflikt protoze nainstalovana muze byt jen jedna
        _write "  - Depends on: $($moduleDependency.Name -join ', ')"
        foreach ($module in $moduleDependency) {
            $requiredModuleName = $module.Name
            $requiredModuleMinVersion = $module.MinimumVersion -replace "\[|]" # for some reason version can be like '[2.0.0-preview6]'
            $requiredModuleMaxVersion = $module.MaximumVersion -replace "\[|]"
            $requiredModuleReqVersion = $module.RequiredVersion -replace "\[|]"
            $notInCorrectVersion = $false

            _write "   - Checking module $requiredModuleName (minVer: $requiredModuleMinVersion maxVer: $requiredModuleMaxVersion reqVer: $requiredModuleReqVersion)"

            # there can be module in Failed state, just because update of such module failed, but if it has SizeInBytes set, it means its in working state
            $existingRequiredModule = $currentAutomationModules | ? { $_.Name -eq $requiredModuleName -and ($_.ProvisioningState -eq "Succeeded" -or $_.SizeInBytes) }
            $existingRequiredModuleVersion = $existingRequiredModule.Version # version always looks like n.n.n. suffixes like rc, beta etc are always cut off!

            # check that existing module version fits
            if ($existingRequiredModule -and ($requiredModuleMinVersion -or $requiredModuleMaxVersion -or $requiredModuleReqVersion)) {
                #TODO pokud nahrazuji existujici modul, tak bych se mel podivat, jestli jsou vsechny ostatni ok s jeho novou verzi
                if ($requiredModuleReqVersion -and (Compare-VersionString $requiredModuleReqVersion $existingRequiredModuleVersion "notEqual")) {
                    $notInCorrectVersion = $true
                    _write "     - module exists, but not in the correct version (has: $existingRequiredModuleVersion, should be: $requiredModuleReqVersion). Will be replaced" "Yellow"
                } elseif ($requiredModuleMinVersion -and $requiredModuleMaxVersion -and ((Compare-VersionString $existingRequiredModuleVersion $requiredModuleMinVersion "lessThan") -or (Compare-VersionString $existingRequiredModuleVersion $requiredModuleMaxVersion "greaterThan"))) {
                    $notInCorrectVersion = $true
                    _write "     - module exists, but not in the correct version (has: $existingRequiredModuleVersion, should be: $requiredModuleMinVersion .. $requiredModuleMaxVersion). Will be replaced" "Yellow"
                } elseif ($requiredModuleMinVersion -and (Compare-VersionString $existingRequiredModuleVersion $requiredModuleMinVersion "lessThan")) {
                    $notInCorrectVersion = $true
                    _write "     - module exists, but not in the correct version (has: $existingRequiredModuleVersion, should be > $requiredModuleMinVersion). Will be replaced" "Yellow"
                } elseif ($requiredModuleMaxVersion -and (Compare-VersionString $existingRequiredModuleVersion $requiredModuleMaxVersion "greaterThan")) {
                    $notInCorrectVersion = $true
                    _write "     - module exists, but not in the correct version (has: $existingRequiredModuleVersion, should be < $requiredModuleMaxVersion). Will be replaced" "Yellow"
                }
            }

            if (!$existingRequiredModule -or $notInCorrectVersion) {
                if (!$existingRequiredModule) {
                    _write "     - module is missing" "Yellow"
                }

                if ($notInCorrectVersion) {
                    #TODO kontrola, ze jina verze modulu nerozbije zavislost nejakeho jineho existujiciho modulu
                }

                #region install required module first
                $param = @{
                    moduleName            = $requiredModuleName
                    resourceGroupName     = $resourceGroupName
                    automationAccountName = $automationAccountName
                    runtimeVersion        = $runtimeVersion
                    indent                = $indent + 1
                }
                if ($requiredModuleMinVersion) {
                    $param.moduleVersion = $requiredModuleMinVersion
                    $param.moduleVersionType = 'MinimumVersion'
                }
                if ($requiredModuleMaxVersion) {
                    $param.moduleVersion = $requiredModuleMaxVersion
                    $param.moduleVersionType = 'MaximumVersion'
                }
                if ($requiredModuleReqVersion) {
                    $param.moduleVersion = $requiredModuleReqVersion
                    $param.moduleVersionType = 'RequiredVersion'
                }

                New-AzureAutomationModule @param
                #endregion install required module first
            } else {
                if ($existingRequiredModuleVersion) {
                    _write "     - module (ver. $existingRequiredModuleVersion) is already present"
                } else {
                    _write "     - module is already present"
                }
            }
        }
    } else {
        _write "  - No dependency found"
    }

    $uri = "https://www.powershellgallery.com/api/v2/package/$moduleName/$moduleVersion"
    _write " - Uploading module $moduleName ($moduleVersion)" "Yellow"
    $status = New-AzAutomationModule -AutomationAccountName $automationAccountName -ResourceGroup $resourceGroupName -Name $moduleName -ContentLinkUri $uri -RuntimeVersion $runtimeVersion

    #region output dots while waiting on import to finish
    $i = 0
    _write "    ." -noNewLine
    do {
        Start-Sleep 5

        if ($i % 3 -eq 0) {
            _write "." -noNewLine -noIndent
        }

        ++$i
    } while (!($requiredModule = Get-AzAutomationModule -AutomationAccountName $automationAccountName -ResourceGroup $resourceGroupName -RuntimeVersion $runtimeVersion -ErrorAction Stop | ? { $_.Name -eq $moduleName -and $_.ProvisioningState -in "Succeeded", "Failed" }))

    ""
    #endregion output dots while waiting on import to finish

    if ($requiredModule.ProvisioningState -ne "Succeeded") {
        Write-Error "Import failed. Check Azure Portal >> Automation Account >> Modules >> $moduleName details to get the reason."
    } else {
        _write " - Success" "Green"
    }
}

function New-AzureAutomationRuntime {
    <#
    .SYNOPSIS
    Function creates a new custom Azure Automation Account Runtime.

    .DESCRIPTION
    Function creates a new custom Azure Automation Account Runtime.

    Both Powershell nad Python runtimes are supported. Powershell one supports specifying Az module version.

    .PARAMETER runtimeName
    Name of the created runtime.

    .PARAMETER runtimeLanguage
    Language that will be used in created runtime.

    Possible values are PowerShell, Python.

    .PARAMETER runtimeVersion
    Version of the runtimeLanguage.

    For Python it is 3.8, 3.10, for PowerShell '5.1', '7.1', '7.2', but this will likely change in the future.

    .PARAMETER defaultPackage
    Only use for PowerShell runtimeLanguage!

    Hashtable where keys are default module names ('az' (both PSHs), 'azure cli' (only in PSH Core)) and values are module versions.

    If no defaultPackage hashtable is provided, no default modules will be enabled in created runtime.

    .PARAMETER description
    Runtime description.

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    $defaultPackage = @{
        az = '8.0.0'
    }

    New-AzureAutomationRuntime -runtimeName 'CustomPSH51' -runtimeLanguage 'PowerShell' -runtimeVersion 5.1 -defaultPackage $defaultPackage -description 'PSH 5.1 for testing purposes' -resourceGroupName 'AdvancedLoggingRG' -automationAccountName 'EnableO365AdvancedLogging'

    Create new custom Powershell 5.1 runtime with Az module 8.0.0 enabled.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    New-AzureAutomationRuntime -runtimeName 'CustomPSH51' -runtimeLanguage 'PowerShell' -runtimeVersion 5.1 -description 'PSH 5.1 for testing purposes' -resourceGroupName 'AdvancedLoggingRG' -automationAccountName 'EnableO365AdvancedLogging'

    Create a new custom Powershell 5.1 runtime without Az module enabled.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    $defaultPackage = @{
        'az' = '8.0.0'
        'azure cli' = '2.56.0'
    }

    New-AzureAutomationRuntime -runtimeName 'CustomPSH72' -runtimeLanguage 'PowerShell' -runtimeVersion 7.2 -defaultPackage $defaultPackage -description 'PSH 7.2 for testing purposes' -resourceGroupName 'AdvancedLoggingRG' -automationAccountName 'EnableO365AdvancedLogging'

    Create a new custom Powershell 7.2 runtime with 'Az module 8.0.0' and 'azure cli 2.56.0' enabled.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    New-AzureAutomationRuntime -runtimeName 'CustomPython310' -runtimeLanguage 'Python' -runtimeVersion 3.10 -description 'Python 3.10 for testing purposes' -resourceGroupName 'AdvancedLoggingRG' -automationAccountName 'EnableO365AdvancedLogging'

    Create a new custom Python 3.10 runtime.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $runtimeName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('PowerShell', 'Python')]
        [string] $runtimeLanguage,

        [ArgumentCompleter( {
                param ($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams)

                if ($runtimeLanguage = $FakeBoundParams.runtimeLanguage) {
                    switch ($runtimeLanguage) {
                        'PowerShell' {
                            '5.1', '7.1', '7.2' | ? { $_ -like "*$WordToComplete*" }
                        }

                        'Python' {
                            '3.8', '3.10' | ? { $_ -like "*$WordToComplete*" }
                        }
                    }
                }
            })]
        [string] $runtimeVersion,

        [hashtable] $defaultPackage,

        [string] $description,

        [string] $resourceGroupName,

        [string] $automationAccountName,

        [hashtable] $header
    )

    #region checks
    if ($defaultPackage -and $runtimeLanguage -ne 'PowerShell') {
        Write-Warning "Parameter 'defaultModuleData' can be defined only for 'PowerShell' runtime language. Will be ignored."
        $defaultPackage = @{}
    }

    if (!$defaultPackage -and $runtimeLanguage -eq 'PowerShell') {
        $defaultPackage = @{}
    }
    #endregion checks

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
    #endregion get missing arguments

    #region checks
    try {
        $runtime = $null
        $runtime = Get-AzureAutomationRuntime -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -header $header -runtimeName $runtimeName -ErrorAction Stop
    } catch {
        if ($_.exception.StatusCode -ne 'NotFound') {
            throw $_
        }
    }

    if ($runtime) {
        # prevent accidental replacing of the existing runtime
        throw "Runtime with given name '$runtimeName' already exist"
    }
    #endregion checks

    #region send web request
    $body = @{
        properties = @{
            runtime         = @{
                language = $runtimeLanguage
                version  = $runtimeVersion
            }
            defaultPackages = $defaultPackage
            description     = $description
        }
    }

    $body = $body | ConvertTo-Json

    Write-Verbose $body

    Invoke-RestMethod2 -method Put -uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runtimeEnvironments/$runtimeName`?api-version=2023-05-15-preview" -body $body -headers $header
    #endregion send web request
}

function New-AzureAutomationRuntimeModule {
    <#
    .SYNOPSIS
    Function add/replace selected module in specified Azure Automation runtime by importing it from the PowerShell Gallery.
    If module has some dependencies, that are currently missing (or have incorrect version), they will be imported automatically.

    .DESCRIPTION
    Function add/replace selected module in specified Azure Automation runtime by importing it from the PowerShell Gallery.

    If module exists, it will be replaced by selected version, if it is not, it will be added.

    If module has some dependencies, that are currently missing (or have incorrect version), they will be imported automatically.

    .PARAMETER runtimeName
    Name of the runtime environment you want to retrieve.

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER moduleName
    Name of the module you want to add/(replace by other version).

    .PARAMETER moduleVersion
    Module version.
    If not specified, newest supported version for given runtime will be gathered from PSGallery.

    .PARAMETER moduleVersionType
    Type of the specified module version.

    Possible values are: 'RequiredVersion', 'MinimumVersion', 'MaximumVersion'.

    By default 'RequiredVersion'.

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .PARAMETER overridePSGalleryModuleVersion
    Hashtable of hashtables where you can specify what module version should be used for given runtime if no specific version is required.

    This is needed in cases, where newest module version available in PSGallery isn't compatible with your runtime because of incorrect module manifest.

    By default:

    $overridePSGalleryModuleVersion = @{
        # 2.x.x PnP.PowerShell versions (2.1.1, 2.2.0) requires PSH 7.2 even though manifest doesn't say it
        # so the wrong module version would be picked up which would cause an error when trying to import
        "PnP.PowerShell" = @{
            "5.1" = "1.12.0"
        }
    }

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    New-AzureAutomationRuntimeModule -moduleName CommonStuff -moduleVersion 1.0.18

    Add module CommonStuff 1.0.18 to the specified Automation runtime.
    If module exists, it will be replaced by selected version, if it is not, it will be added.
    If module has some dependencies, that are currently missing (or have incorrect version), they will be imported automatically.

    Missing function arguments like $resourceGroupName or $automationAccountName will be interactively gathered through Out-GridView GUI.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    New-AzureAutomationRuntimeModule -resourceGroupName "AdvancedLoggingRG" -automationAccountName "EnableO365AdvancedLogging" -runtimeName Custom_PSH_51 -moduleName CommonStuff -moduleVersion 1.0.18

    Add module CommonStuff 1.0.18 to specified Automation runtime.
    If module exists, it will be replaced by selected version, if it is not, it will be added.
    #>

    [CmdletBinding()]
    [Alias("Set-AzureAutomationRuntimeModule")]
    param (
        [string] $runtimeName,

        [string] $resourceGroupName,

        [string] $automationAccountName,

        [Parameter(Mandatory = $true)]
        [string] $moduleName,

        [string] $moduleVersion,

        [ValidateSet('RequiredVersion', 'MinimumVersion', 'MaximumVersion')]
        [string] $moduleVersionType = 'RequiredVersion',

        [hashtable] $header,

        [int] $indent = 0,

        [hashtable[]] $overridePSGalleryModuleVersion = @{
            # 2.x.x PnP.PowerShell versions (2.1.1, 2.2.0) requires PSH 7.2 even though manifest doesn't say it
            # so the wrong module version would be picked up which would cause an error when trying to import
            "PnP.PowerShell" = @{
                "5.1" = "1.12.0"
            }
        }
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
        $runtimeName = Get-AzureAutomationRuntime -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -programmingLanguage PowerShell -runtimeSource Custom -header $header | select -ExpandProperty Name | Out-GridView -OutputMode Single -Title "Select environment you want to process"
    }
    #endregion get missing arguments

    try {
        $runtime = Get-AzureAutomationRuntime -automationAccountName $automationAccountName -ResourceGroup $resourceGroupName -runtimeName $runtimeName -programmingLanguage PowerShell -runtimeSource Custom -header $header -ErrorAction Stop
    } catch {
        throw "Runtime '$runtimeName' doesn't exist or it isn't custom created PowerShell Runtime"
    }
    $runtimeVersion = $runtime.properties.runtime.version

    $indentString = "     " * $indent

    #region helper functions
    function _write {
        param ($string, $color, [switch] $noNewLine, [switch] $noIndent)

        $param = @{}
        if ($noIndent) {
            $param.Object = $string
        } else {
            $param.Object = ($indentString + $string)
        }
        if ($color) {
            $param.ForegroundColor = $color
        }
        if ($noNewLine) {
            $param.noNewLine = $true
        }

        Write-Host @param
    }

    function Compare-VersionString {
        # module version can be like "1.0.0", but also like "2.0.0-preview8", "2.0.0-rc3"
        # hence this comparison function
        param (
            [Parameter(Mandatory = $true)]
            $version1,

            [Parameter(Mandatory = $true)]
            $version2,

            [Parameter(Mandatory = $true)]
            [ValidateSet('equal', 'notEqual', 'greaterThan', 'lessThan')]
            $operator
        )

        function _convertResultToBoolean {
            # function that converts 0,1,-1 to true/false based on comparison operator
            param (
                [ValidateSet('equal', 'notEqual', 'greaterThan', 'lessThan')]
                $operator,

                $result
            )

            switch ($operator) {
                "equal" {
                    if ($result -eq 0) {
                        return $true
                    }
                }

                "notEqual" {
                    if ($result -ne 0) {
                        return $true
                    }
                }

                "greaterThan" {
                    if ($result -eq 1) {
                        return $true
                    }
                }

                "lessThan" {
                    if ($result -eq -1) {
                        return $true
                    }
                }

                default { throw "Undefined operator" }
            }

            return $false
        }

        # Split version and suffix
        $v1, $suffix1 = $version1 -split '-', 2
        $v2, $suffix2 = $version2 -split '-', 2

        # Compare versions
        $versionComparison = ([version]$v1).CompareTo([version]$v2)
        if ($versionComparison -ne 0) {
            return (_convertResultToBoolean -operator $operator -result $versionComparison)
        }

        # If versions are equal, compare suffixes
        if ($suffix1 -and !$suffix2) {
            return (_convertResultToBoolean -operator $operator -result -1)
        } elseif (!$suffix1 -and $suffix2) {
            return (_convertResultToBoolean -operator $operator -result 1)
        } elseif (!$suffix1 -and !$suffix2) {
            return (_convertResultToBoolean -operator $operator -result 0)
        } else {
            return (_convertResultToBoolean -operator $operator -result ([string]::Compare($suffix1, $suffix2)))
        }
    }
    #endregion helper functions

    if ($moduleVersion) {
        $moduleVersionString = "($moduleVersion)"
    } else {
        $moduleVersionString = ""
    }

    _write "Processing module $moduleName $moduleVersionString" "Magenta"

    #region get PSGallery module data
    $param = @{
        # IncludeDependencies = $true # cannot be used, because always returns newest usable module version, I want to use existing modules if possible (to minimize the runtime & risk that something will stop working)
        Name        = $moduleName
        ErrorAction = "Stop"
    }
    if ($moduleVersion) {
        $param.$moduleVersionType = $moduleVersion
        if (!($moduleVersion -as [version])) {
            # version is something like "2.2.0.rc4" a.k.a. pre-release version
            $param.AllowPrerelease = $true
        }
    } elseif ($runtimeVersion -eq '5.1') {
        $param.AllVersions = $true
    }

    $moduleGalleryInfo = Find-Module @param
    #endregion get PSGallery module data

    # get newest usable module version for given runtime
    if (!$moduleVersion -and $runtimeVersion -eq '5.1') {
        # no specific version was selected and older PSH version is used, make sure module that supports it, will be found
        # for example (currently newest) pnp.powershell 2.3.0 supports only PSH 7.2
        $moduleGalleryInfo = $moduleGalleryInfo | ? { $_.AdditionalMetadata.PowerShellVersion -le $runtimeVersion } | select -First 1
    }

    if (!$moduleGalleryInfo) {
        Write-Error "No supported $moduleName module was found in PSGallery"
        return
    }

    #region override module version
    # range instead of specific module version was specified
    if ($moduleVersion -and $moduleVersionType -ne 'RequiredVersion' -and $moduleVersion -ne $moduleGalleryInfo.Version) {
        _write " (version $($moduleGalleryInfo.Version) will be used instead of $moduleVersionType $moduleVersion)"
        $moduleVersion = $moduleGalleryInfo.Version
    }

    # no version was specified and module is in override list
    if (!$moduleVersion -and $moduleName -in $overridePSGalleryModuleVersion.Keys -and $overridePSGalleryModuleVersion.$moduleName.$runtimeVersion) {
        $overriddenModule = $overridePSGalleryModuleVersion.$moduleName
        $overriddenModuleVersion = $overriddenModule.$runtimeVersion
        if ($overriddenModuleVersion) {
            _write " (no version specified and override for version exists, hence will be used ($overriddenModuleVersion))"
            $moduleVersion = $overriddenModuleVersion
        }
    }

    # no version was specified, use the newest one
    if (!$moduleVersion) {
        $moduleVersion = $moduleGalleryInfo.Version
        _write " (no version specified, newest supported version from PSGallery will be used ($moduleVersion))"
    }
    #endregion override module version

    Write-Verbose "Getting current Automation modules"
    $currentAutomationModules = Get-AzureAutomationRuntimeCustomModule -automationAccountName $automationAccountName -ResourceGroup $resourceGroupName -runtimeName $runtimeName -header $header -ErrorAction Stop

    # check whether required module is present
    # there can be module in Failed state, just because update of such module failed, but if it has SizeInBytes set, it means its in working state
    $moduleExists = $currentAutomationModules | ? { $_.Name -eq $moduleName -and ($_.Properties.ProvisioningState -eq "Succeeded" -or $_.Properties.SizeInBytes) }
    if ($moduleExists) {
        $moduleExistsVersion = $moduleExists.Properties.Version
        if ($moduleVersion -and $moduleVersion -ne $moduleExistsVersion) {
            $moduleExists = $null
        }

        if ($moduleExists) {
            return ($indentString + "Module $moduleName ($moduleExistsVersion) is already present")
        } elseif (!$moduleExists -and $indent -eq 0) {
            # some module with that name exists, but not in the correct version and this is not a recursive call (because of dependency processing) hence user was not yet warned about replacing the module
            _write " - Existing module $moduleName ($moduleExistsVersion) will be replaced" "Yellow"
        }
    }

    _write " - Getting module $moduleName dependencies"
    $moduleDependency = $moduleGalleryInfo.Dependencies | Sort-Object { $_.name }

    # dependency must be installed first
    if ($moduleDependency) {
        #TODO znacit si jake moduly jsou required (at uz tam jsou nebo musim doinstalovat) a kontrolovat, ze jeden neni required s ruznymi verzemi == konflikt protoze nainstalovana muze byt jen jedna
        _write "  - Depends on: $($moduleDependency.Name -join ', ')"
        foreach ($module in $moduleDependency) {
            $requiredModuleName = $module.Name
            $requiredModuleMinVersion = $module.MinimumVersion -replace "\[|]" # for some reason version can be like '[2.0.0-preview6]'
            $requiredModuleMaxVersion = $module.MaximumVersion -replace "\[|]"
            $requiredModuleReqVersion = $module.RequiredVersion -replace "\[|]"
            $notInCorrectVersion = $false

            _write "   - Checking module $requiredModuleName (minVer: $requiredModuleMinVersion maxVer: $requiredModuleMaxVersion reqVer: $requiredModuleReqVersion)"

            # there can be module in Failed state, just because update of such module failed, but if it has SizeInBytes set, it means its in working state
            $existingRequiredModule = $currentAutomationModules | ? { $_.Name -eq $requiredModuleName -and ($_.Properties.ProvisioningState -eq "Succeeded" -or $_.Properties.SizeInBytes) }
            $existingRequiredModuleVersion = $existingRequiredModule.Properties.Version # version always looks like n.n.n. suffixes like rc, beta etc are always cut off!

            # check that existing module version fits
            if ($existingRequiredModule -and ($requiredModuleMinVersion -or $requiredModuleMaxVersion -or $requiredModuleReqVersion)) {
                #TODO pokud nahrazuji existujici modul, tak bych se mel podivat, jestli jsou vsechny ostatni ok s jeho novou verzi
                if ($requiredModuleReqVersion -and (Compare-VersionString $requiredModuleReqVersion $existingRequiredModuleVersion "notEqual")) {
                    $notInCorrectVersion = $true
                    _write "     - module exists, but not in the correct version (has: $existingRequiredModuleVersion, should be: $requiredModuleReqVersion). Will be replaced" "Yellow"
                } elseif ($requiredModuleMinVersion -and $requiredModuleMaxVersion -and ((Compare-VersionString $existingRequiredModuleVersion $requiredModuleMinVersion "lessThan") -or (Compare-VersionString $existingRequiredModuleVersion $requiredModuleMaxVersion "greaterThan"))) {
                    $notInCorrectVersion = $true
                    _write "     - module exists, but not in the correct version (has: $existingRequiredModuleVersion, should be: $requiredModuleMinVersion .. $requiredModuleMaxVersion). Will be replaced" "Yellow"
                } elseif ($requiredModuleMinVersion -and (Compare-VersionString $existingRequiredModuleVersion $requiredModuleMinVersion "lessThan")) {
                    $notInCorrectVersion = $true
                    _write "     - module exists, but not in the correct version (has: $existingRequiredModuleVersion, should be > $requiredModuleMinVersion). Will be replaced" "Yellow"
                } elseif ($requiredModuleMaxVersion -and (Compare-VersionString $existingRequiredModuleVersion $requiredModuleMaxVersion "greaterThan")) {
                    $notInCorrectVersion = $true
                    _write "     - module exists, but not in the correct version (has: $existingRequiredModuleVersion, should be < $requiredModuleMaxVersion). Will be replaced" "Yellow"
                }
            }

            if (!$existingRequiredModule -or $notInCorrectVersion) {
                if (!$existingRequiredModule) {
                    _write "     - module is missing" "Yellow"
                }

                if ($notInCorrectVersion) {
                    #TODO kontrola, ze jina verze modulu nerozbije zavislost nejakeho jineho existujiciho modulu
                }

                #region install required module first
                $param = @{
                    moduleName            = $requiredModuleName
                    resourceGroupName     = $resourceGroupName
                    automationAccountName = $automationAccountName
                    runtimeName           = $runtimeName
                    indent                = $indent + 1
                }
                if ($requiredModuleMinVersion) {
                    $param.moduleVersion = $requiredModuleMinVersion
                    $param.moduleVersionType = 'MinimumVersion'
                }
                if ($requiredModuleMaxVersion) {
                    $param.moduleVersion = $requiredModuleMaxVersion
                    $param.moduleVersionType = 'MaximumVersion'
                }
                if ($requiredModuleReqVersion) {
                    $param.moduleVersion = $requiredModuleReqVersion
                    $param.moduleVersionType = 'RequiredVersion'
                }

                New-AzureAutomationRuntimeModule @param
                #endregion install required module first
            } else {
                if ($existingRequiredModuleVersion) {
                    _write "     - module (ver. $existingRequiredModuleVersion) is already present"
                } else {
                    _write "     - module is already present"
                }
            }
        }
    } else {
        _write "  - No dependency found"
    }

    _write " - Uploading module $moduleName ($moduleVersion)" "Yellow"
    $modulePkgUri = "https://devopsgallerystorage.blob.core.windows.net/packages/$($moduleName.ToLower()).$moduleVersion.nupkg"

    $pkgStatus = Invoke-WebRequest -Uri $modulePkgUri -SkipHttpErrorCheck
    if ($pkgStatus.StatusCode -ne 200) {
        # don't exit the invocation, module can have as dependency module that doesn't exist in PSH Gallery
        Write-Error "Module $moduleName (version $moduleVersion) doesn't exist in PSGallery. Error was $($pkgStatus.StatusDescription)"
        return
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

    $null = Invoke-RestMethod2 -method Put -uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runtimeEnvironments/$runtimeName/packages/$moduleName`?api-version=2023-05-15-preview" -body $body -headers $header
    #endregion send web request

    #region output dots while waiting on import to finish
    $i = 0
    _write "    ." -noNewLine
    do {
        Start-Sleep 5

        if ($i % 3 -eq 0) {
            _write "." -noNewLine -noIndent
        }

        ++$i
    } while (!($requiredModule = Get-AzureAutomationRuntimeCustomModule -automationAccountName $automationAccountName -ResourceGroup $resourceGroupName -runtimeName $runtimeName -moduleName $moduleName -header $header -ErrorAction Stop | ? { $_.Properties.ProvisioningState -in "Succeeded", "Failed" }))

    ""
    #endregion output dots while waiting on import to finish

    if ($requiredModule.Properties.ProvisioningState -ne "Succeeded") {
        Write-Error "Import failed. Check Azure Portal >> Automation Account >> Runtime Environments >> $runtimeName >> $moduleName details to get the reason."
    } else {
        _write " - Success" "Green"
    }
}

function Remove-AzureAutomationRuntime {
    <#
    .SYNOPSIS
    Removes selected Azure Automation Account Runtime(s).

    .DESCRIPTION
    Removes selected Azure Automation Account Runtime(s).

    .PARAMETER runtimeName
    Name of the runtime environment you want to remove.

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Remove-AzureAutomationRuntime

    Removes selected Automation Runtime.

    Missing function arguments like $runtimeName, $resourceGroupName or $automationAccountName will be interactively gathered through Out-GridView GUI.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Remove-AzureAutomationRuntime -runtimeName "PSH51Custom" -resourceGroupName "AdvancedLoggingRG" -automationAccountName "EnableO365AdvancedLogging"

    Removes "PSH51Custom" Automation Runtime from given Automation Account.
    #>

    [CmdletBinding()]
    param (
        [string[]] $runtimeName,

        [string] $resourceGroupName,

        [string] $automationAccountName,

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

    if ($runtimeName) {
        foreach ($runtName in $runtimeName) {
            Write-Verbose "Checking existence of $runtName runtime"
            try {
                $runtime = Get-AzureAutomationRuntime -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -header $header -runtimeName $runtName -ErrorAction Stop
            } catch {
                if ($_.exception.StatusCode -eq 'NotFound') {
                    throw "Runtime '$runtName' doesn't exist"
                } else {
                    throw $_
                }
            }
        }
    } else {
        while (!$runtimeName) {
            $runtimeName = Get-AzureAutomationRuntime -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -header $header -programmingLanguage PowerShell -runtimeSource Custom | select -ExpandProperty Name | Out-GridView -OutputMode Multiple -Title "Select runtime you want to process"
        }
    }
    #endregion get missing arguments

    foreach ($runtName in $runtimeName) {
        Write-Verbose "Removing $runtName runtime"

        Invoke-RestMethod2 -method delete -uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runtimeEnvironments/$runtName`?api-version=2023-05-15-preview" -body $body -headers $header
    }
}

function Remove-AzureAutomationRuntimeModule {
    <#
    .SYNOPSIS
    Function remove selected module from specified Azure Automation runtime.

    .DESCRIPTION
    Function remove selected module from specified Azure Automation runtime.

    .PARAMETER runtimeName
    Name of the runtime environment you want to retrieve.

    If not provided, all runtimes will be returned.

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER moduleName
    Name of the module(s) you want to remove.

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Remove-AzureAutomationRuntimeModule

    Remove selected module(s) from the specified Automation runtime.
    Missing function arguments like $resourceGroupName or $moduleName will be interactively gathered through Out-GridView GUI.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Remove-AzureAutomationRuntimeModule -resourceGroupName "AdvancedLoggingRG" -automationAccountName "EnableO365AdvancedLogging" -runtimeName Custom_PSH_51 -moduleName CommonStuff

    Remove module CommonStuff from the specified Automation runtime.
    #>

    [CmdletBinding()]
    param (
        [string] $runtimeName,

        [string] $resourceGroupName,

        [string] $automationAccountName,

        [string[]] $moduleName,

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
        $runtimeName = Get-AzureAutomationRuntime -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -header $header -programmingLanguage PowerShell -runtimeSource Custom | select -ExpandProperty Name | Out-GridView -OutputMode Single -Title "Select runtime you want to process"
    }

    if (!$moduleName) {
        while (!$moduleName) {
            $moduleName = Get-AzureAutomationRuntimeCustomModule -runtimeName $runtimeName -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -moduleName $moduleName -header $header | select -ExpandProperty Name | Out-GridView -OutputMode Multiple -Title "Select module(s) you want to remove"
        }
    } else {
        $moduleExists = Get-AzureAutomationRuntimeCustomModule -runtimeName $runtimeName -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -moduleName $moduleName -header $header
        if (!$moduleExists) {
            throw "Module $moduleName doesn't exist in specified Automation environment"
        }
    }
    #endregion get missing arguments

    foreach ($modName in $moduleName) {
        Write-Verbose "Removing module $modName"

        Invoke-RestMethod2 -method Delete -uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runtimeEnvironments/$runtimeName/packages/$modName`?api-version=2023-05-15-preview" -headers $header
    }
}

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

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
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

function Set-AzureAutomationRunbookRuntime {
    <#
    .SYNOPSIS
    Set Runtime Environment in the selected Azure Automation Account Runbook.

    .DESCRIPTION
    Set Runtime Environment in the selected Azure Automation Account Runbook.

    .PARAMETER runtimeName
    Runtime name you want to use.

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER runbookName
    Runbook name.

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Set-AzureAutomationRunbookRuntime

    Set selected Runtime Environment in selected Runbook.
    Missing function arguments like $runtimeName, $resourceGroupName, $automationAccountName or $runbookName will be interactively gathered through Out-GridView GUI.
    #>

    [CmdletBinding()]
    param (
        [string] $runtimeName,

        [string] $resourceGroupName,

        [string] $automationAccountName,

        [string] $runbookName,

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

    while (!$runbookName) {
        $runbookName = Get-AzAutomationRunbook -AutomationAccountName $automationAccountName -ResourceGroupName $resourceGroupName | select -ExpandProperty Name | Out-GridView -OutputMode Single -Title "Select runbook you want to change"
    }
    #endregion get missing arguments

    $runbookType = Get-AzAutomationRunbook -AutomationAccountName $automationAccountName -ResourceGroupName $resourceGroupName -Name $runbookName | select -ExpandProperty RunbookType

    if ($runbookType -eq 'python2') {
        $programmingLanguage = 'Python'
    } else {
        $programmingLanguage = $runbookType
    }

    $currentRuntimeName = Get-AzureAutomationRunbookRuntime -automationAccountName $automationAccountName -resourceGroupName $resourceGroupName -runbookName $runbookName -header $header

    if ($runtimeName -and $runtimeName -eq $currentRuntimeName) {
        Write-Warning "Runtime '$runtimeName' is already set. Skipping."
        return
    } else {
        while (!$runtimeName) {
            $runtimeName = Get-AzureAutomationRuntime -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -header $header -programmingLanguage $programmingLanguage | select -ExpandProperty Name | ? { $_ -notin $currentRuntimeName } | Out-GridView -OutputMode Single -Title "Select runtime you want to set (current is '$currentRuntimeName')"
        }
    }

    #region send web request
    $body = @{
        "properties" = @{
            runtimeEnvironment = $runtimeName
        }
    }
    if ($programmingLanguage -eq 'Python') {
        # fix for bug? "The property runtimeEnvironment cannot be configured for runbookType Python2. Either use runbookType Python or remove runtimeEnvironment from input."
        $body.properties.runbookType = 'Python'
    }
    $body = $body | ConvertTo-Json

    Write-Verbose $body

    Invoke-RestMethod2 -method PATCH -uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runbooks/$runbookName`?api-version=2023-05-15-preview" -body $body -headers $header
    #endregion send web request
}

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

function Set-AzureAutomationRuntimeDescription {
    <#
    .SYNOPSIS
    Function set Azure Automation Account Runtime description.

    .DESCRIPTION
    Function set Azure Automation Account Runtime description.

    .PARAMETER runtimeName
    Name of the runtime environment you want to update.

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER description
    Runtime description.

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Set-AzureAutomationRuntimeDescription -description "testing runtime"

    Set given description in given Automation Runtime.
    Missing function arguments like $resourceGroupName or $automationAccountName will be interactively gathered through Out-GridView GUI.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Set-AzureAutomationRuntimeDescription -resourceGroupName "AdvancedLoggingRG" -automationAccountName "EnableO365AdvancedLogging" -description "testing runtime"

    Set given description in given Automation Runtime.
    #>

    [CmdletBinding()]
    param (
        [string] $runtimeName,

        [string] $resourceGroupName,

        [string] $automationAccountName,

        [Parameter(Mandatory = $true)]
        [string] $description,

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

    #region send web request
    $body = @{
        "properties" = @{
            "description" = $description
        }
    }
    $body = $body | ConvertTo-Json

    Write-Verbose $body

    Invoke-RestMethod2 -method Patch -uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runtimeEnvironments/$runtimeName`?api-version=2023-05-15-preview" -body $body -headers $header
    #endregion send web request
}

function Update-AzureAutomationModule {
    [CmdletBinding()]
    param (
        [string[]] $moduleName,

        [string] $moduleVersion,

        [switch] $allModule,

        [switch] $allCustomModule,

        [Parameter(Mandatory = $true)]
        [string] $resourceGroupName,

        [string[]] $automationAccountName,

        [ValidateSet('5.1', '7.2')]
        [string] $runtimeVersion = '5.1'
    )

    if ($allCustomModule -and $moduleName) {
        throw "Choose moduleName or allCustomModule"
    }
    if ($allCustomModule -and $allModule) {
        throw "Choose allModule or allCustomModule"
    }

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    $subscription = $((Get-AzContext).Subscription.Name)

    $automationAccount = Get-AzAutomationAccount -ResourceGroupName $resourceGroupName

    if (!$automationAccount) {
        throw "No Automation account found in the current Subscription '$subscription' and Resource group '$resourceGroupName'"
    }

    if ($automationAccountName) {
        $automationAccount = $automationAccount | ? AutomationAccountName -EQ $automationAccountName
    }

    if (!$automationAccount) {
        throw "No Automation account match the selected criteria"
    }

    foreach ($atmAccount in $automationAccount) {
        $atmAccountName = $atmAccount.AutomationAccountName
        $atmAccountResourceGroup = $atmAccount.ResourceGroupName

        "Processing Automation account '$atmAccountName' (ResourceGroup: '$atmAccountResourceGroup' Subscription: '$subscription')"

        $currentAutomationModules = Get-AzAutomationModule -AutomationAccountName $atmAccountName -ResourceGroup $atmAccountResourceGroup -RuntimeVersion $runtimeVersion

        if ($allCustomModule) {
            $automationModulesToUpdate = $currentAutomationModules | ? IsGlobal -EQ $false
        } elseif ($moduleName) {
            $automationModulesToUpdate = $currentAutomationModules | ? Name -In $moduleName
            if ($moduleVersion -and $automationModulesToUpdate) {
                Write-Verbose "Selecting only module(s) with version $moduleVersion or lower"
                $automationModulesToUpdate = $automationModulesToUpdate | ? { [version]$_.Version -lt [version] $moduleVersion }
            }
        } elseif ($allModule) {
            $automationModulesToUpdate = $currentAutomationModules
        } else {
            $automationModulesToUpdate = $currentAutomationModules | Out-GridView -PassThru
            if ($moduleVersion -and $automationModulesToUpdate) {
                Write-Verbose "Selecting only module(s) with version $moduleVersion or lower"
                $automationModulesToUpdate = $automationModulesToUpdate | ? { [version]$_.Version -lt [version] $moduleVersion }
            }
        }

        if (!$automationModulesToUpdate) {
            Write-Warning "No module match the selected update criteria. Skipping"
            continue
        }

        foreach ($module in $automationModulesToUpdate) {
            $moduleName = $module.Name
            $requiredModuleVersion = $moduleVersion

            #region get PSGallery module data
            $param = @{
                # IncludeDependencies = $true # cannot be used, because always returns newest available modules, I want to use existing modules if possible (to minimize risk that something will stop working)
                Name        = $moduleName
                ErrorAction = "Stop"
            }
            if ($requiredModuleVersion) {
                $param.RequiredVersion = $requiredModuleVersion
            } else {
                $param.AllVersions = $true
            }

            $moduleGalleryInfo = Find-Module @param
            #endregion get PSGallery module data

            # get newest usable module version for given runtime
            if (!$requiredModuleVersion -and $runtimeVersion -eq '5.1') {
                # no specific version was selected and older PSH version is used, make sure module that supports it, will be found
                # for example (currently newest) pnp.powershell 2.3.0 supports only PSH 7.2
                $moduleGalleryInfo = $moduleGalleryInfo | ? { $_.AdditionalMetadata.PowerShellVersion -le $runtimeVersion } | select -First 1
            }

            if (!$moduleGalleryInfo) {
                Write-Error "No supported $moduleName module was found in PSGallery"
                continue
            }

            if (!$requiredModuleVersion) {
                # no version specified, newest version from PSGallery will be used"
                $requiredModuleVersion = $moduleGalleryInfo.Version | select -First 1

                if ($requiredModuleVersion -eq $module.Version) {
                    Write-Warning "Module $moduleName already has newest available version $requiredModuleVersion. Skipping"
                    continue
                }
            }

            $param = @{
                resourceGroupName     = $module.ResourceGroupName
                automationAccountName = $module.AutomationAccountName
                moduleName            = $module.Name
                runtimeVersion        = $runtimeVersion
                moduleVersion         = $requiredModuleVersion
            }

            "Updating module $($module.Name) $($module.Version) >> $requiredModuleVersion"
            New-AzureAutomationModule @param
        }
    }
}

function Update-AzureAutomationRunbookModule {
    <#
    .SYNOPSIS
    Function updates all/selected custom modules in given Azure Automation Account Environment Runtime.

    Custom module means module you have to explicitly import (not 'Az' or 'azure cli').

    .DESCRIPTION
    Function updates all/selected custom modules in given Azure Automation Account Environment Runtime.

    Custom module means module you have to explicitly import (not 'Az' or 'azure cli').

    .PARAMETER moduleName
    Name of the module you want to add/(replace by other version).

    .PARAMETER moduleVersion
    Target module version you want to update to.

    Applies to all updated modules!

    If not specified, newest supported version for used runtime language version will be gathered from PSGallery.

    .PARAMETER allCustomModule
    Parameter description

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER runtimeName
    Name of the runtime environment you want to retrieve.

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Update-AzureAutomationRunbookModule -moduleName CommonStuff -moduleVersion 1.0.18

    Updates module CommonStuff to the version 1.0.18 in the specified Automation runtime(s).
    If module has some dependencies, that are currently missing (or have incorrect version), they will be imported automatically.

    Missing function arguments like $runtimeName, $resourceGroupName or $automationAccountName will be interactively gathered through Out-GridView GUI.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Update-AzureAutomationRunbookModule -moduleName CommonStuff

    Updates module CommonStuff to the newest available version in the specified Automation runtime(s).
    If module has some dependencies, that are currently missing (or have incorrect version), they will be imported automatically.

    Missing function arguments like $runtimeName, $resourceGroupName or $automationAccountName will be interactively gathered through Out-GridView GUI.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Update-AzureAutomationRunbookModule -allCustomModule

    Updates all custom modules to the newest available version in the specified Automation runtime(s).
    If module(s) have some dependencies, that are currently missing (or have incorrect version), they will be imported automatically.

    Missing function arguments like $runtimeName, $resourceGroupName or $automationAccountName will be interactively gathered through Out-GridView GUI.
    #>

    [CmdletBinding()]
    param (
        [string[]] $moduleName,

        [string] $moduleVersion,

        [switch] $allCustomModule,

        [string] $resourceGroupName,

        [string] $automationAccountName,

        [string[]] $runtimeName,

        [hashtable] $header
    )

    if ($allCustomModule -and $moduleName) {
        throw "Choose moduleName or allCustomModule"
    }

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    #region get missing arguments
    if (!$header) {
        $header = New-AzureAutomationGraphToken
    }

    $subscriptionId = (Get-AzContext).Subscription.Id
    $subscription = $((Get-AzContext).Subscription.Name)

    while (!$resourceGroupName) {
        $resourceGroupName = Get-AzResourceGroup | select -ExpandProperty ResourceGroupName | Out-GridView -OutputMode Single -Title "Select resource group you want to process"
    }

    while (!$automationAccountName) {
        $automationAccountName = Get-AzAutomationAccount -ResourceGroupName $resourceGroupName | select -ExpandProperty AutomationAccountName | Out-GridView -OutputMode Single -Title "Select automation account you want to process"
    }

    while (!$runtimeName) {
        $runtimeName = Get-AzureAutomationRuntime -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -programmingLanguage PowerShell -runtimeSource Custom -header $header | select -ExpandProperty Name | Out-GridView -OutputMode Multiple -Title "Select environment you want to process"
    }

    $runtimeVersion = $runtime.properties.runtime.version
    #endregion get missing arguments

    foreach ($runtName in $runtimeName) {
        "Processing Runtime '$runtName' (ResourceGroup: '$resourceGroupName' Subscription: '$subscription')"

        $currentAutomationCustomModules = Get-AzureAutomationRuntimeCustomModule -automationAccountName $automationAccountName -ResourceGroup $resourceGroupName -runtimeName $runtName -header $header -ErrorAction Stop

        if ($allCustomModule) {
            $automationModulesToUpdate = $currentAutomationCustomModules
        } elseif ($moduleName) {
            $automationModulesToUpdate = $currentAutomationCustomModules | ? Name -In $moduleName

            if ($moduleVersion -and $automationModulesToUpdate) {
                Write-Verbose "Selecting only module(s) with version $moduleVersion or lower"
                $automationModulesToUpdate = $automationModulesToUpdate | ? { [version]$_.Version -lt [version] $moduleVersion }
            }
        } else {
            $automationModulesToUpdate = $currentAutomationCustomModules | Out-GridView -PassThru -Title "Select module(s) to update"

            if ($moduleVersion -and $automationModulesToUpdate) {
                Write-Verbose "Selecting only module(s) with version $moduleVersion or lower"
                $automationModulesToUpdate = $automationModulesToUpdate | ? { [version]$_.Version -lt [version] $moduleVersion }
            }
        }

        if (!$automationModulesToUpdate) {
            Write-Warning "No module match the selected update criteria. Skipping"
            continue
        }

        foreach ($module in $automationModulesToUpdate) {
            $moduleName = $module.Name
            $requiredModuleVersion = $moduleVersion

            #region get PSGallery module data
            $param = @{
                # IncludeDependencies = $true # cannot be used, because always returns newest available modules, I want to use existing modules if possible (to minimize risk that something will stop working)
                Name        = $moduleName
                ErrorAction = "Stop"
            }
            if ($requiredModuleVersion) {
                $param.RequiredVersion = $requiredModuleVersion
            } else {
                $param.AllVersions = $true
            }

            $moduleGalleryInfo = Find-Module @param
            #endregion get PSGallery module data

            # get newest usable module version for given runtime
            if (!$requiredModuleVersion -and $runtimeVersion -eq '5.1') {
                # no specific version was selected and older PSH version is used, make sure module that supports it, will be found
                # for example (currently newest) pnp.powershell 2.3.0 supports only PSH 7.2
                $moduleGalleryInfo = $moduleGalleryInfo | ? { $_.AdditionalMetadata.PowerShellVersion -le $runtimeVersion } | select -First 1
            }

            if (!$moduleGalleryInfo) {
                Write-Error "No supported $moduleName module was found in PSGallery"
                continue
            }

            if (!$requiredModuleVersion) {
                # no version specified, newest version from PSGallery will be used"
                $requiredModuleVersion = $moduleGalleryInfo.Version | select -First 1

                if ($requiredModuleVersion -eq $module.Version) {
                    Write-Warning "Module $moduleName already has newest available version $requiredModuleVersion. Skipping"
                    continue
                }
            }

            $param = @{
                resourceGroupName     = $resourceGroupName
                automationAccountName = $automationAccountName
                runtimeName           = $runtName
                moduleName            = $module.Name
                moduleVersion         = $requiredModuleVersion
                header                = $header
            }

            "Updating module $($module.Name) $($module.Version) >> $requiredModuleVersion"
            New-AzureAutomationRuntimeModule @param
        }
    }
}

Export-ModuleMember -function Copy-AzureAutomationRuntime, Export-VariableToStorage, Get-AutomationVariable2, Get-AzureAutomationRunbookRuntime, Get-AzureAutomationRuntime, Get-AzureAutomationRuntimeAvailableDefaultModule, Get-AzureAutomationRuntimeCustomModule, Get-AzureAutomationRuntimeSelectedDefaultModule, Get-AzureResource, Import-VariableFromStorage, New-AzureAutomationGraphToken, New-AzureAutomationModule, New-AzureAutomationRuntime, New-AzureAutomationRuntimeModule, Remove-AzureAutomationRuntime, Remove-AzureAutomationRuntimeModule, Set-AutomationVariable2, Set-AzureAutomationRunbookRuntime, Set-AzureAutomationRuntimeDefaultModule, Set-AzureAutomationRuntimeDescription, Update-AzureAutomationModule, Update-AzureAutomationRunbookModule

Export-ModuleMember -alias Get-AzureAutomationRuntimeAzModule, New-AzAutomationModule2, Set-AzureAutomationModule, Set-AzureAutomationRuntimeModule
