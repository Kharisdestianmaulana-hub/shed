// Copyright (c) 2026 Kharis Destian Maulana. All rights reserved.
import Foundation

actor LargeFilesActor {
    func startScan() -> AsyncStream<CrawlerEvent> {
        AsyncStream { continuation in
            Task {
                var batch: [ScannedItem] = []
                var scannedCount = 0
                let fileManager = FileManager.default
                let home = fileManager.homeDirectoryForCurrentUser
                
                let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
                // Skips hidden files so it doesn't scan Library or deep system files
                guard let enumerator = fileManager.enumerator(at: home, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
                    continuation.finish()
                    return
                }
                
                let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
                
                for case let fileURL as URL in enumerator {
                    scannedCount += 1
                    
                    if !fileURL.isDirectory {
                        let size = fileURL.fileSize
                        let modified = fileURL.lastModifiedDate ?? Date()
                        let ext = fileURL.pathExtension.lowercased()
                        
                        var category: CleanupCategory?
                        if size > 1_000_000_000 {
                            category = .largeFiles
                        } else if size > 100_000_000 && modified < oneYearAgo {
                            category = .oldFiles
                        } else if (ext == "dmg" || ext == "pkg" || ext == "iso") && size > 50_000_000 {
                            category = .installers
                        }
                        
                        if let cat = category {
                            let item = ScannedItem(url: fileURL, size: size, category: cat, riskLevel: .review, isDirectory: false)
                            batch.append(item)
                        }
                    }
                    
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
}
