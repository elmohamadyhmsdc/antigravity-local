param(
    [string]$FlutterRoot = 'C:\flutter',
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$mobileDirectory = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$flutterTool = Join-Path $FlutterRoot 'bin\flutter.bat'
$dartTool = Join-Path $FlutterRoot 'bin\dart.bat'

if (-not (Test-Path -LiteralPath $flutterTool -PathType Leaf)) {
    throw "Flutter was not found at $flutterTool. Set -FlutterRoot to the existing SDK."
}
if (-not (Test-Path -LiteralPath $dartTool -PathType Leaf)) {
    throw "Dart was not found at $dartTool."
}

function Invoke-CheckedTool {
    param([string]$Executable, [string[]]$ToolArguments)
    & $Executable @ToolArguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Executable exited with code $LASTEXITCODE."
    }
}

$dartFiles = @(
    'lib/core/theme.dart'
    'lib/features/shared/screen_layout.dart'
    'lib/features/shared/empty_state.dart'
    'lib/features/shared/person_picker.dart'
    'lib/features/home/home_screen.dart'
    'lib/features/studio/studio_screen.dart'
    'lib/features/storage/storage_screen.dart'
    'lib/features/shell/app_shell.dart'
    'lib/features/library/library_screen.dart'
    'lib/features/library/media_grid.dart'
    'lib/features/people/people_screen.dart'
    'lib/features/people/person_detail_screen.dart'
    'lib/features/people/face_grid.dart'
    'lib/features/reface/reface_screen.dart'
    'lib/features/scan/sources_screen.dart'
    'lib/features/restyle/restyle_screen.dart'
    'lib/features/lora/lora_screens.dart'
    'lib/features/settings/settings_screen.dart'
    'lib/features/settings/connection_screen.dart'
    'lib/features/settings/background_screen.dart'
    'lib/features/onboarding/welcome_screen.dart'
    'lib/features/onboarding/manual_pair_screen.dart'
    'lib/features/onboarding/qr_scan_screen.dart'
    'lib/features/onboarding/permissions_screen.dart'
    'lib/features/backup/backup_screen.dart'
    'lib/features/review/review_screen.dart'
    'lib/features/merge/merge_screen.dart'
    'lib/features/insights/insights_screen.dart'
    'lib/features/analyze/analyze_screen.dart'
    'lib/features/jobs/jobs_screen.dart'
    'lib/features/results/results_screen.dart'
    'lib/features/media/media_screen.dart'
    'lib/features/media/video_media_view.dart'
    'lib/features/privacy/app_lock.dart'
    'test/features/redesign_ux_test.dart'
    'test/features/redesign_screens_test.dart'
)

Push-Location -LiteralPath $mobileDirectory
try {
    Write-Host 'Generating localized strings'
    Invoke-CheckedTool -Executable $flutterTool -ToolArguments @('--no-version-check', 'gen-l10n')
    Write-Host 'Formatting the UI files changed by this redesign'
    Invoke-CheckedTool -Executable $dartTool -ToolArguments (@('format') + $dartFiles)
    Write-Host 'Analyzing the Flutter app'
    Invoke-CheckedTool -Executable $flutterTool -ToolArguments @('--no-version-check', 'analyze', '--no-pub')
    if (-not $SkipTests) {
        Write-Host 'Checking feature screens and interactions'
        Invoke-CheckedTool -Executable $flutterTool -ToolArguments @('--no-version-check', 'test', '--no-pub', 'test/features')
    }
}
finally {
    Pop-Location
}
