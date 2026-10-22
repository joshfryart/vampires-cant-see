# Runs the headless GDScript tests. Usage: tools\run-tests.ps1 [-Filter rng]
param([string]$Filter = "")
$port = Split-Path -Parent $PSScriptRoot
$exe = Join-Path (Split-Path -Parent $port) "Godot_v4.4.1-stable_win64.exe"
$args = @("--headless", "--path", (Join-Path $port "project"), "-s", "res://tests/run_tests.gd")
if ($Filter) { $args += @("--", "--filter=$Filter") }
& $exe @args
exit $LASTEXITCODE
