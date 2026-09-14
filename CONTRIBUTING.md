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

---

# Panduan Berkontribusi untuk Shed (Bahasa Indonesia)

Pertama-tama, terima kasih telah mempertimbangkan untuk berkontribusi ke Shed. Orang-orang seperti Anda lah yang membuat dunia _open source_ (dan *source-available*) menjadi luar biasa.

Shed adalah aplikasi utilitas macOS yang dibangun sepenuhnya (*natively*) menggunakan SwiftUI. Tujuan kami adalah menyediakan alat manajemen penyimpanan yang sangat cepat, transparan, dan aman. Kami menyambut kontribusi yang sejalan dengan visi ini, baik itu berupa perbaikan *bug*, penambahan fitur baru, atau peningkatan dokumentasi.

## Kode Etik

Dengan berpartisipasi dalam proyek ini, Anda diharapkan menjunjung tinggi lingkungan yang ramah dan profesional. Harap bersikap hormat kepada kontributor lain. Pelecehan, bahasa diskriminatif, atau perilaku tidak profesional tidak akan ditoleransi.

## Bagaimana Saya Bisa Berkontribusi?

### Melaporkan Bug
Jika Anda menemukan *bug*, silakan buka *Issue* (Masalah) di repositori GitHub ini. Saat melaporkan *bug*, harap sertakan:
- Judul yang jelas dan deskriptif.
- Versi Shed dan versi macOS yang Anda gunakan.
- Langkah-langkah pasti untuk mereproduksi masalah tersebut.
- Perilaku yang diharapkan (*expected behavior*) vs perilaku aktual (*actual behavior*).
- Log atau laporan *crash* yang relevan.

### Menyarankan Peningkatan
Kami selalu terbuka untuk ide-ide baru. Jika Anda ingin mengusulkan fitur baru:
- Buka *Issue* yang dikategorikan sebagai *enhancement* (peningkatan).
- Jelaskan fitur tersebut secara detail dan jelaskan masalah spesifik yang diselesaikannya.
- Jika memungkinkan, sediakan desain (*mockup*) atau referensi ke pola desain *native* macOS yang cocok dengan antarmuka SwiftUI.

### Pull Requests (Mengirim Kode)
Sudah siap untuk menulis kode? Bagus! Silakan ikuti alur kerja berikut:

1. **Fork Repositori**: Buat _fork_ dari repositori `shed` ke akun GitHub Anda sendiri.
2. **Klon (Clone)**: Kloning repositori hasil *fork* ke komputer lokal Anda (`git clone https://github.com/YOUR-USERNAME/shed.git`).
3. **Buat Branch**: Buat _branch_ baru untuk fitur atau perbaikan *bug* Anda (`git checkout -b feature/nama-fitur-anda`).
4. **Pengembangan (Develop)**: Tulis kode Anda. Pastikan Anda mematuhi pedoman arsitektur yang tercantum di bawah ini.
5. **Uji Coba (Test)**: Bangun (*build*) dan uji aplikasi secara lokal. Pastikan tidak ada fitur lama yang rusak.
6. **Commit**: Lakukan *commit* perubahan Anda dengan pesan yang jelas dan deskriptif.
7. **Push**: *Push* *branch* Anda ke repositori *fork* milik Anda (`git push origin feature/nama-fitur-anda`).
8. **Kirim Pull Request**: Buka _Pull Request_ (PR) yang ditujukan ke branch `main` dari repositori resmi Shed. Jelaskan perubahan Anda secara menyeluruh dalam deskripsi PR.

## Pedoman Arsitektur

Untuk menjaga performa dan keamanan Shed, harap patuhi pedoman teknis berikut saat menyumbangkan kode:

- **Wajib SwiftUI**: Semua antarmuka pengguna harus dibangun menggunakan SwiftUI. Hindari penggunaan AppKit (NSView/NSViewController) kembali, kecuali jika benar-benar diperlukan untuk fitur yang tidak dapat ditangani SwiftUI secara bawaan.
- **Pola MVVM-A**: Kami menggunakan arsitektur *Model-View-ViewModel-Actor*. *View* hanya menangani *rendering* UI. *ViewModel* mengelola status (_state_) dan memformat data. Beban kerja yang berat, terutama pemindaian sistem *file*, wajib didelegasikan ke *Actors*.
- **Konkurensi**: Jangan memblokir *Main Thread*! Proses I/O pada *disk*, pencacahan *file*, atau komputasi berat apa pun harus dilakukan secara asinkron menggunakan struktur `async/await` dan `Task` di Swift.
- **Utamakan Keselamatan (Safety First)**: Karena Shed berkaitan dengan penghapusan *file*, setiap tindakan destruktif harus menyertakan dialog konfirmasi (*alert*) kepada pengguna. Hindari penggunaan *force-unwrap optionals* (`!`); tangani kesalahan secara anggun (_graceful handling_) untuk mencegah terjadinya *crash*.

## Pengaturan Lingkungan Pengembangan (Development Setup)

1. Anda harus menginstal Xcode 14 atau versi yang lebih baru.
2. Buka `Shed.xcodeproj`.
3. Atur skema (*scheme*) yang aktif ke **Shed** dan destinasi ke **My Mac**.
4. Tekan `Cmd + R` untuk mengompilasi dan menjalankan aplikasi.

Jika perubahan yang Anda buat melibatkan penghapusan *file* atau modifikasi tingkat sistem, Anda mungkin perlu memberikan Akses Disk Penuh (*Full Disk Access*) untuk aplikasi Shed yang Anda kompilasi secara lokal tersebut di Pengaturan Sistem macOS (System Settings > Privacy & Security) selama masa pengujian.

## Perjanjian Kontributor (Lisensi)

Shed beroperasi di bawah Lisensi Kustom yang bersumber terbuka (*Source-Available License*). Dengan mengirimkan *Pull Request* atau menyumbangkan kode ke repositori ini, Anda secara eksplisit setuju bahwa:
1. Anda memberikan lisensi yang abadi, di seluruh dunia, non-eksklusif, bebas royalti kepada pemilik repositori untuk menggunakan, memodifikasi, dan mendistribusikan kontribusi Anda.
2. Anda memahami bahwa kode sumber (*source code*) Shed sama sekali **tidak boleh** digunakan oleh Anda atau siapa pun untuk membuat aplikasi turunan atau produk pesaing di luar repositori resmi ini.
