// Copyright (c) 2026 Kharis Destian Maulana. All rights reserved.
import Foundation

enum PurgeAction {
    case trash
    case quarantine
    case permanent
}

struct QuarantineMetadata: Codable, Identifiable {
    var id: UUID
    var originalPath: String
    var quarantinedPath: String
    var fileName: String
    var size: Int64
    var quarantinedAt: Date
    var isSelected: Bool = false
    
    enum CodingKeys: String, CodingKey {
        case id, originalPath, quarantinedPath, fileName, size, quarantinedAt
    }
}

class QuarantineManager {
    static let shared = QuarantineManager()
    
    private let fileManager = FileManager.default
    private var metadataURL: URL {
        let defaultAppSupport = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let appSupport = (fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? defaultAppSupport).appendingPathComponent("Shed")
        if !fileManager.fileExists(atPath: appSupport.path) {
            try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }
        return appSupport.appendingPathComponent("quarantine_metadata.json")
    }
    
    var quarantineDir: URL {
        let defaultDocs = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        let dir = (fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? defaultDocs).appendingPathComponent("Shed_Karantina")
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    func getQuarantinedItems() -> [QuarantineMetadata] {
        guard let data = try? Data(contentsOf: metadataURL) else { return [] }
        return (try? JSONDecoder().decode([QuarantineMetadata].self, from: data)) ?? []
    }
    
    private func saveItems(_ items: [QuarantineMetadata]) {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: metadataURL)
        }
    }
    
    func addItems(_ newItems: [QuarantineMetadata]) {
        var items = getQuarantinedItems()
        items.append(contentsOf: newItems)
        saveItems(items)
    }
    
    func autoCleanup() {
        if !UserDefaults.standard.bool(forKey: "autoDeleteQuarantine") { return }
        
        let items = getQuarantinedItems()
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
        var remainingItems: [QuarantineMetadata] = []
        for item in items {
            if item.quarantinedAt < thirtyDaysAgo {
                try? fileManager.removeItem(atPath: item.quarantinedPath)
                // We could add savings here, but it's an automatic background process.
            } else {
                remainingItems.append(item)
            }
        }
        saveItems(remainingItems)
    }
    
    func restoreItem(_ item: QuarantineMetadata) throws {
        let dest = URL(fileURLWithPath: item.originalPath)
        let dir = dest.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try fileManager.moveItem(atPath: item.quarantinedPath, toPath: item.originalPath)
        
        var items = getQuarantinedItems()
        items.removeAll { $0.id == item.id }
        saveItems(items)
    }
    
    func destroyItem(_ item: QuarantineMetadata) throws {
        if fileManager.fileExists(atPath: item.quarantinedPath) {
            try fileManager.removeItem(atPath: item.quarantinedPath)
        }
        var items = getQuarantinedItems()
        items.removeAll { $0.id == item.id }
        saveItems(items)
    }
}

struct PurgeService {
    static func execute(_ action: PurgeAction, items: [ScannedItem]) async throws {
        let selected = items.filter { $0.isSelected }
        let fileManager = FileManager.default
        
        switch action {
        case .trash:
            for item in selected {
                try fileManager.trashItem(at: item.url, resultingItemURL: nil)
            }
        case .quarantine:
            var quarantinedMetadata: [QuarantineMetadata] = []
            let qManager = QuarantineManager.shared
            
            defer {
                if !quarantinedMetadata.isEmpty {
                    qManager.addItems(quarantinedMetadata)
                }
            }
            
            for item in selected {
                let dest = qManager.quarantineDir.appendingPathComponent(item.url.lastPathComponent)
                let finalDest = fileManager.fileExists(atPath: dest.path) ? qManager.quarantineDir.appendingPathComponent(UUID().uuidString + "_" + item.url.lastPathComponent) : dest
                
                try fileManager.moveItem(at: item.url, to: finalDest)
                
                let meta = QuarantineMetadata(
                    id: UUID(),
                    originalPath: item.url.path,
                    quarantinedPath: finalDest.path,
                    fileName: item.name,
                    size: Int64(item.size),
                    quarantinedAt: Date()
                )
                quarantinedMetadata.append(meta)
            }
            
        case .permanent:
            for item in selected {
                try fileManager.removeItem(at: item.url)
            }
        }
    }
}
