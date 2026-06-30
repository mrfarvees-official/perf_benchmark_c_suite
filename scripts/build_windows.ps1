New-Item -ItemType Directory -Force -Path build | Out-Null
Set-Location build
cmake -DCMAKE_BUILD_TYPE=Release ..
cmake --build . --config Release --parallel
Set-Location ..
