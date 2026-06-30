New-Item -ItemType Directory -Force -Path opt_builds, results | Out-Null
foreach ($opt in 0,1,2,3) {
    $dir = "opt_builds\O$opt"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    gcc -std=c11 -O$opt src\common.c src\cpu_prime_optimized.c -lm -fopenmp -o "$dir\cpu_prime_O$opt.exe"
    Measure-Command { & "$dir\cpu_prime_O$opt.exe" 120000 | Tee-Object "results\cpu_prime_O$opt.csv" } | Out-File "results\cpu_prime_O$opt_time.txt"
}
