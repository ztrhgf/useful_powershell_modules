
function ConvertFrom-EncryptedString {
    <#
    .SYNOPSIS
        Decrypts an AES-encrypted string back to plaintext.

    .DESCRIPTION
        This function decrypts a Base64-encoded string that was previously encrypted using the ConvertTo-EncryptedString function. It uses AES decryption with the key derived from the provided string key using SHA256 hashing.

    .PARAMETER EncryptedText
        The Base64-encoded encrypted string to decrypt, which contains both the IV and the encrypted data.

    .PARAMETER Key
        The encryption key as a string. Must be the same key that was used for encryption.
        This will be hashed using SHA256 to create a 256-bit key.

    .EXAMPLE
        $decryptedText = ConvertFrom-EncryptedString -EncryptedText "d8Q3I/AtB6oQ0LyFHAUXGwEs82FUweK+XZG22P8CQq8=" -Key "MyEncryptionKey"

        Returns the original plaintext string.

    .OUTPUTS
        [System.String]
        Returns the decrypted plaintext string.
        Returns $null if the input string is null, empty, or if decryption fails.

    .NOTES
        This function is designed to work with strings encrypted by the ConvertTo-EncryptedString function.
        The IV is expected to be in the first 16 bytes of the decoded Base64 string.
        If the wrong key is provided or if the encrypted string is corrupted, decryption will fail.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$EncryptedText,

        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if ([string]::IsNullOrEmpty($EncryptedText)) { return $null }

    try {
        # Create a byte array from the encryption key using SHA256
        $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($Key)
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $keyBytes = $sha256.ComputeHash($keyBytes)

        # Convert the encrypted text from Base64
        $encryptedBytes = [Convert]::FromBase64String($EncryptedText)

        # Create AES object
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Key = $keyBytes

        # Extract the IV (first 16 bytes) and the encrypted data
        $iv = $encryptedBytes[0..15]
        $aes.IV = $iv
        $encryptedData = $encryptedBytes[16..($encryptedBytes.Length - 1)]

        # Create decryptor and decrypt the data
        $decryptor = $aes.CreateDecryptor()
        $decryptedBytes = $decryptor.TransformFinalBlock($encryptedData, 0, $encryptedData.Length)

        # Convert decrypted bytes to string
        return [System.Text.Encoding]::UTF8.GetString($decryptedBytes)
    } catch {
        throw "Decryption failed: $_"
    } finally {
        if ($aes) { $aes.Dispose() }
        if ($sha256) { $sha256.Dispose() }
    }
}