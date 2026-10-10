[CmdletBinding()]
param(
    [ValidateSet('x64', 'x86', 'all')]
    [string]$Architecture = 'all',
    [string]$AutoHotkeyRoot = '',
    [string]$CompilerPath = '',
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$requiredVersion = [Version]'2.0.30'

if (-not $AutoHotkeyRoot) {
    $portable = Join-Path $projectRoot '.tools\AutoHotkey_2.0.30'
    if (Test-Path -LiteralPath $portable) {
        $AutoHotkeyRoot = $portable
    } else {
        $AutoHotkeyRoot = 'C:\Program Files\AutoHotkey\v2'
    }
}
if (-not $CompilerPath) {
    $CompilerPath = 'C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe'
}
if (-not (Test-Path -LiteralPath $CompilerPath)) {
    throw "Ahk2Exe was not found at '$CompilerPath'. Pass -CompilerPath explicitly."
}

$targets = if ($Architecture -eq 'all') { @('x64', 'x86') } else { @($Architecture) }
$sources = @(
    @{ Source = 'shortcut-keys.ahk'; Output = 'shortcut-keys.exe'; Icon = 'Resources\icons8-bot-48.ico' },
    @{ Source = 'shortcut-keys-send.ahk'; Output = 'shortcut-keys-send.exe'; Icon = 'Resources\autocomplete-48.ico' },
    @{ Source = 'shortcut-keys-autofill.ahk'; Output = 'shortcut-keys-autofill.exe'; Icon = 'Resources\icons8-bot-48.ico' },
    @{ Source = 'shortcut-keys-browser.ahk'; Output = 'shortcut-keys-browser.exe'; Icon = 'Resources\icons8-bot-48.ico' }
)

foreach ($target in $targets) {
    $runtimeName = if ($target -eq 'x64') { 'AutoHotkey64.exe' } else { 'AutoHotkey32.exe' }
    $runtime = Join-Path $AutoHotkeyRoot $runtimeName
    if (-not (Test-Path -LiteralPath $runtime)) {
        throw "The $target runtime was not found at '$runtime'."
    }
    $runtimeVersion = [Version](Get-Item -LiteralPath $runtime).VersionInfo.ProductVersion
    if ($runtimeVersion -ne $requiredVersion) {
        throw "Expected AutoHotkey $requiredVersion, found $runtimeVersion at '$runtime'."
    }

    $testOutputDirectory = Join-Path $projectRoot 'test-results'
    New-Item -ItemType Directory -Force -Path $testOutputDirectory | Out-Null
    if (-not $SkipTests) {
        $testStdout = Join-Path $testOutputDirectory "build-$target.stdout.log"
        $testStderr = Join-Path $testOutputDirectory "build-$target.stderr.log"
        Remove-Item -LiteralPath $testStdout, $testStderr -Force -ErrorAction SilentlyContinue
        $testArguments = '/ErrorStdOut "{0}"' -f (Join-Path $projectRoot 'Tests\run-tests.ahk')
        $test = Start-Process -FilePath $runtime -ArgumentList $testArguments -WorkingDirectory $projectRoot -RedirectStandardOutput $testStdout -RedirectStandardError $testStderr -Wait -PassThru
        if (Test-Path -LiteralPath $testStdout) { Get-Content -LiteralPath $testStdout }
        if (Test-Path -LiteralPath $testStderr) { Get-Content -LiteralPath $testStderr }
        if (Select-String -LiteralPath $testStdout -Pattern '==> Warning:' -Quiet -ErrorAction SilentlyContinue) {
            throw "$target tests emitted AutoHotkey warnings."
        }
        if ($test.ExitCode -ne 0) {
            throw "$target tests failed with exit code $($test.ExitCode)."
        }
    }

    $outputDirectory = Join-Path $projectRoot "dist\win-$target"
    if (Test-Path -LiteralPath $outputDirectory) {
        $resolvedOutput = (Resolve-Path -LiteralPath $outputDirectory).Path
        $resolvedDist = (Resolve-Path -LiteralPath (Join-Path $projectRoot 'dist')).Path
        if (-not $resolvedOutput.StartsWith($resolvedDist + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean unexpected output path '$resolvedOutput'."
        }
        Remove-Item -LiteralPath $outputDirectory -Recurse -Force
    }
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null

    foreach ($item in $sources) {
        $source = Join-Path $projectRoot $item.Source
        $output = Join-Path $outputDirectory $item.Output
        $icon = Join-Path $projectRoot $item.Icon
        $arguments = '/silent verbose /in "{0}" /out "{1}" /base "{2}" /icon "{3}"' -f $source, $output, $runtime, $icon
        $compile = Start-Process -FilePath $CompilerPath -ArgumentList $arguments -WorkingDirectory $projectRoot -Wait -PassThru
        if ($compile.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $output)) {
            throw "Compilation failed for $($item.Source) ($target)."
        }
    }

    foreach ($file in @('credentials.json.enc', 'credentials.example.json', 'README.md', 'MIGRATION.md', 'THIRD_PARTY_NOTICES.md')) {
        Copy-Item -LiteralPath (Join-Path $projectRoot $file) -Destination $outputDirectory
    }
    Copy-Item -LiteralPath (Join-Path $projectRoot 'Resources') -Destination $outputDirectory -Recurse

    try {
        $env:SHORTCUT_KEYS_SELF_TEST = '1'
        $smoke = Start-Process -FilePath (Join-Path $outputDirectory 'shortcut-keys.exe') -ArgumentList 'self-test' -WorkingDirectory $outputDirectory -PassThru
        if (-not $smoke.WaitForExit(10000)) {
            Stop-Process -Id $smoke.Id -Force -ErrorAction SilentlyContinue
            throw "$target compiled smoke test timed out."
        }
    } finally {
        Remove-Item Env:SHORTCUT_KEYS_SELF_TEST -ErrorAction SilentlyContinue
    }
    if ($smoke.ExitCode -ne 0) {
        throw "$target compiled smoke test failed with exit code $($smoke.ExitCode)."
    }

    $workerSmokeStdout = Join-Path $testOutputDirectory "compiled-$target.stdout.log"
    $workerSmokeStderr = Join-Path $testOutputDirectory "compiled-$target.stderr.log"
    Remove-Item -LiteralPath $workerSmokeStdout, $workerSmokeStderr -Force -ErrorAction SilentlyContinue
    $workerSmokeArguments = '/ErrorStdOut "{0}" "{1}"' -f (Join-Path $projectRoot 'Tests\compiled-workers-smoke.ahk'), $outputDirectory
    $workerSmoke = Start-Process -FilePath $runtime -ArgumentList $workerSmokeArguments -WorkingDirectory $projectRoot -RedirectStandardOutput $workerSmokeStdout -RedirectStandardError $workerSmokeStderr -Wait -PassThru
    if (Test-Path -LiteralPath $workerSmokeStdout) { Get-Content -LiteralPath $workerSmokeStdout }
    if (Test-Path -LiteralPath $workerSmokeStderr) { Get-Content -LiteralPath $workerSmokeStderr }
    if (Select-String -LiteralPath $workerSmokeStdout -Pattern '==> Warning:' -Quiet -ErrorAction SilentlyContinue) {
        throw "$target compiled worker smoke test emitted AutoHotkey warnings."
    }
    if ($workerSmoke.ExitCode -ne 0) {
        throw "$target compiled worker smoke test failed with exit code $($workerSmoke.ExitCode)."
    }

    $archive = Join-Path $projectRoot "artifacts\shortcut-keys-$target.zip"
    New-Item -ItemType Directory -Force -Path (Split-Path $archive) | Out-Null
    if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
    Compress-Archive -Path (Join-Path $outputDirectory '*') -DestinationPath $archive
    Write-Host "Built $archive"
}
