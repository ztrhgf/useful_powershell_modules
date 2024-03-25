function ConvertTo-CompressedString {
    <#
    .SYNOPSIS
    Function compress given string.

    .DESCRIPTION
    Function compress given string using GZipStream and the results is returned as a base64 string.

    Please note that the compressed string might not be shorter than the original string if the original string is short, as the compression algorithm adds some overhead.

    .PARAMETER string
    String you want to compress.

    .PARAMETER compressCharThreshold
    (optional) minimum number of characters to actually run the compression.
    If lower, no compression will be made and original text will be returned intact.

    .EXAMPLE
    $output = Get-Process 'PowerShell' | ConvertTo-Json -Compress

    # compress the string
    $compressedString = ConvertTo-CompressedString -string $output

    # decompress the compressed string to the original one
    $decompressedString = ConvertFrom-CompressedString -string $compressedString

    # convert back
    $originalOutput = $decompressedString | ConvertFrom-Json

    .EXAMPLE
    $command = @"
        $output = Get-Process 'PowerShell' | ConvertTo-Json -Compress

        # compress the string (only if necessary a.k.a. remediation output limit of 2048 chars is hit)
        $compressedString = ConvertTo-CompressedString -string $output -compressCharThreshold 2048
    "@

    Invoke-IntuneCommand -command $command -deviceName PC-01

    Get the data from the client and compress them if string is longer than 2048 chars.
    Result will be automatically decompressed and converted back from JSON to object.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $string,

        [int] $compressCharThreshold
    )

    if ($compressCharThreshold) {
        if (($string | Measure-Object -Character).Characters -le $compressCharThreshold) {
            Write-Verbose "Threshold wasn't reached. Returning original string."
            return $string
        }
    }

    try {
        $inputBytes = [System.Text.Encoding]::UTF8.GetBytes($string)
        $outputBytes = New-Object byte[] ($inputBytes.Length)
        $memoryStream = New-Object IO.MemoryStream
        $gzipStream = New-Object IO.Compression.GZipStream($memoryStream, [IO.Compression.CompressionMode]::Compress)
        $gzipStream.Write($inputBytes, 0, $inputBytes.Length)
        $gzipStream.Close()

        return [Convert]::ToBase64String($memoryStream.ToArray())
    } catch {
        Write-Error "Unable to compress the given string"
    }
}