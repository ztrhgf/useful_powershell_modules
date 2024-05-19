function ConvertFrom-CompressedString {
    <#
    .SYNOPSIS
    Function for decompressing the given string.

    .DESCRIPTION
    Function for decompressing the given string.
    It expects the string to be compressed via ConvertTo-CompressedString.

    .PARAMETER compressedString
    String compressed via ConvertTo-CompressedString.

    .EXAMPLE
    $output = Get-Process 'PowerShell' | ConvertTo-Json -Compress

    # compress the string
    $compressedString = ConvertTo-CompressedString -string $output

    # decompress the compressed string to the original one
    $decompressedString = ConvertFrom-CompressedString -string $compressedString
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string] $compressedString
    )

    process {
        try {
            $inputBytes = [Convert]::FromBase64String($compressedString)
            $memoryStream = New-Object IO.MemoryStream($inputBytes, 0, $inputBytes.Length)
            $gzipStream = New-Object IO.Compression.GZipStream($memoryStream, [IO.Compression.CompressionMode]::Decompress)
            $reader = New-Object IO.StreamReader($gzipStream)
            return $reader.ReadToEnd()
        } catch {
            Write-Error "Unable to decompress the given string. Was it really created using ConvertTo-CompressedString?"
        }
    }
}