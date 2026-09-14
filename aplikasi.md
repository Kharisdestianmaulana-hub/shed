# Shed — Aplikasi Pembersih & Utilitas macOS Native

## Ringkasan Singkat

**Shed** adalah aplikasi utilitas macOS yang dibangun 100% native menggunakan **SwiftUI + AppKit**. Aplikasi ini berfungsi untuk membersihkan file sampah, mengelola penyimpanan, mengoptimasi RAM, dan memberikan kontrol penuh atas startup agents — semua dikemas dalam satu antarmuka yang modern dengan arsitektur berbasis *Swift Concurrency*.

- **Platform:** macOS (min. Ventura / macOS 13+)
- **Bahasa Pemrograman:** Swift 5.7+
- **UI Framework:** SwiftUI (dengan bridge AppKit via `NSApplicationDelegateAdaptor`)
- **Concurrency Model:** Swift `actor`, `async/await`, `AsyncStream`
- **Lokalisasi:** Bahasa Indonesia (default) dan English (245 string terlokalisasi per bahasa)

---

## Arsitektur Teknis

### Pola Arsitektur
Aplikasi menggunakan pola **MVVM (Model-View-ViewModel)** dengan variasi:
- **Actor** untuk operasi I/O berat dan thread-safe (scanning filesystem)
- **@MainActor ViewModel** untuk memastikan semua mutasi UI terjadi di main thread
- **Singleton Manager** (`DailyReportManager.shared`, `RAMManager.shared`, `QuarantineManager.shared`, `ScanCacheManager.shared`) untuk state global

### Struktur Folder Proyek
```
Shed/
├── App/
│   └── AppDelegate.swift            — Menu Bar (NSStatusItem) + NSPopover
├── Core/
│   ├── Enums/
│   │   ├── CleanupCategory.swift    — 10 kategori pembersihan (cache, dev artifacts, installer, dll)
│   │   └── RiskLevel.swift          — 3 tingkat risiko: Aman, Perlu Review, Terproteksi Sistem
│   ├── Extensions/
│   │   └── URL+Attributes.swift     — Helper property: fileSize, lastModifiedDate, isDirectory, Int64.formattedSize
│   └── Permissions/
│       └── FullDiskAccessHelper.swift — Cek & buka System Settings untuk Full Disk Access
├── Features/
│   ├── Cleaner/Services/
│   │   └── PurgeService.swift       — 3 mode hapus (Trash, Karantina, Permanen) + QuarantineManager + QuarantineMetadata
│   ├── Crawler/
│   │   ├── Actors/
│   │   │   ├── StorageCrawlerActor.swift   — Smart Scan crawler (AsyncStream<CrawlerEvent>)
│   │   │   ├── DuplicateFinderActor.swift  — SHA256 hash-based duplicate finder
│   │   │   └── LargeFilesActor.swift       — Large/Old/Installer file radar
│   │   └── Models/
│   │       └── ScannedItem.swift    — Model utama hasil scan (url, size, category, riskLevel, isSelected)
│   └── RuleEngine/Services/
│       └── MacOSRuleEngine.swift    — Aturan keamanan: path mana yang aman/perlu review/terkunci (SIP)
├── Views/
│   ├── MainSplitView.swift          — File utama (~3670 baris): semua View, ViewModel, dan komponen UI
│   ├── Components/
│   │   └── PreviewSavingsBar.swift  — Bottom action bar dengan menu dropdown (Trash/Karantina/Hapus Permanen)
│   ├── Sidebar/
│   │   └── StorageGaugeView.swift   — Widget ringkasan ukuran total file ditemukan
│   └── Workspace/
│       └── ItemListView.swift       — List view generik untuk menampilkan hasil scan dengan toggle, badge risiko, dan tombol Reveal in Finder
├── en.lproj/Localizable.strings     — 245 string terjemahan English
├── id.lproj/Localizable.strings     — 245 string terjemahan Bahasa Indonesia
└── ShedApp.swift                    — Entry point (@main), routing Onboarding vs MainSplitView, injeksi locale & tema
```

