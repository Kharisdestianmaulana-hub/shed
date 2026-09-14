# Shed

A native macOS utility application built with SwiftUI designed for intelligent storage management, system cleaning, and performance optimization. Shed aims to provide a safe, transparent, and highly performant alternative to traditional macOS cleaning tools by utilizing modern Swift concurrency and native macOS APIs.

## Overview

Shed was built from the ground up to address common issues found in macOS maintenance software. Rather than relying on opaque cleaning mechanisms, Shed provides full transparency into what is being analyzed and removed. It leverages modern Apple frameworks to ensure stability and efficiency, operating entirely within the boundaries of macOS security protocols.

## Key Features

### Mac Health Dashboard
The dashboard serves as the central hub for monitoring your system's current state. It provides real-time insights into active RAM usage, CPU temperature metrics, and a comprehensive overview of your disk space allocation.

### Storage Analyzer & Crawler
Shed uses a highly concurrent storage crawler powered by Swift's async/await and Actor model. It can rapidly scan deep directory trees across both the user home directory and root system paths without freezing the main thread. It categorizes files intelligently and maps out disk usage visually.

### App Uninstaller
Dragging an application to the Trash often leaves behind gigabytes of cached data. Shed's App Uninstaller resolves this by tracking down associated hidden files, including preference `.plist` files, `/Library/Application Support` directories, and system caches, ensuring a completely clean removal.

### Cryptographic Duplicate Finder
Unlike naive duplicate finders that simply compare file names and sizes, Shed uses full SHA-256 cryptographic hashing to accurately identify exact duplicate files. It scans iteratively to prevent memory spikes, ensuring that your data is safe and that only true duplicates are flagged.

### Quarantine Vault
Safety is a primary concern when deleting system files. The Quarantine Vault acts as an intermediary step before permanent deletion. Sensitive files are moved to a secure vault where they can be restored if necessary. An automatic background task safely purges items that have been in the vault for more than 30 days.

### Smart Rule Engine
Shed implements a rule-based engine for automated maintenance. Users can rely on pre-defined macOS rules to safely clear out old logs, Xcode derived data, and system caches without accidentally removing critical operating system components.

### Startup Manager
Take control of your Mac's boot time. Shed integrates directly with `launchctl` (bootstrap and bootout) to allow users to view, manage, and toggle system daemons and user login agents in real time.

### Native Localization
Shed automatically adapts to the user's preferred language natively. It currently features complete, human-translated localizations for both English and Indonesian.

## Technical Architecture

Shed is built strictly using modern Swift paradigms:
- **UI Framework**: 100% SwiftUI (Targeting macOS 12.0 and newer).
- **Architecture**: MVVM-A (Model-View-ViewModel-Actor) ensuring that all heavy I/O operations are isolated from the main UI thread.
- **Concurrency**: Extensive use of Swift Async/Await, TaskGroups, and Actors to prevent race conditions during high-speed file enumeration.
- **Disk I/O**: Direct integration with `NSWorkspace`, `FileManager`, and `URLResourceValues` for optimal performance.

## Installation

### For Users
To install Shed without compiling the code yourself:
1. Navigate to the **Releases** tab on this repository.
2. Download the latest `Shed-vX.X.dmg` file.
3. Open the disk image and drag the Shed application into your `/Applications` folder.

### For Developers (Building from Source)
To compile and run the application locally:
1. Clone the repository:
   ```bash
   git clone https://github.com/Kharisdestianmaulana-hub/shed.git
   ```
2. Open `Shed.xcodeproj` using Xcode 14 or newer.
3. Ensure the active scheme is set to **Shed** and the destination is **My Mac**.
4. Press `Cmd + R` to build and run the application.

## Building a Release Image

If you wish to distribute the application or create your own `.dmg` installer, you can use the following command to build the release binary:

```bash
xcodebuild -project Shed.xcodeproj -scheme Shed -configuration Release -derivedDataPath ./DerivedData CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO clean build
```
*Note: You will need a utility like `create-dmg` to package the resulting `.app` into a disk image.*

## Contributing

Contributions are highly encouraged and welcome. If you have an idea for a new feature, a bug fix, or an improvement to the existing codebase, please follow these steps:

1. Fork the repository.
2. Create a new feature branch (`git checkout -b feature/your-feature-name`).
3. Commit your changes with clear, descriptive messages (`git commit -m "Add your feature"`).
4. Push the branch to your fork (`git push origin feature/your-feature-name`).
5. Open a Pull Request against the `main` branch of this repository.

Please ensure that your code adheres to the existing architectural patterns (MVVM-A) and that heavy operations do not block the main thread.

## License

This project is released under a **Custom Source-Available License**. 

You are highly encouraged to read the source code for educational purposes and contribute to this repository via Pull Requests. However, you are **strictly prohibited** from using this source code (in whole or in part) to create, distribute, or publish a new application or derivative work without explicit written permission.

See the `LICENSE` file for full legal details.
