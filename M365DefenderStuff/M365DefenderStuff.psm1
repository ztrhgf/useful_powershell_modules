function Get-M365DefenderMachine {
    <#
    .SYNOPSIS
    Get list of just one/all machine/s.

    .DESCRIPTION
    Get list of just one/all machine/s.

    .PARAMETER machineId
    (optional) specific machine ID you want to retrieve.

    .PARAMETER header
    Header created using New-M365DefenderAuthHeader.

    .PARAMETER apiUrl
    API url.

    By default "api-eu.securitycenter.microsoft.com" for best performance in EU region.

    .EXAMPLE
    $header = New-M365DefenderAuthHeader

    $allMachines = Get-M365DefenderMachine -header $header

    Get all machines from defender portal.

    .EXAMPLE
    $header = New-M365DefenderAuthHeader

    $machine = Get-M365DefenderMachine -header $header -machineId 09a3a0af67c7bc1e5efc1a334114d00df3042cc8

    Get just one specific machine from defender portal.

    .NOTES
    Requires Machine.Read.All permission.

    https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/api/get-machine-by-id?view=o365-worldwide
    #>

    [CmdletBinding()]
    param (
        [string] $machineId,

        $header,

        [ValidateSet("api.securitycenter.microsoft.com", "api-eu.securitycenter.microsoft.com", "api-us.securitycenter.microsoft.com", "api-uk.securitycenter.microsoft.com", "api-au.securitycenter.microsoft.com")]
        [string] $apiUrl = "api-eu.securitycenter.microsoft.com"
    )

    if (!$header) {
        $header = New-M365DefenderAuthHeader -ErrorAction Stop
    }

    $url = "https://$apiUrl/api/machines"
    if ($machineId) {
        $url = $url + "/$machineId"
    }

    Invoke-RestMethod2 -uri $url -headers $header
}

function Get-M365DefenderMachineUser {
    <#
    .SYNOPSIS
    Retrieves a list of all users that logged in to the specified computer.

    .DESCRIPTION
    Retrieves a list of all users that logged in to the specified computer.

    .PARAMETER header
    Header created using New-M365DefenderAuthHeader.

    .PARAMETER machineId
    Machine ID.

    .PARAMETER apiUrl
    API url.

    By default "api-eu.securitycenter.microsoft.com" for best performance in EU region.

    .EXAMPLE
    $header = New-M365DefenderAuthHeader

    Get-M365DefenderMachineUser -header $header -machineId 23de7fcd303b5cee7b7aee032276bf2690448582

    Get all users for specified device.

    .EXAMPLE
    $header = New-M365DefenderAuthHeader

    Get-M365DefenderMachineUser -header $header

    Get all computers and their users.

    .NOTES
    Requires User.Read.All.

    https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/api/get-machine-log-on-users?view=o365-worldwide
    #>

    [CmdletBinding()]
    param (
        $header,

        [string[]] $machineId,

        [ValidateSet("api.securitycenter.microsoft.com", "api-eu.securitycenter.microsoft.com", "api-us.securitycenter.microsoft.com", "api-uk.securitycenter.microsoft.com", "api-au.securitycenter.microsoft.com")]
        [string] $apiUrl = "api-eu.securitycenter.microsoft.com"
    )

    if (!$header) {
        $header = New-M365DefenderAuthHeader -ErrorAction Stop
    }

    if (!$machineId) {
        $machineId = Get-M365DefenderMachine -header $header | select -ExpandProperty Id
    }

    foreach ($id in $machineId) {
        $url = "https://$apiUrl/api/machines/$id/logonusers"

        Invoke-RestMethod2 -uri $url -headers $header | select *, @{n = 'MachineId'; e = { $id } }
    }
}

