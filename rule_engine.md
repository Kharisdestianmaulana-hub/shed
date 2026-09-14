# rule_engine.md - macOS Path Classification Matrix

## 1. Domain Types

enum RiskLevel: String, CaseIterable, Codable {
    case safe = "Aman"
    case review = "Perlu Review"
    case locked = "Terproteksi Sistem"
}

enum CleanupCategory: String, CaseIterable, Codable {
    case userCaches = "Cache Aplikasi"
    case developerArtifacts = "Artefak Pengembang"
    case packageManagers = "Cache Paket Sistem"
    case systemLogs = "Berkas Log"
    case installers = "File Installer & Image"
    case staleFiles = "Berkas Besar Tak Tersentuh"
    case protectedSystem = "Integritas macOS (SIP)"
}

---

## 2. Aturan Jalur Spesifik macOS

### A. Level: Locked (Terproteksi Sistem / SIP)
Centang dinonaktifkan permanen. Aplikasi tidak akan menyentuh atau menghapus berkas di jalur ini.
* /System
* /usr/bin, /usr/sbin
* /sbin, /bin
* /Library/Apple
* /Library/SystemExtensions
* /private/var/db

### B. Level: Safe (Aman Dihapus / Otomatis Tercentang)
* User & App Caches:
  * ~/Library/Caches/*
  * /Library/Caches/*
  * /private/var/tmp/*
  * /tmp/*
* Developer Artifacts (Perlakukan folder sebagai single entity):
  * ~/Library/Developer/Xcode/DerivedData
  * ~/Library/Developer/Xcode/iOS DeviceSupport (versi lama)
  * Folder dengan nama node_modules
  * Folder .build (Swift Package Manager)
  * Folder .dart_tool & build/ (Flutter)
  * Cache compiler Rust: target/
* Package Managers:
  * Homebrew cache: ~/Library/Caches/Homebrew
  * CocoaPods cache: ~/Library/Caches/CocoaPods
  * NPM cache: ~/.npm/_cacache
* System & Diagnostic Logs:
  * ~/Library/Logs/*
  * /Library/Logs/*

### C. Level: Review (Perlu Tinjauan Pengguna / Centang Manual)
* Installer Images:
  * ~/Downloads/*.dmg
  * ~/Downloads/*pkg
  * ~/Downloads/*iso
* Stale Big Files:
  * Berkas apa pun di luar folder sistem dengan ukuran > 500 MB dan lastModifiedDate > 180 hari.
* Downloads Directory:
  * Berkas umum di folder ~/Downloads yang berumur lebih dari 30 hari.

---

## 3. Algoritma Optimasi Traversal

1. Periksa Whitelist: Jika path berada dalam daftar abaikan, panggil enumerator.skipDescendants().
2. Periksa Proteksi Sistem: Jika path diawali jalur locked, tandai RiskLevel.locked dan jangan scan rekursif ke dalamnya.
3. Penyatuan Folder Berat (Batch Skipping): Saat crawler menemukan folder DerivedData atau node_modules, jangan memindai ribuan sub-file di dalamnya satu per satu. Hitung ukuran direktori secara keseluruhan, tandai sebagai satu ScannedItem kategori safe, lalu panggil enumerator.skipDescendants() untuk menghemat I/O dan memori.
4. Metadata Filtering: Evaluasi ekstensi installer dan tanggal modifikasi berkas untuk mengelompokkan sisanya ke RiskLevel.review.
