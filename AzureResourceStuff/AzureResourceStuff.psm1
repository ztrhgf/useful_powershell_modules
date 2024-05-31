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
    [Alias("New-AzAutomationModule2")]
    param (
        [Parameter(Mandatory = $true)]
        [string] $moduleName,

        [string] $moduleVersion,

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
        $param.RequiredVersion = $moduleVersion
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

    # override module version
    if (!$moduleVersion -and $moduleName -in $overridePSGalleryModuleVersion.Keys -and $overridePSGalleryModuleVersion.$moduleName.$runtimeVersion) {
        $overriddenModule = $overridePSGalleryModuleVersion.$moduleName
        $overriddenModuleVersion = $overriddenModule.$runtimeVersion
        if ($overriddenModuleVersion) {
            _write " (no version specified and override for version exists, hence will be used ($overriddenModuleVersion))"
            $moduleVersion = $overriddenModuleVersion
        }
    }

    if (!$moduleVersion) {
        $moduleVersion = $moduleGalleryInfo.Version
        _write " (no version specified, newest supported version from PSGallery will be used ($moduleVersion))"
    }

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
                }
                if ($requiredModuleMaxVersion) {
                    $param.moduleVersion = $requiredModuleMaxVersion
                }
                if ($requiredModuleReqVersion) {
                    $param.moduleVersion = $requiredModuleReqVersion
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
                $requiredModuleVersion = $moduleGalleryInfo.Version

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

Export-ModuleMember -function Export-VariableToStorage, Get-AutomationVariable2, Get-AzureResource, Import-VariableFromStorage, New-AzureAutomationModule, Set-AutomationVariable2, Update-AzureAutomationModule

Export-ModuleMember -alias New-AzAutomationModule2