function Get-M365DefenderMachineVulnerability {
    <#
    .SYNOPSIS
    Retrieves a list of all the vulnerabilities affecting the organization per machine and software.

    .DESCRIPTION
    Retrieves a list of all the vulnerabilities affecting the organization per machine and software.

    .PARAMETER header
    Header created using New-M365DefenderAuthHeader.

    .PARAMETER severity
    Filter vulnerabilities by severity.

    Possible values: 'Low', 'Medium', 'High', 'Critical'

    .PARAMETER apiUrl
    API url.

    By default "api-eu.securitycenter.microsoft.com" for best performance in EU region.

    .EXAMPLE
    $header = New-M365DefenderAuthHeader

    $allMachineVulnerabilities = Get-M365DefenderMachineVulnerability -header $header

    .NOTES
    Requires Vulnerability.Read.All permission.

    https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/api/get-all-vulnerabilities-by-machines?view=o365-worldwide
    #>

    [CmdletBinding()]
    param (
        $header,

        [ValidateSet('Low', 'Medium', 'High', 'Critical', ignorecase = $False)]
        [string[]] $severity,

        [ValidateSet("api.securitycenter.microsoft.com", "api-eu.securitycenter.microsoft.com", "api-us.securitycenter.microsoft.com", "api-uk.securitycenter.microsoft.com", "api-au.securitycenter.microsoft.com")]
        [string] $apiUrl = "api-eu.securitycenter.microsoft.com"
    )

    if (!$header) {
        $header = New-M365DefenderAuthHeader -ErrorAction Stop
    }

    $url = "https://$apiUrl/api/vulnerabilities/machinesVulnerabilities"

    if ($severity) {
        $sevF = ""
        $severity | % {
            if ($sevF) { $sevF = $sevF + " or " }

            $sevF += "severity eq '$_'"
        }
        $url = $url + "?`$filter=($sevF)"
    }

    Invoke-RestMethod2 -Uri $url -Headers $header
}

function Get-M365DefenderRecommendation {
    <#
    .SYNOPSIS
    Get list of all/just selected (by name or machine) recommendation/s.

    .DESCRIPTION
    Get list of all/just selected (by name or machine) recommendation/s.

    .PARAMETER productName
    Name of the product to search recommendations for.

    .PARAMETER machineId
    Id of the machine you want recommendations for.

    .PARAMETER header
    Header created using New-M365DefenderAuthHeader.

    .PARAMETER apiUrl
    API url.

    By default "api-eu.securitycenter.microsoft.com" for best performance in EU region.

    .EXAMPLE
    Get-M365DefenderRecommendation

    Get all security recommendations.

    .EXAMPLE
    Get-M365DefenderRecommendation -productName putty

    Get security recommendations just for Putty software.

    .EXAMPLE
    Get-M365DefenderRecommendation -machineId 43a802402664e76a021c8dda2e2aa7db6a09a5a4

    Get all security recommendations for given machine.

    .NOTES
    Requires SecurityRecommendation.Read.All permission.

    https://learn.microsoft.com/en-us/defender-endpoint/api/get-all-recommendations?view=o365-worldwide
    #>

    [CmdletBinding(DefaultParameterSetName = 'productName')]
    param (
        [Parameter(Mandatory = $false, ParameterSetName = "productName")]
        [string] $productName,

        [Parameter(Mandatory = $true, ParameterSetName = "machineId")]
        [string] $machineId,

        $header,

        [ValidateSet("api.securitycenter.microsoft.com", "api-eu.securitycenter.microsoft.com", "api-us.securitycenter.microsoft.com", "api-uk.securitycenter.microsoft.com", "api-au.securitycenter.microsoft.com")]
        [string] $apiUrl = "api-eu.securitycenter.microsoft.com"
    )

    if (!$header) {
        $header = New-M365DefenderAuthHeader -ErrorAction Stop
    }

    if ($machineId) {
        $url = "https://$apiUrl/api/machines/$machineId/recommendations"
    } else {
        $url = "https://$apiUrl/api/recommendations"
        if ($productName) {
            $url = $url + '?$filter=' + "productName eq '$productName'"
        }
    }

    Invoke-RestMethod2 -uri $url -headers $header
}

