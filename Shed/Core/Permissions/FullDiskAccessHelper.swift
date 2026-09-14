import Foundation
import AppKit

struct FullDiskAccessHelper {
    static var hasFullDiskAccess: Bool {
        let tccPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db").path
        return FileManager.default.isReadableFile(atPath: tccPath)
    }
    
    static func openPrivacySettings() {
        let urlString: String
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 13 {
            urlString = "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension?Privacy_AllFiles"
        } else {
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        }
        if let url = URL(string: urlString) {
            DispatchQueue.main.async {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
