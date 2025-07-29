function ConvertTo-EncryptedString {
    <#
    .SYNOPSIS
        Encrypts a string using AES encryption with a provided key.

    .DESCRIPTION
        This function takes a plaintext string and encrypts it using AES-256 encryption.
        The encryption key is derived from the provided string key using SHA256 hashing.
        The function returns a Base64-encoded string that includes the IV and encrypted data.
        Portable across any system.

    .PARAMETER textToEncrypt
        The plaintext string to be encrypted.

    .PARAMETER key
        The encryption key as a string. This will be hashed using SHA256 to create a 256-bit key.

    .EXAMPLE
        $encryptedPassword = ConvertTo-EncryptedString -textToEncrypt "SecretPassword123" -key "MyEncryptionKey"

        Encrypts the password with the provided key and returns an encrypted Base64 string.

    .OUTPUTS
        [System.String]
        Returns a Base64-encoded string containing the IV and encrypted data.
        Returns $null if the input string is null or empty.

    .NOTES
        The function uses AES encryption with a random IV for each encryption operation.
        The IV is prepended to the encrypted data in the output string.
        To decrypt the string, use the corresponding ConvertFrom-EncryptedString function with the same key.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $textToEncrypt,

        [Parameter(Mandatory = $true)]
        [string] $key
    )

    if ([string]::IsNullOrEmpty($textToEncrypt)) { return $null }

    try {
        # Create a byte array from the encryption key
        # We'll derive a 256-bit key using SHA256
        $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($key)
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $keyBytes = $sha256.ComputeHash($keyBytes)

        # Create AES object
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Key = $keyBytes
        $aes.GenerateIV() # Generate a random IV for each encryption

        # Convert the text to encrypt to bytes
        $dataBytes = [System.Text.Encoding]::UTF8.GetBytes($textToEncrypt)

        # Create encryptor and encrypt the data
        $encryptor = $aes.CreateEncryptor()
        $encryptedData = $encryptor.TransformFinalBlock($dataBytes, 0, $dataBytes.Length)

        # Combine the IV and encrypted data for storage
        $resultBytes = $aes.IV + $encryptedData

        # Return as Base64 string
        return [Convert]::ToBase64String($resultBytes)
    } catch {
        throw "Encryption failed: $_"
    } finally {
        if ($aes) { $aes.Dispose() }
        if ($sha256) { $sha256.Dispose() }
    }
}