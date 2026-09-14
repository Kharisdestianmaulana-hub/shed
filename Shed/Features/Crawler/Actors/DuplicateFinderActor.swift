import Foundation
import CryptoKit

struct DuplicateGroup: Identifiable {
    let id = UUID()
    let size: Int64
    let hash: String
    var files: [URL]
}

actor DuplicateFinderActor {
    func startScan() -> [DuplicateGroup] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let targetDirs = [
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Desktop")
        ]
        
        var sizeDict: [Int64: [URL]] = [:]
        let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
        
        for dir in targetDirs {
            guard let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            
            for case let fileURL as URL in enumerator {
                if fileURL.isDirectory { continue }
                let size = fileURL.fileSize
                // Hanya periksa file di atas 10KB agar tidak membuang waktu memproses ribuan file teks kecil
                if size > 10_000 {
                    sizeDict[size, default: []].append(fileURL)
                }
            }
        }
        
        let potentialDuplicates = sizeDict.filter { $0.value.count > 1 }
        var finalGroups: [DuplicateGroup] = []
        
        for (size, urls) in potentialDuplicates {
            var hashDict: [String: [URL]] = [:]
            for url in urls {
                if let hash = hashFile(url: url) {
                    hashDict[hash, default: []].append(url)
                }
            }
            
            for (hash, identicalUrls) in hashDict where identicalUrls.count > 1 {
                finalGroups.append(DuplicateGroup(size: size, hash: hash, files: identicalUrls))
            }
        }
        
        return finalGroups.sorted { $0.size > $1.size }
    }
    
    private func hashFile(url: URL) -> String? {
        do {
            var hasher = SHA256()
            let fileHandle = try FileHandle(forReadingFrom: url)
            defer { try? fileHandle.close() }
            
            while let chunk = try fileHandle.read(upToCount: 1024 * 1024 * 4), !chunk.isEmpty { // 4MB chunks
                hasher.update(data: chunk)
            }
            let digest = hasher.finalize()
            return digest.compactMap { String(format: "%02x", $0) }.joined()
        } catch {
            return nil
        }
    }
}
