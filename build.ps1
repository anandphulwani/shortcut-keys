[CmdletBinding()]
param(
    [ValidateSet('x64', 'x86', 'all')]
    [string]$Architecture = 'all',
    [string]$AutoHotkeyRoot = '',
    [string]$CompilerPath = '',
    [string]$OutputRoot = '',
    [string]$ArtifactRoot = '',
    [switch]$SkipTests,
    [switch]$SkipSmoke
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$OutputRoot = if ($OutputRoot) { [System.IO.Path]::GetFullPath($OutputRoot) } else { Join-Path $projectRoot 'dist' }
$ArtifactRoot = if ($ArtifactRoot) { [System.IO.Path]::GetFullPath($ArtifactRoot) } else { Join-Path $projectRoot 'artifacts' }
foreach ($root in @($OutputRoot, $ArtifactRoot)) {
    if (-not $root.StartsWith($projectRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Build output root must be inside the project: '$root'."
    }
}
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
    $env:SHORTCUT_KEYS_BRIDGE_DIR = $testOutputDirectory
    if (-not $SkipTests) {
        $node = Get-Command node -ErrorAction SilentlyContinue
        if (-not $node) { throw 'Node.js is required for browser-extension tests.' }
        & $node.Source --check (Join-Path $projectRoot 'extension\common\background.js')
        & $node.Source --check (Join-Path $projectRoot 'extension\common\login-content.js')
        & $node.Source --check (Join-Path $projectRoot 'extension\common\options.js')
        & $node.Source (Join-Path $projectRoot 'Tests\browser-extension.test.js')
        if ($LASTEXITCODE -ne 0) { throw "$target browser-extension tests failed." }
        & $node.Source (Join-Path $projectRoot 'Tests\browser-login.test.js')
        if ($LASTEXITCODE -ne 0) { throw "$target browser-login tests failed." }
        & $node.Source (Join-Path $projectRoot 'Tests\browser-options.test.js')
        if ($LASTEXITCODE -ne 0) { throw "$target browser-options tests failed." }
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
        if (Select-String -LiteralPath $testStdout -Pattern '^FAIL |^RESULT .*failed=[1-9]' -Quiet -ErrorAction SilentlyContinue) {
            throw "$target tests reported failures."
        }
        if ($test.ExitCode -ne 0) {
            throw "$target tests failed with exit code $($test.ExitCode)."
        }
    }

    $outputDirectory = Join-Path $OutputRoot "win-$target"
    if (Test-Path -LiteralPath $outputDirectory) {
        $resolvedOutput = (Resolve-Path -LiteralPath $outputDirectory).Path
        $resolvedRoot = (Resolve-Path -LiteralPath $OutputRoot).Path
        if (-not $resolvedOutput.StartsWith($resolvedRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean unexpected output path '$resolvedOutput'."
        }
        foreach ($existingBinary in (Get-ChildItem -LiteralPath $resolvedOutput -Filter '*.exe' -File -ErrorAction SilentlyContinue)) {
            try {
                $exclusiveHandle = [System.IO.File]::Open($existingBinary.FullName, 'Open', 'ReadWrite', 'None')
                $exclusiveHandle.Dispose()
            } catch {
                throw "The existing distribution is in use at '$($existingBinary.FullName)'. Close it or pass -OutputRoot to build separately."
            }
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

    foreach ($file in @('credentials.json.enc', 'credentials.example.json', 'README.md', 'MIGRATION.md', 'THIRD_PARTY_NOTICES.md', 'install-browser-bridge.ps1')) {
        Copy-Item -LiteralPath (Join-Path $projectRoot $file) -Destination $outputDirectory
    }
    Copy-Item -LiteralPath (Join-Path $projectRoot 'Resources') -Destination $outputDirectory -Recurse
    foreach ($browser in @('chromium', 'firefox')) {
        $extensionOutput = Join-Path $outputDirectory "extension\$browser"
        New-Item -ItemType Directory -Path $extensionOutput -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $projectRoot "extension\$browser\manifest.json") -Destination $extensionOutput
        Copy-Item -Path (Join-Path $projectRoot 'extension\common\*') -Destination $extensionOutput
    }

    if (-not $SkipSmoke) {
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
    }

    $archive = Join-Path $ArtifactRoot "shortcut-keys-$target.zip"
    New-Item -ItemType Directory -Force -Path (Split-Path $archive) | Out-Null
    if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
    Compress-Archive -Path (Join-Path $outputDirectory '*') -DestinationPath $archive
    Write-Host "Built $archive"
}
