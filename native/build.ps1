param([switch]$Run, [switch]$Test)
$ErrorActionPreference = 'Stop'
$nativeRoot = $PSScriptRoot
$vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
 if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Install Visual Studio C++ build tools, or run from an x64 Native Tools prompt.' }
 $vsRoot = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
 if (-not $vsRoot) { throw 'The Visual Studio Desktop development with C++ workload is required.' }
 $devCmd = Join-Path $vsRoot 'Common7/Tools/VsDevCmd.bat'
 $vars = & cmd.exe /d /c "call `"$devCmd`" -arch=x64 -host_arch=x64 >nul && set"
 if ($LASTEXITCODE -ne 0) { throw 'Visual Studio environment setup failed.' }
 foreach ($line in $vars) { if ($line -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($matches[1],$matches[2],'Process') } }
}
if (-not (Get-Command nvcc.exe -ErrorAction SilentlyContinue)) { throw 'Install NVIDIA CUDA Toolkit and put nvcc on PATH.' }
& cmake -S $nativeRoot -B "$nativeRoot/build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_CUDA_ARCHITECTURES=native
if ($LASTEXITCODE -ne 0) { throw 'CMake configuration failed.' }
& cmake --build "$nativeRoot/build"
if ($LASTEXITCODE -ne 0) { throw 'Native build failed.' }
if ($Test) { & ctest --test-dir "$nativeRoot/build" --output-on-failure; if ($LASTEXITCODE -ne 0) { throw 'Native GPU tests failed.' } }
if ($Run) { & "$nativeRoot/build/watercuda.exe" }

