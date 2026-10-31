# Run the pinned mobile checks in order; any failure stops verification.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-MobileCheck {
    param(
        [string]$Label,
        [string]$Command,
        [string[]]$Arguments
    )

    Write-Host "==> $Label"
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed (exit code $LASTEXITCODE)."
    }
}

Push-Location (Join-Path $PSScriptRoot '../mobile')
try {
    $flutterCommand = (Get-Command flutter.bat -CommandType Application | Select-Object -First 1).Source
    $dartCommand = Join-Path (Split-Path $flutterCommand) 'dart.bat'
    $expectedVersion = (Get-Content -LiteralPath '.flutter-version' -Raw).Trim()

    Write-Host '==> Flutter SDK version'
    $versionOutput = & $flutterCommand --version --machine
    if ($LASTEXITCODE -ne 0) {
        throw "flutter --version --machine failed (exit code $LASTEXITCODE)."
    }
    $actualVersion = ($versionOutput | ConvertFrom-Json).frameworkVersion
    if ($actualVersion -ne $expectedVersion) {
        throw "Flutter version mismatch: expected $expectedVersion; actual $actualVersion."
    }
    Write-Host "Flutter $actualVersion matches .flutter-version."

    Invoke-MobileCheck 'Dependencies' $flutterCommand @('pub', 'get', '--enforce-lockfile')
    Invoke-MobileCheck 'Format' $dartCommand @('format', '--output=none', '--set-exit-if-changed', 'lib', 'test')
    Invoke-MobileCheck 'Analyze' $flutterCommand @('analyze')
    Invoke-MobileCheck 'Widget tests' $flutterCommand @('test')
    Invoke-MobileCheck 'Android debug APK' $flutterCommand @('build', 'apk', '--debug')
    Write-Host 'Mobile verification passed.'
}
catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
finally {
    Pop-Location
}