function Get-M365DefenderSoftware {
    <#
    .SYNOPSIS
    Get list of just specific/all application/s.

    .DESCRIPTION
    Get list of just specific/all machine/s.

    .PARAMETER softwareId
    (optional) specific software ID you want to retrieve.

    .PARAMETER header
    Header created using New-M365DefenderAuthHeader.

    .PARAMETER apiUrl
    API url.

    By default "api-eu.securitycenter.microsoft.com" for best performance in EU region.

    .EXAMPLE
    $header = New-M365DefenderAuthHeader

    $allApplications = Get-M365DefenderSoftware -header $header

    Get all applications from defender portal.

    .EXAMPLE
    $header = New-M365DefenderAuthHeader

    $application = Get-M365DefenderSoftware -softwareId samsung-_-petservice -header $header

    Get just one specific application from defender portal.

    .NOTES
    Requires Software.Read.All permission.

    https://learn.microsoft.com/en-us/defender-endpoint/api/get-software?view=o365-worldwide
    #>

    [CmdletBinding()]
    param (
        [string] $softwareId,

        $header,

        [ValidateSet("api.securitycenter.microsoft.com", "api-eu.securitycenter.microsoft.com", "api-us.securitycenter.microsoft.com", "api-uk.securitycenter.microsoft.com", "api-au.securitycenter.microsoft.com")]
        [string] $apiUrl = "api-eu.securitycenter.microsoft.com"
    )

    if (!$header) {
        $header = New-M365DefenderAuthHeader -ErrorAction Stop
    }

    $url = "https://$apiUrl/api/software"
    if ($softwareId) {
        $url = $url + "/$softwareId"
    }

    Invoke-RestMethod2 -uri $url -headers $header
}

function Get-M365DefenderVulnerability {
    <#
    .SYNOPSIS
    Get list of all/just one vulnerabilities/y.

    .DESCRIPTION
    Get list of all/just one vulnerabilities/y.

    .PARAMETER vulnerabilityId
    (optional) specific vulnerability ID you want to retrieve.

    .PARAMETER header
    Header created using New-M365DefenderAuthHeader.

    .PARAMETER apiUrl
    API url.

    By default "api-eu.securitycenter.microsoft.com" for best performance in EU region.

    .EXAMPLE
    $header = New-M365DefenderAuthHeader

    $allVulnerabilities = Get-M365DefenderVulnerability -header $header

    Get all vulnerabilities.

    .EXAMPLE
    $header = New-M365DefenderAuthHeader
    Get-M365DefenderVulnerability -header $header -vulnerabilityId "CVE-2022-40674"

    Get vulnerability "CVE-2022-40674" details.

    .NOTES
    Requires Vulnerability.Read.All permission.

    It can can take several minutes (there is more than 200 000 vulnerabilities now)!

    https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/api/get-all-vulnerabilities?view=o365-worldwide
    #>

    [CmdletBinding()]
    param (
        [string] $vulnerabilityId,

        $header,

        [ValidateSet("api.securitycenter.microsoft.com", "api-eu.securitycenter.microsoft.com", "api-us.securitycenter.microsoft.com", "api-uk.securitycenter.microsoft.com", "api-au.securitycenter.microsoft.com")]
        [string] $apiUrl = "api-eu.securitycenter.microsoft.com"
    )

    if (!$header) {
        $header = New-M365DefenderAuthHeader -ErrorAction Stop
    }

    $url = "https://$apiUrl/api/vulnerabilities"
    if ($vulnerabilityId) {
        $url = $url + "/$vulnerabilityId"
    }

    # for some reason it doesn't provides '@odata.nextLink' so I need to loop through "manually"
    # returned output is limited to 8000 items per call
    $apiDefaultLimit = 8000
    $round = 0
    do {
        $urlFinal = $url

        if (!$vulnerabilityId) {
            # doesn't make sense deal with skip if only one vulnerability will be outputted
            $urlFinal = $urlFinal + '?$skip=' + ($apiDefaultLimit * $round)
        }

        Write-Verbose "Retrieval round: $round url: $urlFinal"

        $result = Invoke-RestMethod2 -uri $urlFinal -headers $header

        $result

        ++$round
    } while ($result -and !$vulnerabilityId -and !($result.count % $apiDefaultLimit))
}

