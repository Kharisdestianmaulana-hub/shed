import SwiftUI

struct StorageGaugeView: View {
    let totalSize: Int64
    
    var body: some View {
        VStack {
            Text("Total Ditemukan")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(totalSize.formattedSize)
                .font(.title)
                .bold()
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}
