function Create-BasicAuthHeader {
    <#
    .SYNOPSIS
    Function returns basic authentication header that can be used for web requests.

    .DESCRIPTION
    Function returns basic authentication header that can be used for web requests.

    .PARAMETER credential
    Credentials object that will be used to create auth. header.

    .EXAMPLE
    $header = Create-BasicAuthHeader -credential (Get-Credential)
    $response = Invoke-RestMethod -Uri "https://example.com/api" -Headers $header
    #>

    param (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential] $credential
    )

    @{
        "Authorization" = "Basic " + [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($Credential.UserName + ":" + [System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($Credential.Password)) )))
    }
}