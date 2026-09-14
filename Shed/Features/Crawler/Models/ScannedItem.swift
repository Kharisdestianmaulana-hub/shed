// Copyright (c) 2026 Kharis Destian Maulana. All rights reserved.
import Foundation

struct ScannedItem: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let name: String
    let size: Int64
    let category: CleanupCategory
    let riskLevel: RiskLevel
    let isDirectory: Bool
    var isSelected: Bool
    
    init(url: URL, size: Int64, category: CleanupCategory, riskLevel: RiskLevel, isDirectory: Bool) {
        self.id = UUID()
        self.url = url
        self.name = url.lastPathComponent
        self.size = size
        self.category = category
        self.riskLevel = riskLevel
        self.isDirectory = isDirectory
        // Default selection based on risk level
        self.isSelected = riskLevel == .safe
    }
}
