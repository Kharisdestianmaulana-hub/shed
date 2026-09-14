import SwiftUI

struct PreviewSavingsBar: View {
    let totalSize: Int64
    let action: (PurgeAction) -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                HStack(spacing: 4) {
                    Text("Terpilih:")
                    Text(totalSize.formattedSize)
                }
                    .font(.headline)
            }
            Spacer()
            
            Menu {
                Button(action: { action(.trash) }) {
                    Label("Pindahkan ke Trash", systemImage: "trash.fill")
                }
                Button(action: { action(.quarantine) }) {
                    Label("Karantina Sementara", systemImage: "archivebox.fill")
                }
                Button(role: .destructive, action: { action(.permanent) }) {
                    Label("Hapus Permanen", systemImage: "trash.slash.fill")
                }
            } label: {
                Text("Bersihkan...")
                    .padding(.horizontal, 16)
            }
            .menuStyle(BorderlessButtonMenuStyle())
            .fixedSize()
            .disabled(totalSize == 0)
        }
        .padding()
        .background(.regularMaterial)
    }
}
