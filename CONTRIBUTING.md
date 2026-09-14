# Contributing to Shed

First off, thank you for considering contributing to Shed. It is people like you that make open source tools great. 

Shed is a macOS utility application built natively with SwiftUI. Our goal is to provide a highly performant, transparent, and safe storage management tool. We welcome contributions that align with this vision, whether they are bug fixes, new features, or documentation improvements.

## Code of Conduct

By participating in this project, you are expected to uphold a welcoming and professional environment. Please be respectful to other contributors. Harassment, discriminatory language, or unprofessional conduct will not be tolerated.

## How Can I Contribute?

### Reporting Bugs
If you find a bug, please open an issue in the GitHub repository. When logging a bug, please include:
- A clear and descriptive title.
- The version of Shed and the version of macOS you are using.
- Exact steps to reproduce the issue.
- Expected behavior vs actual behavior.
- Any relevant logs or crash reports.

### Suggesting Enhancements
We are always open to new ideas. If you want to propose a new feature:
- Open an issue categorized as an enhancement.
- Describe the feature in detail and explain the specific problem it solves.
- If possible, provide mockups or references to native macOS design patterns that fit the SwiftUI interface.

### Pull Requests
Ready to write some code? Great! Please follow this workflow:

1. **Fork the Repository**: Create a fork of the `shed` repository to your own GitHub account.
2. **Clone the Fork**: Clone your fork locally (`git clone https://github.com/YOUR-USERNAME/shed.git`).
3. **Create a Branch**: Create a new branch for your feature or bug fix (`git checkout -b feature/your-feature-name`).
4. **Develop**: Write your code. Ensure you adhere to the architectural guidelines listed below.
5. **Test**: Build and test the application locally. Ensure no existing features are broken.
6. **Commit**: Commit your changes with clear, descriptive commit messages.
7. **Push**: Push your branch to your fork (`git push origin feature/your-feature-name`).
8. **Submit a Pull Request**: Open a PR against the `main` branch of the official repository. Describe your changes thoroughly in the PR description.

## Architectural Guidelines

To maintain the performance and safety of Shed, please adhere to the following technical guidelines when contributing code:

- **SwiftUI Exclusivity**: All user interfaces must be built using SwiftUI. Avoid falling back to AppKit (NSView/NSViewController) unless absolutely necessary for a feature SwiftUI cannot handle natively.
- **MVVM-A Pattern**: We use the Model-View-ViewModel-Actor architecture. Views should only handle UI rendering. ViewModels manage state and format data. Heavy lifting, especially file system scanning, must be delegated to Actors.
- **Concurrency**: Do not block the Main Thread. Any disk I/O, file enumeration, or heavy computation must be done asynchronously using Swift's `async/await` and `Task` structures.
- **Safety First**: Since Shed deals with file deletion, any destructive action must include a user confirmation prompt. Avoid force-unwrapping optionals (`!`); handle errors gracefully to prevent crashes.

## Development Setup

1. You must have Xcode 14 or later installed.
2. Open `Shed.xcodeproj`.
3. Set the active scheme to **Shed** and the destination to **My Mac**.
4. Press `Cmd + R` to compile and run.

If your changes involve file deletion or system modifications, you may need to grant the locally compiled application Full Disk Access in your System Settings during testing.

## License & Contributor Agreement

Shed operates under a custom Source-Available License. By submitting a Pull Request or contributing code to this repository, you explicitly agree that:
1. You grant the repository owner a perpetual, worldwide, non-exclusive, royalty-free license to use, modify, and distribute your contributions.
2. You understand that the source code of Shed cannot be used by you or anyone else to create derivative applications or competing products outside of this official repository.
