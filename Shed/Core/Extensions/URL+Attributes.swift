// Copyright (c) 2026 Kharis Destian Maulana. All rights reserved.
import Foundation

extension URL {
    var fileSize: Int64 {
        do {
            let resourceValues = try self.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            return Int64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileSize ?? 0)
        } catch {
            return 0
        }
    }
    
    var lastModifiedDate: Date? {
        do {
            let resourceValues = try self.resourceValues(forKeys: [.contentModificationDateKey])
            return resourceValues.contentModificationDate
        } catch {
            return nil
        }
    }
    
    var isDirectory: Bool {
        do {
            let resourceValues = try self.resourceValues(forKeys: [.isDirectoryKey])
            return resourceValues.isDirectory ?? false
        } catch {
            return false
        }
    }
}

extension Int64 {
    private static let sizeFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        f.countStyle = .file
        return f
    }()
    
    var formattedSize: String {
        return Self.sizeFormatter.string(fromByteCount: self)
    }
}
