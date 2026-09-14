# architecture.md - Shed macOS Architecture

## 1. Struktur Folder Xcode (Modular Native)

Shed/
├── App/
│   ├── ShedApp.swift               # Entry point SwiftUI App lifecycle
│   └── AppDelegate.swift           # Menu bar, window lifecycle, & termination hooks
├── Core/
│   ├── Enums/
│   │   ├── RiskLevel.swift         # Safe, Review, Locked
│   │   └── CleanupCategory.swift   # Caches, DevArtifacts, Installers, System
│   ├── Extensions/
│   │   ├── URL+Attributes.swift    # Helper alokasi ukuran disk & metadata tanggal
│   │   └── Int64+ByteFormatter.swift # Formatter ukuran disk format macOS
│   └── Permissions/
│       └── FullDiskAccessHelper.swift # Helper deteksi hak akses TCC/FDA
├── Features/
│   ├── Crawler/
│   │   ├── Actors/StorageCrawlerActor.swift # Background I/O traversal
│   │   └── Models/ScannedItem.swift         # Struct entitas representasi file/folder
│   ├── RuleEngine/
│   │   └── Services/MacOSRuleEngine.swift   # Evaluator pola path & metadata
│   ├── Cleaner/
│   │   └── Services/PurgeService.swift      # Eksekusi trashItem & isolasi karantina
│   ├── Whitelist/
│   │   └── Services/WhitelistStore.swift    # Persistent ignore-list via UserDefaults/JSON
│   └── VisualMap/
│       ├── Models/TreemapNode.swift         # Model layout hierarkis
│       └── Views/TreemapCanvasView.swift    # Kanvas SwiftUI untuk rendering Treemap
└── Views/
    ├── MainSplitView.swift         # Layout NavigationSplitView macOS
    ├── Sidebar/
    │   ├── StorageGaugeView.swift  # Visualisasi kapasitas disk global
    │   └── CategoryNavList.swift   # Filter kategori
    ├── Workspace/
    │   ├── ItemRowView.swift       # Baris item dengan toggle centang & badge
    │   └── ItemListView.swift      # List / Accordion grup berkas
    └── Components/
        ├── PreviewSavingsBar.swift # Action bar bawah dengan kalkulasi live
        └── FDAGuideModal.swift     # Pop-up panduan Full Disk Access

---

## 2. Concurrency Model (Swift Concurrency)

Pemindaian berjalan secara terisolasi menggunakan actor untuk mencegah data race dan menjaga UI thread tetap responsif:

[Main UI (SwiftUI View)]
      │
      │ 1. startScan(targetURL)
      ▼
[StorageCrawlerActor] (Background Thread)
      │
      │── 2. FileManager.default.enumerator(...)
      │── 3. URLResourceValues (.totalFileAllocatedSizeKey, .contentModificationDateKey)
      │── 4. WhitelistStore.isIgnored(url) -> Skip
      │── 5. MacOSRuleEngine.evaluate(url) -> RiskLevel
      │── 6. Batching: Akumulasi 50 items atau interval 100ms
      │
      ▼ (Yield via AsyncStream atau @MainActor Callback)
[AppState / ViewModel] ──> Updates @Published items ──> [SwiftUI List & Treemap]

---

## 3. Eksekusi Penghapusan Aman

* **Primary Method:** Memanfaatkan native API AppKit/Foundation:
  FileManager.default.trashItem(at: url, resultingItemURL: nil)
  Metode ini memindahkan berkas langsung ke ~/.Trash, memungkinkan user melakukan Put Back jika terjadi kesalahan.
* **Permanent Purge:** Dijalankan hanya jika user secara eksplisit memilih opsi hapus instan lewat konfirmasi modal sekunder.
