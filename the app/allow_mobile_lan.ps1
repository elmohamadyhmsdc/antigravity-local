#requires -RunAsAdministrator
<#! Run from the app folder, or pass -PythonPath with the existing venv executable.
Only Antigravity's two local ports are allowed. No packages or network profiles are changed.
!#>
param(
    [string]$PythonPath = (Join-Path $PSScriptRoot 'venv\Scripts\python.exe'),
    [ValidateRange(1,65535)][int]$ApiPort = 8443,
    [ValidateRange(1,65535)][int]$DiscoveryPort = 8445
)
$ErrorActionPreference = 'Stop'
$resolvedPython = (Resolve-Path -LiteralPath $PythonPath).Path
$serverPython = (& $resolvedPython -c 'import sys; print(sys._base_executable)').Trim()
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $serverPython -PathType Leaf)) {
    throw 'The existing Python interpreter could not be resolved.'
}
foreach ($spec in @(@{Protocol='TCP';Port=$ApiPort},@{Protocol='UDP';Port=$DiscoveryPort})) {
    $ruleName = "Antigravity-Mobile-$($spec.Protocol)-$($spec.Port)"
    $rule = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
    if ($null -eq $rule) {
        New-NetFirewallRule -Name $ruleName -DisplayName $ruleName -Direction Inbound -Action Allow `
            -Enabled True -Profile Private,Public -Program $serverPython -Protocol $spec.Protocol `
            -LocalPort $spec.Port -RemoteAddress LocalSubnet | Out-Null
    } else {
        $rule | Set-NetFirewallRule -Enabled True -Profile Private,Public -Direction Inbound -Action Allow
        $rule | Get-NetFirewallApplicationFilter | Set-NetFirewallApplicationFilter -Program $serverPython
        $rule | Get-NetFirewallPortFilter | Set-NetFirewallPortFilter -Protocol $spec.Protocol -LocalPort $spec.Port
        $rule | Get-NetFirewallAddressFilter | Set-NetFirewallAddressFilter -RemoteAddress LocalSubnet
    }
}
Write-Output 'Local phone connections enabled for the existing Python server. The pairing/admin port stays local.'
