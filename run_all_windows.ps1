# One-command runner for native Windows using GCC from MSYS2/MinGW-w64.
# Run from PowerShell inside the perf_benchmark_c_suite folder:
#   powershell -ExecutionPolicy Bypass -File .\run_all_windows.ps1 native_windows

param(
    [string]$EnvironmentName = "native_windows",
    [int]$Repeats = 5,
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
"environment,opt_level,threads,repeat,workload,version,seconds,metric_name_or_value,extra,resource_cpu_seconds_total,resource_cpu_percent,resource_peak_rss_kb,resource_io_read,resource_io_write" | Set-Content -Path $CsvPath -Encoding ascii

function Run-One($Label, $Exe, $Arg, $Opt, $Threads, $Repeat) {
    Log "Running $Label opt=$Opt threads=$Threads repeat=$Repeat"
    $env:OMP_NUM_THREADS = [string]$Threads
    $Raw = Join-Path $OutDir "raw_${Label}_${Opt}_t${Threads}_r${Repeat}.txt"
    $Err = Join-Path $OutDir "err_${Label}_${Opt}_t${Threads}_r${Repeat}.txt"
    $TimeFile = Join-Path $OutDir "time_${Label}_${Opt}_t${Threads}_r${Repeat}.txt"

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $proc = Start-Process -FilePath $Exe -ArgumentList $Arg -PassThru -NoNewWindow -RedirectStandardOutput $Raw -RedirectStandardError $Err
    $peakWorkingSet = 0
    $peakIoRead = 0
    $peakIoWrite = 0
    $lastCpuSeconds = 0.0

    while ($true) {
        try {
            $p = Get-Process -Id $proc.Id -ErrorAction Stop
            if ($p.PeakWorkingSet64 -gt $peakWorkingSet) { $peakWorkingSet = $p.PeakWorkingSet64 }
            if ($p.PSObject.Properties.Name -contains "IOReadBytes" -and $p.IOReadBytes -gt $peakIoRead) { $peakIoRead = [int64]$p.IOReadBytes }
            if ($p.PSObject.Properties.Name -contains "IOWriteBytes" -and $p.IOWriteBytes -gt $peakIoWrite) { $peakIoWrite = [int64]$p.IOWriteBytes }
            if ($p.CPU -gt $lastCpuSeconds) { $lastCpuSeconds = [double]$p.CPU }
        } catch { break }
        Start-Sleep -Milliseconds 50
    }

    $sw.Stop()
    $exitCode = $proc.ExitCode
    $cpuSeconds = $lastCpuSeconds
    $peakRssKb = if ($peakWorkingSet -gt 0) { [math]::Round($peakWorkingSet / 1KB, 0) } else { "" }
    $ioRead = if ($peakIoRead -gt 0) { [double]$peakIoRead } else { "" }
    $ioWrite = if ($peakIoWrite -gt 0) { [double]$peakIoWrite } else { "" }
    $cpuPercent = if ($sw.Elapsed.TotalSeconds -gt 0) { [double](($cpuSeconds / $sw.Elapsed.TotalSeconds) * 100.0) } else { "" }

    "PowerShell_elapsed_seconds=$($sw.Elapsed.TotalSeconds)" | Set-Content -Encoding ascii $TimeFile
    "exit_code=$exitCode" | Add-Content -Encoding ascii $TimeFile
    "cpu_seconds_total=$cpuSeconds" | Add-Content -Encoding ascii $TimeFile
    "cpu_percent=$cpuPercent" | Add-Content -Encoding ascii $TimeFile
    "peak_rss_kb=$peakRssKb" | Add-Content -Encoding ascii $TimeFile
    "io_read=$ioRead" | Add-Content -Encoding ascii $TimeFile
    "io_write=$ioWrite" | Add-Content -Encoding ascii $TimeFile

    $lines = Get-Content $Raw
    foreach ($line in $lines | Select-Object -Skip 1) {
        if ($line.Trim().Length -gt 0) {
            $fields = $line.Split(",")
            if ($fields.Count -eq 4) {
                Add-Content -Path $CsvPath -Value "$EnvironmentName,$Opt,$Threads,$Repeat,$line,,${cpuSeconds},${cpuPercent},${peakRssKb},${ioRead},${ioWrite}"
            } else {
                Add-Content -Path $CsvPath -Value "$EnvironmentName,$Opt,$Threads,$Repeat,$line,${cpuSeconds},${cpuPercent},${peakRssKb},${ioRead},${ioWrite}"
            }
        }
    }
}

function Format-F6([double]$Value) {
    return $Value.ToString("F6", [System.Globalization.CultureInfo]::InvariantCulture)
}

function Generate-Averages {
    $rows = Import-Csv -Path $CsvPath
    $groups = @{}

    foreach ($row in $rows) {
        $key = "$($row.environment)|$($row.opt_level)|$($row.threads)|$($row.workload)|$($row.version)"
        if (-not $groups.ContainsKey($key)) {
            $groups[$key] = [ordered]@{
                environment = $row.environment
                opt_level = $row.opt_level
                threads = $row.threads
                workload = $row.workload
                version = $row.version
                samples = 0
                seconds_sum = 0.0
                metric_sum = 0.0
                extra_sum = 0.0
                extra_samples = 0
                cpu_seconds_sum = 0.0
                cpu_seconds_samples = 0
                cpu_percent_sum = 0.0
                cpu_percent_samples = 0
                peak_rss_sum = 0.0
                peak_rss_samples = 0
                io_read_sum = 0.0
                io_read_samples = 0
                io_write_sum = 0.0
                io_write_samples = 0
            }
        }

        $group = $groups[$key]
        $group.samples++
        $group.seconds_sum += [double]$row.seconds
        $group.metric_sum += [double]$row.metric_name_or_value
        if ($null -ne $row.extra -and $row.extra.Trim().Length -gt 0) {
            $group.extra_sum += [double]$row.extra
            $group.extra_samples++
        }
        if ($null -ne $row.resource_cpu_seconds_total -and $row.resource_cpu_seconds_total.Trim().Length -gt 0) {
            $group.cpu_seconds_sum += [double]$row.resource_cpu_seconds_total
            $group.cpu_seconds_samples++
        }
        if ($null -ne $row.resource_cpu_percent -and $row.resource_cpu_percent.Trim().Length -gt 0) {
            $group.cpu_percent_sum += [double]$row.resource_cpu_percent
            $group.cpu_percent_samples++
        }
        if ($null -ne $row.resource_peak_rss_kb -and $row.resource_peak_rss_kb.Trim().Length -gt 0) {
            $group.peak_rss_sum += [double]$row.resource_peak_rss_kb
            $group.peak_rss_samples++
        }
        if ($null -ne $row.resource_io_read -and $row.resource_io_read.Trim().Length -gt 0) {
            $group.io_read_sum += [double]$row.resource_io_read
            $group.io_read_samples++
        }
        if ($null -ne $row.resource_io_write -and $row.resource_io_write.Trim().Length -gt 0) {
            $group.io_write_sum += [double]$row.resource_io_write
            $group.io_write_samples++
        }
    }

    $AveragePath = Join-Path $OutDir "averages.csv"
    "environment,opt_level,threads,workload,version,samples,avg_seconds,avg_metric_value,avg_extra_value,avg_resource_cpu_seconds_total,avg_resource_cpu_percent,avg_resource_peak_rss_kb,avg_resource_io_read,avg_resource_io_write" | Set-Content -Path $AveragePath -Encoding ascii

    $groups.Values |
        Sort-Object environment, opt_level, threads, workload, version |
        ForEach-Object {
            $avgSeconds = Format-F6 ($_.seconds_sum / $_.samples)
            $avgMetric = Format-F6 ($_.metric_sum / $_.samples)
            $avgExtra = if ($_.extra_samples -gt 0) { Format-F6 ($_.extra_sum / $_.extra_samples) } else { "" }
            $avgCpuSeconds = if ($_.cpu_seconds_samples -gt 0) { Format-F6 ($_.cpu_seconds_sum / $_.cpu_seconds_samples) } else { "" }
            $avgCpuPercent = if ($_.cpu_percent_samples -gt 0) { Format-F6 ($_.cpu_percent_sum / $_.cpu_percent_samples) } else { "" }
            $avgPeakRss = if ($_.peak_rss_samples -gt 0) { Format-F6 ($_.peak_rss_sum / $_.peak_rss_samples) } else { "" }
            $avgIoRead = if ($_.io_read_samples -gt 0) { Format-F6 ($_.io_read_sum / $_.io_read_samples) } else { "" }
            $avgIoWrite = if ($_.io_write_samples -gt 0) { Format-F6 ($_.io_write_sum / $_.io_write_samples) } else { "" }
            $line = "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10},{11},{12},{13}" -f $_.environment, $_.opt_level, $_.threads, $_.workload, $_.version, $_.samples, $avgSeconds, $avgMetric, $avgExtra, $avgCpuSeconds, $avgCpuPercent, $avgPeakRss, $avgIoRead, $avgIoWrite
            Add-Content -Path $AveragePath -Value $line -Encoding ascii
        }
}

function Cleanup-EmptyErrorFiles {
    Get-ChildItem -Path $OutDir -Filter "err_*.txt" -File | Where-Object { $_.Length -eq 0 } | Remove-Item -Force
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
Generate-Averages
Cleanup-EmptyErrorFiles

Log "Finished. Results saved in: $OutDir"
Write-Host "Results folder: $OutDir"
Write-Host "Main CSV: $CsvPath"
Write-Host "Average CSV: $(Join-Path $OutDir 'averages.csv')"
