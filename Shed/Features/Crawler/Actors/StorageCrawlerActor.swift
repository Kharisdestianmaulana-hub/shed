// Copyright (c) 2026 Kharis Destian Maulana. All rights reserved.
import Foundation

enum CrawlerEvent {
    case batch([ScannedItem])
    case progress(scannedCount: Int, currentPath: String)
}

actor StorageCrawlerActor {
    func startScan(targetURL: URL) -> AsyncStream<CrawlerEvent> {
        AsyncStream { continuation in
            Task {
                var batch: [ScannedItem] = []
                var scannedCount = 0
                let fileManager = FileManager.default
                let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey, .isDirectoryKey, .contentModificationDateKey]
                
                guard let enumerator = fileManager.enumerator(at: targetURL, includingPropertiesForKeys: keys, options: []) else {
                    continuation.finish()
                    return
                }
                
                let whitelistString = UserDefaults.standard.string(forKey: "whitelistPaths") ?? ""
                let whitelistPaths = whitelistString.components(separatedBy: "|").filter { !$0.isEmpty }
                
                for case let fileURL as URL in enumerator {
                    if whitelistPaths.contains(where: { fileURL.path.hasPrefix($0) }) {
                        enumerator.skipDescendants()
                        continue
                    }
                    
                    scannedCount += 1
                    
                    let (riskLevel, category, skipDescendants) = MacOSRuleEngine.evaluate(url: fileURL)
                    
                    if riskLevel == .locked {
                        if skipDescendants { enumerator.skipDescendants() }
                        continue
                    }
                    
                    if skipDescendants {
                        enumerator.skipDescendants()
                    }
                    
                    let isDir = fileURL.isDirectory
                    
                    if skipDescendants && riskLevel == .safe {
                        let totalSize = calculateTotalSize(of: fileURL)
                        let item = ScannedItem(url: fileURL, size: totalSize, category: category, riskLevel: riskLevel, isDirectory: true)
                        batch.append(item)
                    } else if !isDir && riskLevel == .review {
                        if category != .uncategorized {
                            let item = ScannedItem(url: fileURL, size: fileURL.fileSize, category: category, riskLevel: riskLevel, isDirectory: false)
                            batch.append(item)
                        }
                    } else if riskLevel == .safe && !isDir {
                         let item = ScannedItem(url: fileURL, size: fileURL.fileSize, category: category, riskLevel: riskLevel, isDirectory: false)
                         batch.append(item)
                    }
                    
                    // Flush progress & item ke UI setiap 100 file yang dicek
                    if scannedCount % 100 == 0 {
                        continuation.yield(.progress(scannedCount: scannedCount, currentPath: fileURL.path))
                        if !batch.isEmpty {
                            continuation.yield(.batch(batch))
                            batch = []
                            await Task.yield()
                        }
                    }
                }
                
                if !batch.isEmpty {
                    continuation.yield(.batch(batch))
                }
                
                continuation.finish()
            }
        }
    }
    
    private func calculateTotalSize(of url: URL) -> Int64 {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: keys) else {
            return url.fileSize
        }
        
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += fileURL.fileSize
        }
        return total
    }
}

import SwiftUI

struct StorageNode: Identifiable, Hashable {
    let id: UUID
    let name: String
    let url: URL?
    var size: Int64
    var isDirectory: Bool
    var children: [StorageNode]? // nil means not fetched yet
    var iconName: String
    var color: Color
}

actor FolderSizeScannerActor {
    func calculateSize(for url: URL) async -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        
        if !isDir.boolValue {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int64 {
                return size
            }
            return 0
        }
        
        let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        var count = 0
        for case let fileURL as URL in enumerator {
            if let rv = try? fileURL.resourceValues(forKeys: Set(keys)), rv.isDirectory != true {
                totalSize += Int64(rv.fileSize ?? 0)
            }
            count += 1
            if count % 1000 == 0 {
                // Yield to allow UI updates to process and other Tasks to breathe
                await Task.yield()
            }
        }
        return totalSize
    }
    
    func scanChildren(of urls: [URL]) async -> [StorageNode] {
        var results: [StorageNode] = []
        let fm = FileManager.default
        
        for baseURL in urls {
            guard let children = try? fm.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
                continue
            }
            
            for childURL in children {
                let size = await calculateSize(for: childURL)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: childURL.path, isDirectory: &isDir)
                
                let isPackage = childURL.pathExtension == "app" || childURL.pathExtension == "bundle" || childURL.pathExtension == "plugin"
                let actualIsDir = isDir.boolValue && !isPackage
                
                let node = StorageNode(
                    id: UUID(),
                    name: childURL.lastPathComponent,
                    url: childURL,
                    size: size,
                    isDirectory: actualIsDir,
                    children: nil,
                    iconName: isPackage ? "app.fill" : (actualIsDir ? "folder.fill" : "doc.fill"),
                    color: .blue
                )
                
                results.append(node)
            }
        }
        
        return results.sorted { $0.size > $1.size }
    }
}
