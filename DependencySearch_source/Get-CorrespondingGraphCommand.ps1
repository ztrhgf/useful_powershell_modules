function Get-CorrespondingGraphCommand {
    <#
    .SYNOPSIS
    Function finds corresponding Graph command for MSOnline and AzureAD commands.

    .DESCRIPTION
    Function finds corresponding Graph command for MSOnline and AzureAD commands.

    .PARAMETER commandName
    MSOnline or AzureAD command name.

    .EXAMPLE
    Get-CorrespondingGraphCommand Get-MsolUser

    Finds corresponding Graph command for Get-MsolUser command. A.k.a. Get-MgUser.

    .EXAMPLE
    $scripts = Get-ChildItem C:\scripts -Recurse -Filter "*.ps1" -file | ? name -Match "\.ps1$" | select -exp FullName

    $moduleList = @()
    "AzureAD", "AzureADPreview", "MSOnline", "AzureRM" | % {
        $module = Get-Module $_ -ListAvailable
        if ($module) {
            $moduleList += $module
        } else {
            Write-Warning "Module $_ isn't available on you system. Add it to `$env:PSModulePath or install using Install-Module?"
        }
    }

    $scripts | % {
        Get-ModuleCommandUsedInCode -scriptPath $_ -module $moduleList | Select-Object *, @{n = 'GraphCommand'; e = { (Get-CorrespondingGraphCommand $_.command).GraphCommand } } | Format-Table -AutoSize
    }

    Search all ps1 scripts in C:\scripts folder for commands defined in modules "AzureAD", "AzureADPreview", "MSOnline", "AzureRM". Show where they are used and if possible also equivalent Graph command.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $commandName
    )

    $cacheFile = "$env:TEMP\graphcommandmap.xml"

    if ((Test-Path $cacheFile -ea SilentlyContinue) -and ((Get-Item $cacheFile).LastWriteTime -gt [datetime]::Today.AddDays(-30))) {
        Write-Verbose "Using $cacheFile"
        $table = Import-Clixml $cacheFile
    } else {
        Write-Verbose "Getting command map"
        $uri = "https://learn.microsoft.com/en-au/powershell/microsoftgraph/azuread-msoline-cmdlet-map?view=graph-powershell-beta"
        $pageContent = (Invoke-WebRequest -Method GET -Uri $uri -UseBasicParsing).content
        $table = ConvertFrom-HTMLTable $pageContent -useHTMLAgilityPack -asArrayOfTables -all
        $table | Export-Clixml $cacheFile -Force
    }

    $table | % { $_ | select @{n = "Command"; e = { if ($_."Azure AD cmdlet") { $_."Azure AD cmdlet" } elseif ($_."MSOnline cmdlet") { $_."MSOnline cmdlet" } else { $_."Azure AD Preview cmdlet" } } }, @{n = "GraphCommand"; e = { $_."Microsoft Graph PowerShell cmdlet" } } } | select *, @{n = 'Note'; e = { if ($_.Command -like "* 1") { "This cmdlet has more than one cmdlet mapping in Microsoft Graph PowerShell" } elseif ($_.Command -like "* 2") { "Privileged Identity Management (PIM) iteration 3 APIs (https://learn.microsoft.com/en-us/graph/api/resources/privilegedidentitymanagementv3-overview?view=graph-rest-1.0) should be used. Check this guidance (https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-apis) for more details." } } } | select @{n = "Command"; e = { $_.Command -replace " \d+$" } }, GraphCommand, Note | ? Command -EQ $commandName
}