### Model Data Inti

| Model | Properti Utama | Kegunaan |
|---|---|---|
| `ScannedItem` | `url`, `size`, `category`, `riskLevel`, `isSelected`, `isDirectory` | Representasi setiap file/folder hasil scan |
| `DuplicateGroup` | `size`, `hash`, `files: [URL]` | Grup file duplikat (SHA256 hash match) |
| `AppUninstallItem` | `name`, `bundleId`, `appURL`, `icon`, `appSize`, `associatedURLs`, `associatedSize` | Representasi aplikasi + file sisa tersembunyi |
| `FolderOrganizerItem` | `url`, `category`, `size`, `isSelected` | File dalam folder yang siap diorganisir per kategori |
| `StartupItem` | `name`, `type`, `plistURL`, `isEnabled`, `canModify` | LaunchAgent/LaunchDaemon entry |
| `QuarantineMetadata` | `originalPath`, `quarantinedPath`, `fileName`, `size`, `quarantinedAt` | Catatan file yang sedang dikarantina |
| `RAMInfo` | `total`, `used`, `free`, `percentage` | Status penggunaan RAM real-time |
| `SwipeCardItem` | `title`, `subtitle`, `sizeString`, `fileURL`, `onSwipeLeft`, `onSwipeRight` | Data untuk UI kartu swipe |

### Enum Penting

**`CleanupCategory`** — Kategori pembersihan:
- `userCaches` (Cache Aplikasi), `developerArtifacts` (Artefak Pengembang: DerivedData, node_modules, .build, .dart_tool)
- `packageManagers` (Cache Paket Sistem), `systemLogs` (Berkas Log)
- `installers` (File Installer & Image: .dmg, .pkg, .iso)
- `largeFiles` (Berkas Raksasa >1GB), `oldFiles` (Berkas Usang >1 Tahun & >100MB)
- `staleFiles`, `protectedSystem` (SIP), `uncategorized`

**`RiskLevel`** — Tingkat risiko:
- `safe` (Aman — hijau, siap hapus tanpa pikir panjang)
- `review` (Perlu Review — kuning, pengguna harus cek dulu)
- `locked` (Terproteksi Sistem — merah, tidak bisa dihapus, dilindungi SIP)

**`PurgeAction`** — Metode penghapusan:
- `trash` (Pindahkan ke Tong Sampah macOS)
- `quarantine` (Pindahkan ke folder karantina Shed dengan metadata untuk restore)
- `permanent` (Hapus permanen dari disk)

---

## Fitur-Fitur Lengkap

### 1. 🚀 Onboarding (4 Langkah)
Alur setup awal saat pertama kali membuka aplikasi:
1. **Sambutan** — Pengenalan aplikasi Shed
2. **Izin Full Disk Access** — Memandu pengguna membuka System Preferences > Privacy > Full Disk Access. Timer 1 detik otomatis mendeteksi saat izin sudah diberikan
3. **Pengenalan Menu Bar** — Menjelaskan bahwa Shed juga hidup di pojok kanan atas Mac
4. **Izin Notifikasi** — Meminta izin `UNUserNotificationCenter` untuk Laporan Malam jam 21:00

Onboarding tidak bisa di-skip: selama belum selesai, jendela Settings otomatis ditutup paksa (`NSApp.windows...close()`).

### 2. 🏠 Dasbor Utama (Dashboard)
Halaman utama dengan navigasi cepat ke semua fitur:
- **Tombol "Pindah ke Pembersih Pintar"** — shortcut langsung ke Smart Scan
- **Jam ikon** — berfungsi sebagai shortcut ke Daily Report
- Navigasi ke seluruh modul melalui sidebar

### 3. 🧹 Pembersih Pintar (Smart Scan) — `SmartScanView` + `AppViewModel`
Pemindaian cerdas menggunakan `StorageCrawlerActor` + `MacOSRuleEngine`:

