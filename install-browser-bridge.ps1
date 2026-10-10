[CmdletBinding()]
param(
    [ValidatePattern('^[a-p]{32}$')][string]$ChromeExtensionId = '',
    [ValidatePattern('^[a-p]{32}$')][string]$EdgeExtensionId = '',
    [switch]$Firefox
)

$ErrorActionPreference = 'Stop'
if (-not $ChromeExtensionId -and -not $EdgeExtensionId -and -not $Firefox) {
    throw 'Specify -ChromeExtensionId, -EdgeExtensionId, and/or -Firefox after installing the corresponding extension.'
}

$hostName = 'com.shortcutkeys.bridge'
$binary = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'shortcut-keys-browser.exe')).Path
$directory = Join-Path $env:LOCALAPPDATA 'ShortcutKeys\native-hosts'
New-Item -ItemType Directory -Path $directory -Force | Out-Null

function Register-Host([string]$browser, [string]$registryPath, [hashtable]$manifest) {
    $manifestPath = Join-Path $directory "$browser.json"
    $json = $manifest | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText($manifestPath, $json, [System.Text.UTF8Encoding]::new($false))
    New-Item -Path $registryPath -Force | Out-Null
    Set-Item -Path $registryPath -Value $manifestPath
    Write-Host "$browser native-messaging host registered for the current user."
}

if ($ChromeExtensionId) {
    Register-Host 'chrome' "HKCU:\Software\Google\Chrome\NativeMessagingHosts\$hostName" @{
        name = $hostName; description = 'ShortcutKeys browser bridge'; path = $binary
        type = 'stdio'; allowed_origins = @("chrome-extension://$ChromeExtensionId/")
    }
}
if ($EdgeExtensionId) {
    Register-Host 'edge' "HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\$hostName" @{
        name = $hostName; description = 'ShortcutKeys browser bridge'; path = $binary
        type = 'stdio'; allowed_origins = @("chrome-extension://$EdgeExtensionId/")
    }
}
if ($Firefox) {
    Register-Host 'firefox' "HKCU:\Software\Mozilla\NativeMessagingHosts\$hostName" @{
        name = $hostName; description = 'ShortcutKeys browser bridge'; path = $binary
        type = 'stdio'; allowed_extensions = @('shortcutkeys-novnc@example.org')
    }
}

Write-Host 'Restart the selected browser after registration. Keep ShortcutKeys running before opening its noVNC extension.'