function Get-M365DefenderVulnerabilityReport {
    <#
    .SYNOPSIS
    Function process vulnerabilities returned by Get-M365DefenderMachineVulnerability, process them and returns as custom PSObject.

    .DESCRIPTION
    Function process vulnerabilities returned by Get-M365DefenderMachineVulnerability, process them and returns as custom PSObject.

    .PARAMETER groupBy
    Possible values: machine, productName

    .PARAMETER severity
    Possible values: Low, Medium, High, Critical

    By default Critical.

    .PARAMETER skipOSVuln
    Switch for skipping Operating System vulnerabilities.

    .PARAMETER header
    Header created using New-M365DefenderAuthHeader.

    .EXAMPLE
    $header = New-M365DefenderAuthHeader

    $vulnerabilityPerMachine = Get-M365DefenderVulnerabilityReport -groupBy machine -header $header -skipOSVuln -severity Critical
    #>

    [CmdletBinding()]
    param (
        [ValidateSet('machine', 'productName')]
        [string] $groupBy,

        [ValidateSet('Low', 'Medium', 'High', 'Critical', ignorecase = $False)]
        [string[]] $severity = "Critical",

        [switch] $skipOSVuln,

        $header
    )

    if (!$header) {
        $header = New-M365DefenderAuthHeader -ErrorAction Stop
    }

    $machineVulnerability = Get-M365DefenderMachineVulnerability -header $header -severity $severity

    if ($skipOSVuln) {
        $machineVulnerability = $machineVulnerability | ? productName -NotIn "windows_10", "windows_11", "mac_os"
    }

    # get all machines to be able to translate id to dnsname
    $allMachines = Get-M365DefenderMachine -header $header

    if ($groupBy -eq "machine") {
        $vulnGroupedByMachineId = $machineVulnerability | group MachineId

        foreach ($groupedData in $vulnGroupedByMachineId) {
            $machineId = $groupedData.Name

            $groupSw = $groupedData.group | group productName, productVersion
            $VulnSW = $groupSw | % {
                [PSCustomObject]@{
                    VulnSW         = (@($_.Group.productName)[0] + ", " + @($_.Group.productVersion)[0])
                    productName    = @($_.Group.productName)[0]
                    productVersion = @($_.Group.productVersion)[0]
                    productVendor  = @($_.Group.productVendor)[0]
                    cveId          = $_.Group.cveId
                    fixingKbId     = $_.Group.fixingKbId
                }
            }

            [PSCustomObject]@{
                ComputerName = ($allMachines.where({ $_.Id -eq $machineId })).computerDnsName
                MachineId    = $machineId
                VulnSW       = $groupSw.Name
                VulnSWData   = $VulnSW
            }
        }
    } elseif ($groupBy -eq "productName") {
        $vulnGroupedByProdName = $machineVulnerability | group productName

        foreach ($groupedData in $vulnGroupedByProdName) {
            $productName = $groupedData.Name

            $groupSw = $groupedData.group | group productName, productVersion
            $VulnSW = $groupSw | % {
                $machineId = $_.group.machineid | select -Unique
                [PSCustomObject]@{
                    VulnSW         = (@($_.Group.productName)[0] + ", " + @($_.Group.productVersion)[0])
                    productName    = @($_.Group.productName)[0]
                    productVersion = @($_.Group.productVersion)[0]
                    productVendor  = @($_.Group.productVendor)[0]
                    cveId          = $_.Group.cveId | select -Unique
                    fixingKbId     = $_.Group.fixingKbId
                    machineid      = $machineId
                    ComputerName   = ($allMachines.where({ $_.Id -in $machineId })).computerDnsName
                }
            }

            [PSCustomObject]@{
                ProductName  = $productName
                ComputerName = (($allMachines.where({ $_.Id -in $groupedData.group.machineid })).computerDnsName | sort)
                MachineId    = $groupedData.group.machineid | select -Unique
                VulnSW       = $groupSw.Name
                VulnSWData   = $VulnSW
            }
        }
    } else {
        # don't group the results
        $machineVulnerability | select *, @{n = 'ComputerName'; e = { $machineId = $_.MachineId; ($allMachines.where({ $_.Id -eq $machineId })).computerDnsName } }
    }
}