**Cara kerja:**
1. `StorageCrawlerActor` merayapi filesystem menggunakan `FileManager.enumerator()` secara asinkron
2. Setiap URL dievaluasi oleh `MacOSRuleEngine.evaluate(url:)` → mengembalikan `(RiskLevel, CleanupCategory, Bool)`
3. Hasil dikumpulkan per batch (setiap 100 file) dan di-stream ke UI via `AsyncStream<CrawlerEvent>`
4. UI menampilkan file secara real-time dengan animasi `.spring()` (diurutkan dari terbesar)

**Target pemindaian:**
- Xcode `DerivedData`
- `node_modules` / `.build` / `.dart_tool`
- Folder `~/Library/Caches/` (per-app cache)
- Folder `~/Library/Logs/`
- File `.dmg`, `.pkg`, `.iso` (installer)
- File >1GB (berkas raksasa)
- File >100MB yang tidak dimodifikasi selama >1 tahun

**Fitur tambahan:**
- **Filter mode:** Semua / Aman (Siap Hapus) / Perlu Review
- **Cache hasil scan:** `ScanCacheManager.shared` menyimpan hasil agar scan ulang instan
- **Whitelist:** Folder yang dimasukkan ke daftar pengecualian akan di-skip (termasuk sub-foldernya)
- **Reveal in Finder:** Tombol kaca pembesar per item untuk membuka lokasi file di Finder

### 4. 👯 Berkas Kembar (Duplicate Finder) — `DuplicatesView` + `DuplicatesViewModel`
Menemukan file duplikat menggunakan perbandingan hash SHA256:

**Cara kerja:**
1. `DuplicateFinderActor` memindai `Downloads`, `Documents`, `Desktop` (atau disk yang dipilih)
2. Fase 1: Mengelompokkan file berdasarkan ukuran (hanya file >10KB untuk efisiensi)
3. Fase 2: Untuk setiap grup ukuran yang memiliki >1 file, hitung hash SHA256 dari 1MB pertama file
4. Fase 3: File dengan hash identik dikelompokkan sebagai `DuplicateGroup`
5. Hasil diurutkan dari ukuran terbesar

**Fitur:**
- Menampilkan grup duplikat dalam section/accordion
- Toggle per file untuk memilih mana yang ingin dihapus
- Tombol "Reveal in Finder" per file
- Mendukung mode Swipe

### 5. 🐘 Radar Berkas Raksasa (Large Files Finder) — `LargeFilesView` + `LargeFilesViewModel`
Menemukan file-file besar yang memakan ruang disk:

**Kriteria deteksi oleh `LargeFilesActor`:**
- File >1GB → kategori `largeFiles`
- File >100MB yang tidak dimodifikasi >1 tahun → kategori `oldFiles`
- File `.dmg`/`.pkg`/`.iso` yang >50MB → kategori `installers`

**Fitur:**
- Streaming real-time (progress count + current path ditampilkan)
- Mematuhi whitelist
- Cache hasil scan
- Mendukung mode Swipe

### 6. 🗑️ App Uninstaller — `AppUninstallerView` + `AppUninstallerViewModel`
Penghapusan aplikasi beserta seluruh file tersembunyi:

**Cara kerja `AppUninstallerActor`:**
1. Memindai `/Applications` dan `~/Applications` untuk file `.app`
2. Membaca `Bundle.bundleIdentifier` setiap aplikasi
3. Mencari file terkait di 6 lokasi tersembunyi:
   - `~/Library/Application Support/`
   - `~/Library/Caches/`
   - `~/Library/Preferences/`
   - `~/Library/Containers/`
   - `~/Library/Logs/`
   - `~/Library/Saved Application State/`
4. Pencocokan berdasarkan `bundleId` DAN `nama aplikasi`
5. Menghitung `associatedSize` (ukuran total file sisa)

