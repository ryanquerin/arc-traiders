[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Path)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'File not found.' }
$file = Get-Item -LiteralPath $Path
$sig = Get-AuthenticodeSignature -FilePath $Path
[pscustomobject]@{
    file = $file.FullName
    size_bytes = $file.Length
    sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    signature_status = $sig.Status.ToString()
    signer = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { $null }
    version = $file.VersionInfo.FileVersion
    product = $file.VersionInfo.ProductName
} | ConvertTo-Json -Depth 4