function Invoke-M365DefenderAdvancedQuery {
    <#
    .SYNOPSIS
    Returns result of the specified KQL.

    .DESCRIPTION
    Returns result of the specified KQL.

    .PARAMETER header
    Header created using New-M365DefenderAuthHeader.

    .PARAMETER apiUrl
    API url.

    By default "api-eu.securitycenter.microsoft.com" for best performance in EU region.

    .EXAMPLE
    $header = New-M365DefenderAuthHeader

    Invoke-M365DefenderAdvancedQuery -header $header -query "DeviceInfo | join kind = fullouter DeviceTvmSoftwareEvidenceBeta on DeviceId"

    Returns result of the selected KQL query.

    .NOTES
    Requires AdvancedQuery.Read.All permission.

    https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/api/run-advanced-query-api?view=o365-worldwide
    #>

    [CmdletBinding()]
    param (
        [string] $query,

        $header,

        [ValidateSet("api.securitycenter.microsoft.com", "api-eu.securitycenter.microsoft.com", "api-us.securitycenter.microsoft.com", "api-uk.securitycenter.microsoft.com", "api-au.securitycenter.microsoft.com")]
        [string] $apiUrl = "api-eu.securitycenter.microsoft.com"
    )

    if (!$header) {
        $header = New-M365DefenderAuthHeader -ErrorAction Stop
    }

    $url = "https://$apiUrl/api/advancedqueries/run"

    $queryBody = ConvertTo-Json -InputObject @{ 'Query' = $query }

    Write-Verbose "Query: $query"

    Invoke-RestMethod2 -uri $url -headers $header -method POST -body $queryBody -ErrorAction Stop | select -ExpandProperty Results
}

function Invoke-M365DefenderSoftwareEvidenceQuery {
    <#
    .SYNOPSIS
    Get Software Evidence query results.

    .DESCRIPTION
    Get Software Evidence query results from DeviceTvmSoftwareEvidenceBeta table.

    .PARAMETER appName
    (optional) name of the app you want to get data for.

    .PARAMETER appVersion
    (optional) version of the app you want to get data for.

    .PARAMETER deviceId
    (optional) ID of the device you want to get data for.

    .PARAMETER header
    Header created using New-M365DefenderAuthHeader.

    .PARAMETER apiUrl
    API url.

    By default "api-eu.securitycenter.microsoft.com" for best performance in EU region.

    .EXAMPLE
    $header = New-M365DefenderAuthHeader

    Invoke-M365DefenderSoftwareEvidenceQuery -header $header

    Get all (100 000 at most) results of Software Evidence table query.

    .EXAMPLE
    $header = New-M365DefenderAuthHeader

    Invoke-M365DefenderSoftwareEvidenceQuery -header $header -appName JRE

    Get all (100 000 at most) results of Software Evidence table query related to JRE software.

    .NOTES
    Requires AdvancedQuery.Read.All permission.

    https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/api/run-advanced-query-api?view=o365-worldwide
    #>

    [CmdletBinding()]
    param (
        [string] $appName,

        [string] $appVersion,

        [string] $deviceId,

        $header,

        [ValidateSet("api.securitycenter.microsoft.com", "api-eu.securitycenter.microsoft.com", "api-us.securitycenter.microsoft.com", "api-uk.securitycenter.microsoft.com", "api-au.securitycenter.microsoft.com")]
        [string] $apiUrl = "api-eu.securitycenter.microsoft.com"
    )

    if (!$header) {
        $header = New-M365DefenderAuthHeader -ErrorAction Stop
    }

    #region create query
    $query = "DeviceTvmSoftwareEvidenceBeta`n| sort by SoftwareName, SoftwareVersion"

    if ($appName) {
        $query += "`n| where SoftwareName has '$appName'"
    }
    if ($appVersion) {
        $query += "`n| where SoftwareVersion has '$appVersion'"
    }
    if ($deviceId) {
        $query += "`n| where DeviceId has '$deviceId'"
    }
    #endregion create query

    Write-Verbose "Running query:`n$query"

    Invoke-M365DefenderAdvancedQuery -header $header -query $query
}