**Fitur:**
- Menampilkan ikon aplikasi asli (`NSWorkspace.icon(forFile:)`)
- Menampilkan ukuran aplikasi + ukuran data sisa
- Menggunakan `NSWorkspace.recycle()` untuk menghapus ke Trash (dengan konfirmasi macOS)
- Mendukung mode Swipe
- Aplikasi Apple (prefix `com.apple.`) otomatis di-skip

### 7. 📁 Folder Organizer — `FolderOrganizerView` + `FolderOrganizerViewModel`
Alat perapih folder otomatis:

**Cara kerja `FolderOrganizerActor`:**
1. Pengguna memilih folder target (misal: `~/Downloads`)
2. Actor memindai isi folder dan mengkategorikan setiap file berdasarkan ekstensi:
   - **Images:** jpg, jpeg, png, gif, heic, webp, svg, bmp, tiff
   - **Videos:** mp4, mov, mkv, avi, webm, flv, wmv
   - **Audio:** mp3, wav, aac, flac, ogg, m4a
   - **Documents:** pdf, doc, docx, xls, xlsx, ppt, pptx, txt, csv, rtf
   - **Archives:** zip, rar, 7z, tar, gz, bz2
   - **Installers:** dmg, pkg, iso
   - **Others:** ekstensi lainnya
3. Pengguna memilih file yang ingin diorganisir
4. File dipindahkan ke sub-folder berdasarkan kategori (misal: `Downloads/Images/`, `Downloads/Videos/`)

**Fitur:**
- Tombol "Pilih Folder" via `NSOpenPanel`
- Toggle per file
- Cache hasil scan + URL folder terakhir
- Menampilkan ikon kategori dan ukuran file

### 8. ⚙️ Pengelola Startup — `StartupManagerView` + `StartupViewModel`
Mengelola LaunchAgents dan LaunchDaemons:

**Cara kerja `StartupManagerActor`:**
1. Memindai 3 direktori plist:
   - `~/Library/LaunchAgents/` (User Agent)
   - `/Library/LaunchAgents/` (System Agent)
   - `/Library/LaunchDaemons/` (System Daemon)
2. Membaca setiap file `.plist` untuk mendapatkan label, status enabled/disabled
3. Menentukan apakah item bisa dimodifikasi (`canModify`)

**Fitur:**
- Dikelompokkan per tipe (User Agent / System Agent / System Daemon) dalam section
- Toggle per item untuk enable/disable
- Item yang tidak bisa dimodifikasi ditampilkan dengan ikon gembok
- Tombol refresh untuk scan ulang

### 9. 🛡️ Ruang Karantina (Quarantine Vault) — `QuarantineVaultView` + `QuarantineVaultViewModel`
Area penyimpanan aman untuk file yang belum siap dihapus permanen:

**Cara kerja `QuarantineManager`:**
1. File yang dikarantina dipindahkan ke `~/Documents/Shed_Karantina/`
2. Metadata disimpan di `~/Library/Application Support/Shed/quarantine_metadata.json`
3. Metadata mencatat: `originalPath`, `quarantinedPath`, `fileName`, `size`, `quarantinedAt`
4. Saat restore: file dikembalikan ke `originalPath` (folder parent dibuat ulang jika sudah tidak ada)
5. Saat destroy: file dihapus permanen + metadata dihapus dari JSON

**Fitur:**
- Menampilkan nama file, lokasi asal, ukuran, dan tanggal karantina
- Tombol **Pulihkan (Restore)** — mengembalikan file ke lokasi aslinya
- Tombol **Hapus Permanen** — menghapus file selamanya
- Validasi: file yang sudah tidak ada di disk otomatis dikeluarkan dari daftar

### 10. 🃏 Mode Review Swipe (Tinder-Style) — `SwipeCardView` + `SwipeCardContainer`
Mode alternatif untuk mengulas file satu per satu menggunakan gesture swipe:

