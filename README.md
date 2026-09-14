# Shed 🧹

A native macOS utility application built with SwiftUI for intelligent storage management, system cleaning, and performance optimization.

<p align="center">
  <img src="https://raw.githubusercontent.com/github/explore/80688e429a7d4ef2fca1e82350fe8e3517d3494d/topics/macos/macos.png" width="80" height="80">
  <img src="https://raw.githubusercontent.com/github/explore/80688e429a7d4ef2fca1e82350fe8e3517d3494d/topics/swift/swift.png" width="80" height="80">
</p>

## ✨ Features

- **Mac Health Dashboard**: Visual representation of RAM usage, CPU temperature insights, and disk space overview.
- **Storage Analyzer & Crawler**: Scan your entire file system (`/` and `~`) with high concurrency, utilizing Swift Concurrency (Actors, `TaskGroup`) to safely analyze deep directories and locate storage hogs.
- **App Uninstaller**: Cleanly remove applications along with their hidden `.plist` preferences, `/Library/Application Support` caches, and system leftovers.
- **Duplicate Finder**: Safely find duplicate files using full cryptographic hashing (SHA-256) instead of naive file size comparisons.
- **Quarantine Vault**: Move sensitive files into a secure vault instead of deleting them outright. Includes an auto-cleanup feature for items left over 30 days.
- **Smart Rule Engine**: Define cleaning rules (e.g. "Only delete .log files older than 7 days") directly implemented via macOS APIs.
- **Startup Manager**: Manage your login items and system daemons via direct `launchctl bootstrap` & `bootout` integrations.
- **Full Localization**: Seamlessly supports both English and Indonesian natively.

## 🛠 Tech Stack
- **UI Framework**: SwiftUI (macOS 12.0+)
- **Architecture**: MVVM-A (Model-View-ViewModel-Actor)
- **Concurrency**: Swift Async/Await, Actors, MainActor
- **Disk I/O**: `NSWorkspace`, `FileManager.default.enumerator`, `launchctl`

## 🚀 Getting Started

1. Clone the repository:
   ```bash
   git clone https://github.com/Kharisdestianmaulana-hub/shed.git
   ```
2. Open `Shed.xcodeproj` in Xcode.
3. Ensure your build target is set to **My Mac**.
4. Press `Cmd + R` to build and run the app.

## 📦 Building a Release

To build a standalone `.dmg` installer:
```bash
xcodebuild -project Shed.xcodeproj -scheme Shed -configuration Release -derivedDataPath ./DerivedData CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO clean build
```

## ⚖️ License
This project is for personal portfolio and educational purposes.
