# EdNovas Clash Mobile

A Flutter-based Android application for V2Board panels with Clash core integration.

## 🚀 Getting Started

### 1. Install Flutter SDK (Windows)

Since you are asking "how to install", here is a quick guide:

1.  **Download Flutter**: Go to the [Flutter official website](https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.16.9-stable.zip) (or latest stable version) and download the zip file.
2.  **Extract**: Extract the zip file to a location like `C:\src\flutter`. (Do *not* install in `C:\Program Files`).
3.  **Update Path**:
    *   Search for "Environment Variables" in your Windows search bar.
    *   Click "Edit the system environment variables".
    *   Click "Environment Variables".
    *   Under "User variables", find `Path` and click "Edit".
    *   Click "New" and add `C:\src\flutter\bin`.
    *   Click OK to close all windows.
4.  **Verify**: Open a new PowerShell window and run `flutter doctor`.

### 2. Install Android Studio

1.  Download and install [Android Studio](https://developer.android.com/studio).
2.  During installation, ensure the **Android SDK** and **Android Virtual Device** components are selected.
3.  Open Android Studio, go to **Settings > Languages & Frameworks > Android SDK**, and install the standard SDK tools.
4.  Accept the android licenses by running this command in PowerShell:
    ```powershell
    flutter doctor --android-licenses
    ```

### 3. Setup Project

1.  Open this folder in VS Code or Android Studio.
2.  Run dependencies installation:
    ```powershell
    flutter pub get
    ```

### 4. Run Locally

1.  **Launch Emulator**: Open Android Studio > Device Manager, and start a virtual device (Pixel recommended).
2.  **Run**:
    ```powershell
    flutter run
    ```

## 📦 Features

- **V2Board Integration**: Login & Subscription management.
- **Clash Core**: Proxy traffic routing (simulated/abstracted for UI demo).
- **Modern UI**: Dark mode, animated connect button, bottom sheet node selector.

## 🔨 Build & Release

The project is configured with GitHub Actions to automatically build APKs on push to the `main` branch.

To build manually:
```powershell
flutter build apk --release
```
