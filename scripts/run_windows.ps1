New-Item -ItemType Directory -Force -Path results | Out-Null
$bin = ".\build\Release"
if (!(Test-Path "$bin\cpu_prime_baseline.exe")) { $bin = ".\build" }
& "$bin\cpu_prime_baseline.exe" 120000 | Tee-Object results\cpu_prime_baseline.csv
& "$bin\cpu_prime_optimized.exe" 120000 | Tee-Object results\cpu_prime_optimized.csv
& "$bin\memory_matrix_baseline.exe" 512 | Tee-Object results\memory_matrix_baseline.csv
& "$bin\memory_matrix_optimized.exe" 512 | Tee-Object results\memory_matrix_optimized.csv
& "$bin\file_io_benchmark.exe" 256 | Tee-Object results\file_io.csv
& "$bin\mixed_sort_baseline.exe" 5000000 | Tee-Object results\mixed_sort_baseline.csv
& "$bin\mixed_sort_optimized.exe" 5000000 | Tee-Object results\mixed_sort_optimized.csv