**Cara kerja:**
1. File hasil scan di-map menjadi `SwipeCardItem` (dengan callback `onSwipeLeft` dan `onSwipeRight`)
2. `SwipeCardContainer` menampilkan tumpukan kartu (max 3 terlihat sekaligus, skala berkurang untuk efek kedalaman)
3. Pengguna bisa drag kartu ke kiri/kanan dengan threshold 100pt
4. Saat drag: background kartu berubah hijau (kanan/keep) atau merah (kiri/delete)
5. Saat release melewati threshold: animasi kartu terbang keluar + callback dipanggil
6. Tombol arrow left/right di bawah kartu sebagai alternatif gesture

**Fitur teknis:**
- Thumbnail otomatis via `QLThumbnailGenerator` (menampilkan preview gambar/dokumen)
- Fallback icon: folder → `folder.fill`, file → `doc.fill`
- Animasi `.spring(response: 0.4, dampingFraction: 0.7)`
- ID stabil (menggunakan `item.id` bukan `UUID()` baru) untuk mencegah reset state saat re-render

**Tersedia di modul:** Smart Scan, Duplicate Finder, Large Files, App Uninstaller

### 11. 📊 Laporan Malam (Daily Report) — `DailyReportView` + `DailyReportManager`
Ringkasan kesehatan Mac yang muncul otomatis setiap malam:

**Mekanisme waktu:**
- `DailyReportManager` menjalankan timer setiap 60 detik
- Antara jam 21:00 – 05:59: menu "Laporan Malam Ini" muncul di sidebar (dengan ikon bulan)
- Counter `dailySavedBytes` di-reset setiap jam 06:00

**Konten laporan (grid 2x2):**
1. **Rapor Kesehatan Mac** — status ruang disk + sisa RAM
2. **Status Penyimpanan** — ukuran Trash + ukuran folder Downloads
3. **Waktu Istirahat Mac** — System Uptime (dengan peringatan jika >7 hari tanpa restart)
4. **Penghematan Total** — akumulasi total bytes yang pernah dibersihkan seumur hidup

**Saran Pintar:** Dua rekomendasi navigasi langsung (ke Folder Organizer dan Startup Manager)

**Notifikasi:** Mengirim notifikasi macOS setiap jam 21:00 via `UNCalendarNotificationTrigger`

### 12. 🔽 Shed Mini (Menu Bar App) — `MenuBarPopupView` + `AppDelegate`
Akses cepat dari pojok kanan atas layar Mac:

**Komponen:**
1. **Identitas & Penghematan** — menampilkan total bytes yang pernah dihemat
2. **Monitor RAM Real-Time** — circular gauge yang di-update setiap 2 detik via `Timer.publish`
3. **Tombol "Bebaskan RAM"** — menggunakan teknik *memory pressure*:
   - Mengalokasikan ~60% RAM fisik (`malloc`)
   - Menulis data sparse setiap 4MB untuk memaksa backing fisik
   - Menahan selama 1.5 detik agar macOS memicu kompresi memori
   - Melepas alokasi → macOS otomatis membebaskan halaman inaktif
4. **Tombol "Bersihkan Caches Sekarang"** — menghapus seluruh isi `~/Library/Caches/` dalam satu klik
5. **Kontrol** — "Buka Shed" (buka jendela utama) dan "Keluar" (terminate app)

**Detail teknis:**
- `NSPopover` dengan behavior `.transient` (otomatis tutup saat klik di luar)
- Ukuran 280x380 pixel
- `applicationShouldTerminateAfterLastWindowClosed` return `false` → app tetap hidup di menu bar meski jendela utama ditutup

### 13. 🔧 Pengaturan (Settings) — 4 Tab
Jendela pengaturan macOS native (`Settings` scene):

**Tab Umum (`SettingsGeneralView`):**
- Pilihan Bahasa: Bahasa Indonesia / English
- Tema Tampilan: Ikuti Sistem / Terang / Gelap
- Gaya Tampilan Scan: Mode Daftar (List) / Mode Kartu (Swipe)
- Target Disk: dropdown semua volume yang ter-mount (internal/external)

