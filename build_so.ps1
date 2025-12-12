$env:ANDROID_HOME = "C:\Users\wdm17\AppData\Local\Android\sdk"
$env:ANDROID_NDK_HOME = "C:\Users\wdm17\AppData\Local\Android\sdk\ndk\28.2.13676358"
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:PATH = "$env:PATH;$env:ANDROID_HOME\platform-tools;$env:JAVA_HOME\bin"

# Correct Clang path in NDK 28
# NDK 28 is llvm based.
$TOOLCHAIN = "$env:ANDROID_NDK_HOME\toolchains\llvm\prebuilt\windows-x86_64"
$CC_BIN = "$TOOLCHAIN\bin"

Write-Host "Building Clash Core as Shared Library (.so)..."
Set-Location "core"

# Define Targets
# Maps: Android ABI -> (GOARCH, CC Target Triple)
$TARGETS = @{
    "arm64-v8a"   = @("arm64", "aarch64-linux-android34-clang")
    "armeabi-v7a" = @("arm",   "armv7a-linux-androideabi34-clang")
    "x86_64"      = @("amd64", "x86_64-linux-android34-clang")
}

foreach ($key in $TARGETS.Keys) {
    $abi = $key
    $arch = $TARGETS[$key][0]
    $clang = $TARGETS[$key][1]
    
    $outputDir = "../android/app/src/main/jniLibs/$abi"
    $outputFile = "$outputDir/libclash.so"
    
    # Ensure dir exists
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    
    Write-Host "Compiling for $abi ($arch)..."
    
    $env:GOOS = "android"
    $env:GOARCH = $arch
    $env:CGO_ENABLED = "1"
    $env:CC = "$CC_BIN\$clang.cmd" # Windows NDK often has .cmd or .exe
    if (-not (Test-Path "$env:CC")) {
         $env:CC = "$CC_BIN\$clang" # Try without extension if cmd missing but exe exists (unlikely for clang wrapper)
    }

    # Verify CC exists
    if (-not (Test-Path "$env:CC")) {
        Write-Error "Compiler not found at $env:CC"
        exit 1
    }

    go build -buildmode=c-shared -o $outputFile -tags "with_gvisor,cmfa" -ldflags="-s -w" .
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Build failed for $abi"
        exit 1
    }
}

Write-Host "Build Complete!"
