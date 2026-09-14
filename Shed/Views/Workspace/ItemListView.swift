// Copyright (c) 2026 Kharis Destian Maulana. All rights reserved.
import SwiftUI

struct ItemListView: View {
    @Binding var items: [ScannedItem]
    
    var body: some View {
        List($items) { $item in
            HStack {
                Toggle("", isOn: $item.isSelected)
                    .disabled(item.riskLevel == .locked)
                
                Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading) {
                    Text(item.name).font(.headline)
                    Text(item.url.path).font(.caption).foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(item.size.formattedSize)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(item.riskLevel.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(item.riskLevel.badgeBackground)
                    .foregroundColor(item.riskLevel.color)
                    .clipShape(Capsule())
                
                Button(action: {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                }) {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .foregroundColor(.blue)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
    }
}
