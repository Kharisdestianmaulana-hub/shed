import Foundation
import SwiftUI

enum RiskLevel: String, CaseIterable, Codable, Comparable {
    case safe = "Aman"
    case review = "Perlu Review"
    case locked = "Terproteksi Sistem"
    
    var color: Color {
        switch self {
        case .safe: return .green
        case .review: return .orange
        case .locked: return .red
        }
    }
    
    var badgeBackground: Color {
        self.color.opacity(0.15)
    }
    
    var iconName: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .review: return "exclamationmark.triangle.fill"
        case .locked: return "lock.fill"
        }
    }
    
    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        let order: [RiskLevel: Int] = [.safe: 0, .review: 1, .locked: 2]
        return order[lhs]! < order[rhs]!
    }
}
