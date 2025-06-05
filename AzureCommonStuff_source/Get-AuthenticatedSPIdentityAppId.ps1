function Get-AuthenticatedSPIdentityAppId {
    <#
    .SYNOPSIS
    Function returns application ID of the app used for authenticating against an Azure.

    .DESCRIPTION
    Function returns application ID of the app used for authenticating against an Azure.

    .EXAMPLE
    Get-AuthenticatedSPIdentityAppId

    Function returns application ID of the app used for authenticating against an Azure.
    #>

    [CmdletBinding()]
    param ()

    function ConvertFrom-JWTToken {
        [cmdletbinding()]
        param([Parameter(Mandatory = $true)][string]$token)

        if ($token -match "^bearer ") {
            # get rid of "bearer " part
            $token = $token -replace "^bearer\s+"
        }

        #Validate as per https://tools.ietf.org/html/rfc7519
        #Access and ID tokens are fine, Refresh tokens will not work
        if (!$token.Contains(".") -or !$token.StartsWith("eyJ")) { Write-Error "Invalid token" -ErrorAction Stop }

        #Payload
        $tokenPayload = $token.Split(".")[1].Replace('-', '+').Replace('_', '/')
        #Fix padding as needed, keep adding "=" until string length modulus 4 reaches 0
        while ($tokenPayload.Length % 4) { Write-Verbose "Invalid length for a Base-64 char array or string, adding ="; $tokenPayload += "=" }
        #Convert to Byte array
        $tokenByteArray = [System.Convert]::FromBase64String($tokenPayload)
        #Convert to string array
        $tokenArray = [System.Text.Encoding]::ASCII.GetString($tokenByteArray)
        Write-Verbose "Decoded array in JSON format:"
        Write-Verbose $tokenArray
        #Convert from JSON to PSObject
        $tokobj = $tokenArray | ConvertFrom-Json
        Write-Verbose "Decoded Payload:"

        return $tokobj
    }

    $token = (Get-AzAccessToken -WarningAction SilentlyContinue).token
    $objectId = (ConvertFrom-JWTToken $token).oid

    Write-Verbose "Get AppId of app with $objectId ObjectId"

    (Get-AzADServicePrincipal -ObjectId $objectId -Select appid).AppId
}