function New-M365DefenderAuthHeader {
    <#
    .SYNOPSIS
    Function creates authentication header for accessing Microsoft 365 Defender API.

    .DESCRIPTION
    Function creates authentication header for accessing Microsoft 365 Defender API.

    Support authentication using Managed identity, current user, app secret.

    .PARAMETER credential
    Application ID (as username), application secret (as password).

    .PARAMETER identity
    Use managed identity to authenticate.
    https://learn.microsoft.com/en-us/answers/questions/1394819/authenticate-to-microsoft-defender-for-endpoint-ap

    .PARAMETER tenantId
    ID of your tenant.

    .EXAMPLE
    $header = New-M365DefenderAuthHeader

    # Send the webrequest and get the results.
    $url = "https://api.securitycenter.microsoft.com/api/alerts?`$filter=alertCreationTime ge $dateTime"
    $response = Invoke-WebRequest -Method Get -Uri $url -Headers $header -ErrorAction Stop

    # Extract the alerts from the results.
    $alerts = ($response | ConvertFrom-Json).value | ConvertTo-Json

    Interactive authentication using provided credentials.

    .EXAMPLE
    Connect-AzAccount

    $header = New-M365DefenderAuthHeader

    Silent authentication using currently authenticated user.

    .EXAMPLE
    $header = New-M365DefenderAuthHeader -credential $credential

    Silent authentication using provided credentials.

    .EXAMPLE
    Connect-AzAccount -identity

    $header = New-M365DefenderAuthHeader -identity

    Silent authentication using managed identity.

    .NOTES
    https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/api/exposed-apis-create-app-webapp?view=o365-worldwide#use-powershell
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, ParameterSetName = "Credential")]
        [System.Management.Automation.PSCredential] $credential,

        [Parameter(Mandatory = $true, ParameterSetName = "ManagedIdentity")]
        [switch] $identity,

        [Parameter(Mandatory = $false, ParameterSetName = "Credential")]
        [ValidateNotNullOrEmpty()]
        $tenantId = $_tenantDomain
    )

    if ($credential -and !$tenantId) {
        throw "TenantId parameter cannot be empty!"
    }

    if ($identity) {
        # connecting using authenticated managed identity

        if (!(Get-Command "Get-AzAccessToken" -ea SilentlyContinue)) {
            throw "'Get-AzAccessToken' command is missing (module Az.Accounts). Unable to continue"
        }

        $sourceAppIdUri = 'https://api.securitycenter.microsoft.com/.default'
        $secureToken = (Get-AzAccessToken -ResourceUri $sourceAppIdUri -AsSecureString).Token
        $token = [PSCredential]::New('dummy', $secureToken).GetNetworkCredential().Password

        if (!$token) {
            throw "Unable to obtain an auth. token. Are you authenticated using managed identity via 'Connect-AzAccount -Identity'?"
        }
    } else {
        # connecting using credentials

        if ($credential) {
            # connecting using provided credentials
            $oAuthUri = "https://login.microsoftonline.com/$tenantId/oauth2/token"
            $authBody = [Ordered]@{
                scope         = 'https://api.securitycenter.microsoft.com/.default'
                client_id     = $credential.username
                client_secret = $credential.GetNetworkCredential().password
                grant_type    = 'client_credentials'
            }

            $authResponse = Invoke-RestMethod -Method Post -Uri $oAuthUri -Body $authBody -ErrorAction Stop
            $token = $authResponse.access_token
        } else {
            # connecting using existing Azure session
            $secureToken = (Get-AzAccessToken -ResourceUri 'https://api.securitycenter.microsoft.com' -AsSecureString -ErrorAction Stop).Token
            $token = [PSCredential]::New('dummy', $secureToken).GetNetworkCredential().Password
        }

        if (!$token) {
            throw "Unable to obtain an auth. token"
        }
    }

    $headers = @{
        'Content-Type' = 'application/json'
        Accept         = 'application/json'
        Authorization  = "Bearer $token"
    }

    return $headers
}

Export-ModuleMember -function Get-M365DefenderMachine, Get-M365DefenderMachineUser, Get-M365DefenderMachineVulnerability, Get-M365DefenderRecommendation, Get-M365DefenderSoftware, Get-M365DefenderVulnerability, Get-M365DefenderVulnerabilityReport, Invoke-M365DefenderAdvancedQuery, Invoke-M365DefenderSoftwareEvidenceQuery, New-M365DefenderAuthHeader

