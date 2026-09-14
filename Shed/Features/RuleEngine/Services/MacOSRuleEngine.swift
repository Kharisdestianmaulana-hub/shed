// Copyright (c) 2026 Kharis Destian Maulana. All rights reserved.
import Foundation

struct MacOSRuleEngine {
    static let lockedPaths = [
        "/System",
        "/usr/bin",
        "/usr/sbin",
        "/sbin",
        "/bin",
        "/Library/Apple",
        "/Library/SystemExtensions",
        "/private/var/db"
    ]
    
    static func evaluate(url: URL) -> (RiskLevel, CleanupCategory, Bool) {
        let path = url.path
        
        // 1. Check Locked Paths
        for locked in lockedPaths {
            if path == locked || path.hasPrefix(locked + "/") {
                return (.locked, .protectedSystem, true) // Should skip descendants
            }
        }
        
        // 2. Check Safe Paths (Developer Artifacts & Caches)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        
        let name = url.lastPathComponent
        if name == "DerivedData" || 
           name == "node_modules" || 
           name == ".build" ||
           name == ".dart_tool" {
            return (.safe, .developerArtifacts, true) // Skip descendants for performance
        }
        
        let cachesPrefix = "\(home)/Library/Caches/"
        if path.hasPrefix(cachesPrefix) {
            let relativePath = path.dropFirst(cachesPrefix.count)
            if !relativePath.contains("/") {
                return (.safe, .userCaches, true)
            }
        }
        
        let logsPrefix = "\(home)/Library/Logs/"
        if path.hasPrefix(logsPrefix) {
            let relativePath = path.dropFirst(logsPrefix.count)
            if !relativePath.contains("/") {
                return (.safe, .systemLogs, true)
            }
        }
        
        // 3. Check Review Paths
        let ext = url.pathExtension.lowercased()
        if ext == "dmg" || ext == "pkg" || ext == "iso" {
            return (.review, .installers, false)
        }
        
        // Large & Old Files
        let size = url.fileSize
        let modified = url.lastModifiedDate ?? Date()
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        
        if size > 1_000_000_000 {
            return (.review, .largeFiles, false)
        }
        
        if size > 100_000_000 && modified < oneYearAgo {
            return (.review, .oldFiles, false)
        }
        
        return (.review, .uncategorized, false)
    }
}
