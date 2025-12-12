$env:ANDROID_HOME = "C:\Users\wdm17\AppData\Local\Android\sdk"
$env:ANDROID_NDK_HOME = "C:\Users\wdm17\AppData\Local\Android\sdk\ndk\28.2.13676358"
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:PATH = "$env:PATH;$env:ANDROID_HOME\platform-tools;$env:JAVA_HOME\bin"

Write-Host "Building Clash Core..."
Set-Location "core"
go mod tidy
go get golang.org/x/mobile/bind
gomobile bind -target=android -androidapi 21 -o ../android/app/libs/mobile.aar -ldflags="-s -w" -tags "with_gvisor" .
if ($LASTEXITCODE -eq 0) {
    Write-Host "Build Successful!"
} else {
    Write-Host "Build Failed!"
    exit 1
}
