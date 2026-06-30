# One-command runner for native Windows using GCC from MSYS2/MinGW-w64.
# Run from PowerShell inside the perf_benchmark_c_suite folder:
#   powershell -ExecutionPolicy Bypass -File .\run_all_windows.ps1 native_windows

param(
    [string]$EnvironmentName = "native_windows",
    [int]$Repeats = 3,
    [int]$CpuLimit = 120000,
    [int]$MatrixN = 512,
    [int]$IoMB = 256,
    [int]$SortN = 5000000,
    [int[]]$ThreadsToTest = @(1,2,4)
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$OutDir = Join-Path $Root "results\${EnvironmentName}_${Stamp}"
$BinDir = Join-Path $Root "build_${EnvironmentName}_${Stamp}"
New-Item -ItemType Directory -Force -Path $OutDir, $BinDir | Out-Null

function Log($msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg
    Write-Host $line
    Add-Content -Path (Join-Path $OutDir "run.log") -Value $line
}

function Find-Gcc {
    $cmd = Get-Command gcc -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        "C:\msys64\ucrt64\bin\gcc.exe",
        "C:\msys64\mingw64\bin\gcc.exe",
        "C:\msys64\clang64\bin\gcc.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    throw "gcc.exe was not found. Install MSYS2 MinGW-w64 GCC, then run this script again."
}

$Gcc = Find-Gcc
$Common = "src\common.c"
$CFlagsBase = @("-std=c11", "-Wall", "-Wextra")
$LdFlagsBase = @("-lm")
$OpenMpFlag = @()

# Detect OpenMP support.
$OpenMpCheck = Join-Path $BinDir "openmp_check.c"
@"
#include <omp.h>
int main(void){return omp_get_max_threads() < 1;}
"@ | Set-Content -Path $OpenMpCheck -Encoding ascii
try {
    & $Gcc @CFlagsBase "-fopenmp" $OpenMpCheck "-o" (Join-Path $BinDir "openmp_check.exe") *> (Join-Path $OutDir "openmp_check.txt")
    if ($LASTEXITCODE -eq 0) { $OpenMpFlag = @("-fopenmp") }
} catch { }

function Collect-SystemInfo {
    Log "Collecting Windows system information"
    "Environment name: $EnvironmentName" | Set-Content (Join-Path $OutDir "system_summary.txt")
    "Date: $(Get-Date)" | Add-Content (Join-Path $OutDir "system_summary.txt")
    "Compiler: $(& $Gcc --version | Select-Object -First 1)" | Add-Content (Join-Path $OutDir "system_summary.txt")
    "OpenMP flag detected: $(if($OpenMpFlag.Count -gt 0){'-fopenmp'}else{'not available'})" | Add-Content (Join-Path $OutDir "system_summary.txt")

    systeminfo | Out-File -Encoding utf8 (Join-Path $OutDir "systeminfo.txt")
    Get-CimInstance Win32_Processor | Format-List * | Out-File -Encoding utf8 (Join-Path $OutDir "cpu.txt")
    Get-CimInstance Win32_PhysicalMemory | Format-Table BankLabel,Capacity,Speed,Manufacturer -AutoSize | Out-File -Encoding utf8 (Join-Path $OutDir "memory.txt")
    Get-CimInstance Win32_DiskDrive | Format-Table Model,MediaType,Size -AutoSize | Out-File -Encoding utf8 (Join-Path $OutDir "disk.txt")
    & $Gcc --version | Out-File -Encoding utf8 (Join-Path $OutDir "compiler_version.txt")
}

function Build-One($Opt, $Suffix) {
    Log "Building benchmarks with $Opt"
    & $Gcc @CFlagsBase $Opt "src\cpu_prime_baseline.c" $Common "-o" (Join-Path $BinDir "cpu_prime_baseline_${Suffix}.exe") @LdFlagsBase
    & $Gcc @CFlagsBase $Opt @OpenMpFlag "src\cpu_prime_optimized.c" $Common "-o" (Join-Path $BinDir "cpu_prime_optimized_${Suffix}.exe") @LdFlagsBase
    & $Gcc @CFlagsBase $Opt "src\memory_matrix_baseline.c" $Common "-o" (Join-Path $BinDir "memory_matrix_baseline_${Suffix}.exe") @LdFlagsBase
    & $Gcc @CFlagsBase $Opt @OpenMpFlag "src\memory_matrix_optimized.c" $Common "-o" (Join-Path $BinDir "memory_matrix_optimized_${Suffix}.exe") @LdFlagsBase
    & $Gcc @CFlagsBase $Opt "src\file_io_benchmark.c" $Common "-o" (Join-Path $BinDir "file_io_benchmark_${Suffix}.exe") @LdFlagsBase
    & $Gcc @CFlagsBase $Opt "src\mixed_sort_baseline.c" $Common "-o" (Join-Path $BinDir "mixed_sort_baseline_${Suffix}.exe") @LdFlagsBase
    & $Gcc @CFlagsBase $Opt @OpenMpFlag "src\mixed_sort_optimized.c" $Common "-o" (Join-Path $BinDir "mixed_sort_optimized_${Suffix}.exe") @LdFlagsBase
}

$CsvPath = Join-Path $OutDir "results.csv"
"environment,opt_level,threads,repeat,workload,version,seconds,metric_name_or_value,extra" | Set-Content -Path $CsvPath -Encoding ascii

function Run-One($Label, $Exe, $Arg, $Opt, $Threads, $Repeat) {
    Log "Running $Label opt=$Opt threads=$Threads repeat=$Repeat"
    $env:OMP_NUM_THREADS = [string]$Threads
    $Raw = Join-Path $OutDir "raw_${Label}_${Opt}_t${Threads}_r${Repeat}.txt"
    $TimeFile = Join-Path $OutDir "time_${Label}_${Opt}_t${Threads}_r${Repeat}.txt"

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $output = & $Exe $Arg 2>&1
    $exitCode = $LASTEXITCODE
    $sw.Stop()
    $output | Out-File -Encoding ascii $Raw
    "PowerShell_elapsed_seconds=$($sw.Elapsed.TotalSeconds)" | Set-Content -Encoding ascii $TimeFile
    "exit_code=$exitCode" | Add-Content -Encoding ascii $TimeFile

    $lines = Get-Content $Raw
    foreach ($line in $lines | Select-Object -Skip 1) {
        if ($line.Trim().Length -gt 0) {
            Add-Content -Path $CsvPath -Value "$EnvironmentName,$Opt,$Threads,$Repeat,$line"
        }
    }
}

function Run-All {
    # Required assignment comparison: O0 vs O1 vs O2 vs O3.
    # Important run order: finish one workload completely before moving to the next workload.
    # Order: CPU -> Memory -> File I/O -> Mixed.

    Log "PHASE 1/4: CPU workload, all optimization levels"
    foreach ($opt in @("O0", "O1", "O2", "O3")) {
        foreach ($r in 1..$Repeats) {
            Run-One "cpu_prime_baseline" (Join-Path $BinDir "cpu_prime_baseline_${opt}.exe") $CpuLimit $opt 1 $r
        }
        foreach ($th in $ThreadsToTest) {
            foreach ($r in 1..$Repeats) {
                Run-One "cpu_prime_optimized" (Join-Path $BinDir "cpu_prime_optimized_${opt}.exe") $CpuLimit $opt $th $r
            }
        }
    }

    Log "PHASE 2/4: Memory workload, all optimization levels"
    foreach ($opt in @("O0", "O1", "O2", "O3")) {
        foreach ($r in 1..$Repeats) {
            Run-One "memory_matrix_baseline" (Join-Path $BinDir "memory_matrix_baseline_${opt}.exe") $MatrixN $opt 1 $r
        }
        foreach ($th in $ThreadsToTest) {
            foreach ($r in 1..$Repeats) {
                Run-One "memory_matrix_optimized" (Join-Path $BinDir "memory_matrix_optimized_${opt}.exe") $MatrixN $opt $th $r
            }
        }
    }

    Log "PHASE 3/4: File I/O workload, all optimization levels"
    foreach ($opt in @("O0", "O1", "O2", "O3")) {
        foreach ($r in 1..$Repeats) {
            Run-One "file_io_benchmark" (Join-Path $BinDir "file_io_benchmark_${opt}.exe") $IoMB $opt 1 $r
        }
    }

    Log "PHASE 4/4: Mixed sorting workload, all optimization levels"
    foreach ($opt in @("O0", "O1", "O2", "O3")) {
        foreach ($r in 1..$Repeats) {
            Run-One "mixed_sort_baseline" (Join-Path $BinDir "mixed_sort_baseline_${opt}.exe") $SortN $opt 1 $r
        }
        foreach ($th in $ThreadsToTest) {
            foreach ($r in 1..$Repeats) {
                Run-One "mixed_sort_optimized" (Join-Path $BinDir "mixed_sort_optimized_${opt}.exe") $SortN $opt $th $r
            }
        }
    }
}

Collect-SystemInfo
Build-One "-O0" "O0"
Build-One "-O1" "O1"
Build-One "-O2" "O2"
Build-One "-O3" "O3"
Run-All

Log "Finished. Results saved in: $OutDir"
Write-Host "Results folder: $OutDir"
Write-Host "Main CSV: $CsvPath"
