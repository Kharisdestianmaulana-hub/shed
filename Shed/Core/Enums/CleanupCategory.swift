import Foundation

enum CleanupCategory: String, CaseIterable, Codable {
    case userCaches = "Cache Aplikasi"
    case developerArtifacts = "Artefak Pengembang"
    case packageManagers = "Cache Paket Sistem"
    case systemLogs = "Berkas Log"
    case installers = "File Installer & Image"
    case staleFiles = "Berkas Besar Tak Tersentuh"
    case protectedSystem = "Integritas macOS (SIP)"
    // Large & Old Files
    case largeFiles = "Berkas Raksasa (>1GB)"
    case oldFiles = "Berkas Usang (>1 Tahun)"
    case uncategorized = "Lainnya"
}
