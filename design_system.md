# design_system.md - macOS Native HIG & Visual Tokens

## 1. Prinsip Desain
* Native macOS Big Sur/Monterey/Sonoma Aesthetic: Menggunakan gaya jendela modern dengan sidebar tembus pandang (vibrancy material), SF Symbols, dan kontrol native.
* High Semantic Contrast: Status keamanan berkas dapat dibedakan seketika lewat warna aksen semantik yang tegas.

---

## 2. Palet Warna & Visual Tokens

extension Color {
    // Semantic Status Indicators
    static let statusSafe = Color.green        // #34C759 - Otomatis tercentang
    static let statusReview = Color.orange     // #FF9500 - Perlu review manual
    static let statusLocked = Color.red        // #FF3B30 - Terproteksi, centang mati
    
    // Background Surface Highlights
    static let badgeSafeBg = Color.green.opacity(0.15)
    static let badgeReviewBg = Color.orange.opacity(0.15)
    static let badgeLockedBg = Color.red.opacity(0.15)
}

---

## 3. Komponen Utama

### A. NavigationSplitView Layout
* Sidebar Column (Width: min 220px, ideal 260px):
  * Ringkasan kapasitas storage (circular gauge atau bar chart native).
  * Filter cepat: Semua Temuan, Aman Saja, Perlu Review, Peta Visual (Treemap).
  * Tombol aksi pemindaian: Mulai Pindai.
* Detail / Workspace Column:
  * Header tabel dengan indikator sortir (Ukuran, Nama, Tingkat Risiko).
  * List hierarkis dengan checkbox seleksi native macOS.

### B. Preview Savings Bar (Docked Bottom Bar)
* Menempel di dasar jendela detail dengan efek material blur (.background(.bar)).
* Sisi Kiri:
  * Teks tebal ukuran terpilih: Terpilih: 18.4 GB
  * Teks status ruang: Ruang disk bebas akan menjadi 64.2 GB
* Sisi Kanan:
  * Tombol eksekusi utama: Pindahkan ke Trash (18.4 GB) dengan tint warna hijau (.tint(.statusSafe)).

### C. Status Badges
* Aman: Kapsul dengan latar hijau muda transparan, teks hijau, ikon SF Symbol checkmark.shield.fill.
* Perlu Review: Kapsul dengan latar oranye muda transparan, teks oranye, ikon SF Symbol exclamationmark.triangle.fill.
* Terproteksi: Kapsul dengan latar merah muda transparan, teks merah, ikon SF Symbol lock.fill.
