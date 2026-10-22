[CmdletBinding()]
param([string]$Keytool = 'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe')
$ErrorActionPreference = 'Stop'
$androidDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\android'))
$keyPath = Join-Path $androidDir 'upload-keystore.jks'
$propertiesPath = Join-Path $androidDir 'key.properties'
if ((Test-Path -LiteralPath $keyPath) -or (Test-Path -LiteralPath $propertiesPath)) {
    throw 'Signing files already exist. Preserve them: replacing a signing key can prevent app updates.'
}
if (-not (Test-Path -LiteralPath $Keytool)) { throw 'Pass -Keytool with the path to your local JDK keytool.exe.' }
$randomBytes = New-Object byte[] 32
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
try { $rng.GetBytes($randomBytes) } finally { $rng.Dispose() }
$signingPassword = [Convert]::ToBase64String($randomBytes)
# keytool reads the password from this process's environment; it never appears
# in command arguments, terminal output or the repository.
$oldPassword = [Environment]::GetEnvironmentVariable('AG_RELEASE_KEY_PASSWORD', 'Process')
try {
    [Environment]::SetEnvironmentVariable('AG_RELEASE_KEY_PASSWORD', $signingPassword, 'Process')
    & $Keytool -genkeypair -v -keystore $keyPath -storetype JKS -alias upload -keyalg RSA -keysize 3072 -validity 10000 -dname 'CN=Antigravity Mobile' -storepass:env AG_RELEASE_KEY_PASSWORD -keypass:env AG_RELEASE_KEY_PASSWORD
    if ($LASTEXITCODE -ne 0) { throw 'keytool failed; no signing properties were created.' }
    $properties = "storeFile=upload-keystore.jks`nstorePassword=$signingPassword`nkeyAlias=upload`nkeyPassword=$signingPassword`n"
    [IO.File]::WriteAllText($propertiesPath, $properties, [Text.UTF8Encoding]::new($false))
    # Restrict these local secrets to the current Windows user.
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    foreach ($secretFile in @($keyPath, $propertiesPath)) {
        & icacls.exe $secretFile /inheritance:r /grant:r "${currentUser}:(F)" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not restrict access to the local signing files.' }
    }
    Write-Output 'Release signing created. Back up android/upload-keystore.jks and android/key.properties together in a secure location. Both are excluded from Git.'
} finally {
    [Environment]::SetEnvironmentVariable('AG_RELEASE_KEY_PASSWORD', $oldPassword, 'Process')
    [Array]::Clear($randomBytes, 0, $randomBytes.Length)
    $signingPassword = $null
    $properties = $null
}
