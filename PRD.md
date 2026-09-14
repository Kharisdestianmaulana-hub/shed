# Product Requirements Document (PRD) - Shed for macOS

## 1. Ringkasan Produk
* **Nama Aplikasi:** Shed
* **Platform Target:** macOS 11.0 (Big Sur) hingga versi terbaru (Universal Binary: Apple Silicon & Intel)
* **Teknologi Utama:** Swift, SwiftUI, Swift Concurrency (Actors & AsyncStream), Foundation (FileManager)
* **Tujuan:** Aplikasi utilitas pembersih dan penganalisis penyimpanan disk native macOS yang cepat, transparan, dan aman, dengan label risiko visual untuk mencegah salah hapus berkas sistem.

---

## 2. Masalah & Solusi
* **Masalah:** Disk Mac sering penuh oleh cache tersembunyi (Xcode DerivedData, node_modules, cache aplikasi), sementara utilitas bawaan macOS kurang mendalam dan aplikasi pihak ketiga sering kali berbayar mahal atau berjalan lambat (berbasis Electron/Webview).
* **Solusi:** Utilitas native yang memanfaatkan API filesystem tingkat rendah macOS, memvisualisasikan konsumsi disk secara instan, serta memberikan rekomendasi cerdas dengan klasifikasi risiko berbasis warna.

---

## 3. Fitur Utama (MVP Scope)

### A. Deep Storage Crawler & Classification
* Pemindaian direktori pengguna (~) di latar belakang tanpa memblokir thread UI.
* Klasifikasi otomatis ke dalam 3 status risiko:
  * **Safe (Hijau):** Cache pengguna, Xcode DerivedData, build artifacts (node_modules), package cache.
  * **Review (Kuning):** File installer (.dmg, .pkg), file tidur (>500 MB tidak dibuka >6 bulan), duplikat.
  * **Locked (Merah):** Direktori sistem vital yang dilindungi SIP (System Integrity Protection).

### B. Interactive Visual Map (Treemap)
* Representasi visual blok direktori proporsional terhadap ukuran disk.
* Mendukung klik untuk drill-down (zoom in) dan navigasi breadcrumb.

### C. Live Preview Savings Bar
* Menghitung ruang disk yang akan dibebaskan secara dinamis setiap kali pilihan centang diubah sebelum eksekusi dilakukan.

### D. Safe Purge & Trash Integration
* Secara bawaan menggunakan FileManager.default.trashItem agar berkas masuk ke macOS Trash (dapat di-restore sewaktu-waktu).
* Opsi Karantina Terisolasi untuk berkas pengembangan.

### E. Smart Whitelist
* Pengguna dapat mengecualikan direktori proyek atau berkas spesifik agar dilewati selama pemindaian.

---

## 4. Kebutuhan Non-Fungsional & Kepatuhan Sistem
* **Memory Footprint:** Maksimal < 100 MB RAM saat pemindaian intensif 500.000+ berkas.
* **Frame Rate UI:** Menjaga 60/120 FPS (ProMotion) secara konsisten.
* **Privasi & Keamanan:** 
  * App Sandbox: Dinonaktifkan (com.apple.security.app-sandbox = false).
  * Full Disk Access (FDA): Deteksi dan layar edukasi pembukaan izin di System Settings / System Preferences.