**Tab Pembersihan (`SettingsCleaningView`):**
- Tindakan Default: Pindahkan ke Tong Sampah / Karantina (Folder Aman) / Hapus Permanen (radio group)
- Otomatisasi: Toggle "Hapus file Karantina otomatis setelah 30 hari"

**Tab Pengecualian (`SettingsWhitelistView`):**
- Daftar path folder yang dikecualikan dari semua pemindaian
- Tombol tambah folder via `NSOpenPanel`
- Tombol hapus per path

**Tab Lanjutan (`SettingsAdvancedView`):**
- Tombol "Reset Aplikasi (Ulangi Onboarding)" — menghapus semua data tersimpan + menutup jendela settings otomatis

### 14. 🧱 Komponen UI Bersama

**`PreviewSavingsBar`** — Bottom bar yang muncul di Smart Scan, Duplicates, dan Large Files:
- Menampilkan "Terpilih: [ukuran]"
- Menu dropdown "Bersihkan..." dengan 3 opsi: Trash / Karantina Sementara / Hapus Permanen
- Disabled jika tidak ada file yang dipilih

**`SidebarView`** — Sidebar navigasi utama:
- Circular gauge pemakaian disk (terpakai/total)
- Link navigasi ke semua 8 modul + Daily Report (conditional, hanya muncul malam hari)
- Menampilkan info disk yang dipilih

**`ItemListView`** — List generik untuk hasil scan:
- Toggle seleksi per item (disabled untuk item `locked`)
- Ikon folder/file + nama + path
- Badge risiko berwarna (capsule shape)
- Tombol "Reveal in Finder"

### 15. 🔒 Sistem Keamanan (`MacOSRuleEngine`)
Mesin aturan yang melindungi file sistem dari penghapusan:

**Path yang dikunci (tidak bisa dihapus):**
- `/System`, `/usr/bin`, `/usr/sbin`, `/sbin`, `/bin`
- `/Library/Apple`, `/Library/SystemExtensions`
- `/private/var/db`

**Evaluasi per file:** Setiap URL dievaluasi dan dikembalikan sebagai tuple `(RiskLevel, CleanupCategory, skipDescendants)`. File dengan `riskLevel == .locked` tidak ditampilkan di UI dan sub-foldernya di-skip untuk performa.

---

## Fitur Infrastruktur

### Caching (`ScanCacheManager`)
Semua hasil scan disimpan di memori agar pemindaian ulang bisa instan:
- `smartScanCache: [ScannedItem]`
- `duplicatesCache: [DuplicateGroup]`
- `largeFilesCache: [ScannedItem]`
- `uninstallerCache: [AppUninstallItem]`
- `organizerCache: [FolderOrganizerItem]` + `organizerLastURL`
- Method `clearAll()` untuk reset

### Statistik Penghematan
- `dailySavedBytes` (reset setiap jam 06:00 pagi)
- `totalSavedBytes` (akumulasi selamanya, tersimpan di `UserDefaults`)
- Setiap pembersihan yang berhasil memanggil `DailyReportManager.shared.addSavings(bytes)`

### Global State (`GlobalAppState`)
- `isAnyScanning: Bool` — flag yang diobservasi oleh sidebar. Saat `true`, sidebar navigation links di-disable untuk mencegah navigasi saat scanning berlangsung

---

## Tujuan Dokumen Ini
Dokumen ini dibuat sebagai rangkuman teknis proyek **Shed** yang lengkap dan akurat (diverifikasi langsung dari source code) agar AI/ChatGPT dapat:
1. Memahami konteks dan arsitektur proyek secara menyeluruh
2. Memberikan **saran fitur baru** yang relevan, tidak duplikat, dan logis secara teknis
3. Menghindari saran fitur yang sudah ada atau bertabrakan dengan arsitektur yang sudah dibangun
