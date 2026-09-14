// Menambahkan FilterMode yang hilang
enum FilterMode: String, CaseIterable {
    case all = "Semua"
    case safe = "Aman (Siap Hapus)"
    case review = "Perlu Review"
}
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
        let diskPath = UserDefaults.standard.string(forKey: "selectedDiskPath") ?? "/"
        let targetDirs: [URL]
        
        if diskPath == "/" {
            let home = fileManager.homeDirectoryForCurrentUser
            targetDirs = [
                home.appendingPathComponent("Downloads"),
                home.appendingPathComponent("Documents"),
                home.appendingPathComponent("Desktop")
            ]
        } else {
            targetDirs = [URL(fileURLWithPath: diskPath)]
        }
        
        var sizeDict: [Int64: [URL]] = [:]
        let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
        
        let whitelistString = UserDefaults.standard.string(forKey: "whitelistPaths") ?? ""
        let whitelistPaths = whitelistString.components(separatedBy: "|").filter { !$0.isEmpty }
        
        for dir in targetDirs {
            guard let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            
            for case let fileURL as URL in enumerator {
                if whitelistPaths.contains(where: { fileURL.path.hasPrefix($0) }) {
                    enumerator.skipDescendants()
                    continue
                }
                
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
            // Untuk performa super cepat, kita hash 1 MB pertama dari file
            let fileHandle = try FileHandle(forReadingFrom: url)
            defer { try? fileHandle.close() }
            let data = try fileHandle.read(upToCount: 1024 * 1024) ?? Data()
            let hash = SHA256.hash(data: data)
            return hash.compactMap { String(format: "%02x", $0) }.joined()
        } catch {
            return nil
        }
    }
}
import Foundation

actor LargeFilesActor {
    func startScan() -> AsyncStream<CrawlerEvent> {
        AsyncStream { continuation in
            Task {
                var batch: [ScannedItem] = []
                var scannedCount = 0
                let fileManager = FileManager.default
                let diskPath = UserDefaults.standard.string(forKey: "selectedDiskPath") ?? "/"
                let home = URL(fileURLWithPath: diskPath)
                
                let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
                // Skips hidden files so it doesn't scan Library or deep system files
                guard let enumerator = fileManager.enumerator(at: home, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
                    continuation.finish()
                    return
                }
                
                let whitelistString = UserDefaults.standard.string(forKey: "whitelistPaths") ?? ""
                let whitelistPaths = whitelistString.components(separatedBy: "|").filter { !$0.isEmpty }
                let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
                
                for case let fileURL as URL in enumerator {
                    if whitelistPaths.contains(where: { fileURL.path.hasPrefix($0) }) {
                        enumerator.skipDescendants()
                        continue
                    }
                    
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
                            try? await Task.sleep(nanoseconds: 5_000_000)
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
import SwiftUI
import AppKit

// MARK: - Global App State
class GlobalAppState: ObservableObject {
    @Published var isAnyScanning: Bool = false
}

// MARK: - Scan Cache Manager
class ScanCacheManager {
    static let shared = ScanCacheManager()
    
    var smartScanCache: [ScannedItem] = []
    var duplicatesCache: [DuplicateGroup] = []
    var largeFilesCache: [ScannedItem] = []
    var uninstallerCache: [AppUninstallItem] = []
    var storageAnalyzerCache: [StorageNode] = []
    
    var organizerCache: [FolderOrganizerItem] = []
    var organizerLastURL: URL? = nil
    
    func clearAll() {
        smartScanCache.removeAll()
        duplicatesCache.removeAll()
        largeFilesCache.removeAll()
        uninstallerCache.removeAll()
        organizerCache.removeAll()
        organizerLastURL = nil
    }
}


// MARK: - Navigation Mode
enum NavigationMode {
    case dashboard
    case smartScan
    case storageMap
    case developer
    case duplicates
    case largeFiles
    case uninstaller
    case organizer
    case startup
    case quarantine
    case dailyReport
}

// MARK: - Main Split View
// (Fitur lainnya akan diletakkan di berkas terpisah)
struct MainSplitView: View {
    @State private var selection: NavigationMode? = .dashboard
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    
    @StateObject private var globalState = GlobalAppState()
    
    var body: some View {
        NavigationView {
            SidebarView(selection: $selection)
                .disabled(globalState.isAnyScanning)
            
            detailView
        }
        .navigationTitle("Shed")
        .environmentObject(globalState)
    }
    



    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .smartScan:
            SmartScanView()
        case .storageMap:
            StorageAnalyzerView()
        case .developer:
            DeveloperCleanupView()
        case .duplicates:
            DuplicatesView()
        case .largeFiles:
            LargeFilesView()
        case .uninstaller:
            AppUninstallerView()
        case .quarantine:
            QuarantineVaultView()
        case .organizer:
            FolderOrganizerView()
        case .startup:
            StartupManagerView()
        case .dailyReport:
            DailyReportView(selection: $selection)
        case .dashboard, .none:
            DashboardView(selection: $selection)
        }
    }
}

// MARK: - Sidebar
struct SidebarView: View {
    @Binding var selection: NavigationMode?
    @EnvironmentObject var globalState: GlobalAppState
    
    @State private var totalDiskSpace: Int64 = 0
    @State private var freeDiskSpace: Int64 = 0
    @AppStorage("selectedDiskPath") private var selectedDiskPath: String = "/"
    @StateObject private var dailyManager = DailyReportManager.shared
    
    var body: some View {
        VStack {
            // Gauge is now just showing static disk info since it's global
            let used = totalDiskSpace - freeDiskSpace
            let percentage = totalDiskSpace > 0 ? Double(used) / Double(totalDiskSpace) : 0
            
            VStack {
                ZStack {
                    Circle()
                        .stroke(lineWidth: 12)
                        .opacity(0.3)
                        .foregroundColor(Color.secondary)
                    
                    Circle()
                        .trim(from: 0.0, to: CGFloat(min(percentage, 1.0)))
                        .stroke(style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
                        .foregroundColor(Color.blue)
                        .rotationEffect(Angle(degrees: 270.0))
                    
                    VStack {
                        Text("Terpakai")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(used.formattedSize)
                            .font(.headline)
                            .bold()
                    }
                }
                .frame(width: 120, height: 120)
                .padding()
                
                HStack(spacing: 4) {
                    Text("Total:")
                    Text(totalDiskSpace.formattedSize)
                }
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 20)
            
            List {
                if dailyManager.isReportTime {
                    NavigationLink(destination: DailyReportView(selection: $selection), tag: NavigationMode.dailyReport, selection: $selection) {
                        Label("Laporan Malam Ini", systemImage: "moon.stars.fill")
                            .font(.headline)
                    }
                }
                
                Group {
                    NavigationLink(destination: DashboardView(selection: $selection), tag: NavigationMode.dashboard, selection: $selection) {
                        Label("Dashboard", systemImage: "house.fill")
                    }
                    NavigationLink(destination: StorageAnalyzerView(), tag: NavigationMode.storageMap, selection: $selection) {
                        Label("Storage Analyzer", systemImage: "chart.pie.fill")
                    }
                    NavigationLink(destination: SmartScanView(), tag: NavigationMode.smartScan, selection: $selection) {
                        Label("Pembersih Pintar", systemImage: "wand.and.stars")
                    }
                    NavigationLink(destination: DuplicatesView(), tag: NavigationMode.duplicates, selection: $selection) {
                        Label("Berkas Kembar", systemImage: "doc.on.doc")
                    }
                }
                Group {
                    NavigationLink(destination: DeveloperCleanupView(), tag: NavigationMode.developer, selection: $selection) {
                        Label("Developer Cleanup", systemImage: "terminal.fill")
                    }
                    NavigationLink(destination: LargeFilesView(), tag: NavigationMode.largeFiles, selection: $selection) {
                        Label("Radar Berkas Raksasa", systemImage: "externaldrive.fill")
                    }
                    NavigationLink(destination: AppUninstallerView(), tag: NavigationMode.uninstaller, selection: $selection) {
                        Label("App Uninstaller", systemImage: "trash.square.fill")
                    }
                    NavigationLink(destination: FolderOrganizerView(), tag: NavigationMode.organizer, selection: $selection) {
                        Label("Folder Organizer", systemImage: "folder.badge.gearshape")
                    }
                    NavigationLink(destination: StartupManagerView(), tag: NavigationMode.startup, selection: $selection) {
                        Label("Pengelola Startup", systemImage: "bolt.horizontal.fill")
                    }
                }
            }
            .listStyle(SidebarListStyle())
        }
        .frame(minWidth: 200)
        .onAppear {
            fetchDiskSpace()
        }
        .onChange(of: selectedDiskPath) { _ in
            fetchDiskSpace()
        }
    }
    
    private func fetchDiskSpace() {
        do {
            let path = UserDefaults.standard.string(forKey: "selectedDiskPath") ?? "/"
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: path)
            if let total = attrs[.systemSize] as? NSNumber,
               let free = attrs[.systemFreeSize] as? NSNumber {
                self.totalDiskSpace = total.int64Value
                self.freeDiskSpace = free.int64Value
            }
        } catch {}
    }
}
import SwiftUI
import AppKit

// MARK: - AppViewModel
@MainActor
class AppViewModel: ObservableObject {
    @Published var items: [ScannedItem] = []
    @Published var isScanning: Bool = false
    @Published var scannedCount: Int = 0
    @Published var currentPath: String = ""
    @Published var filterMode: FilterMode = .all
    
    var filteredItems: [ScannedItem] {
        items.filter { item in
            switch filterMode {
            case .all: return true
            case .safe: return item.riskLevel == .safe
            case .review: return item.riskLevel == .review
            }
        }
    }
    
    var totalSelectedSize: Int64 {
        items.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
    }
    
    var totalFoundSize: Int64 {
        items.reduce(0) { $0 + $1.size }
    }
    
    func startScan() {
        items.removeAll()
        isScanning = true
        scannedCount = 0
        currentPath = "Memulai pemindaian..."
        
        let cache = ScanCacheManager.shared.smartScanCache
        if !cache.isEmpty {
            Task {
                let sortedCache = cache.sorted { $0.size > $1.size }
                withAnimation(.spring()) {
                    self.items = sortedCache
                }
                self.isScanning = false
                self.currentPath = "Selesai (dari Cache)"
            }
            return
        }
        
        Task {
            let crawler = StorageCrawlerActor()
            let diskPath = UserDefaults.standard.string(forKey: "selectedDiskPath") ?? "/"
            let homeURL = diskPath == "/" ? FileManager.default.homeDirectoryForCurrentUser : URL(fileURLWithPath: diskPath)
            let stream = await crawler.startScan(targetURL: homeURL)
            
            for await event in stream {
                switch event {
                case .progress(let count, let path):
                    self.scannedCount = count
                    self.currentPath = path
                case .batch(let batch):
                    withAnimation(.spring()) {
                        for item in batch {
                            if let index = self.items.firstIndex(where: { $0.size < item.size }) {
                                self.items.insert(item, at: index)
                            } else {
                                self.items.append(item)
                            }
                        }
                    }
                }
            }
            ScanCacheManager.shared.smartScanCache = self.items
            self.isScanning = false
            self.currentPath = "Selesai"
        }
    }
    
    func purgeSelected(action: PurgeAction) {
        let sizeToPurge = self.totalSelectedSize
        Task {
            do {
                try await PurgeService.execute(action, items: items)
                withAnimation {
                    items.removeAll { $0.isSelected }
                }
                
                DailyReportManager.shared.addSavings(Int64(sizeToPurge))
            } catch {
                print("Error purging: \(error)")
            }
        }
    }
}

// MARK: - SmartScanView
struct SmartScanView: View {
    @StateObject private var viewModel = AppViewModel()
    @EnvironmentObject var globalState: GlobalAppState
    @AppStorage("fileReviewMode") private var fileReviewMode: String = "list"
    
    var body: some View {
        VStack(spacing: 0) {
            // Header actions
            HStack {
                if viewModel.isScanning {
                    VStack(alignment: .leading) {
                        HStack {
                            ProgressView().controlSize(.small)
                            HStack(spacing: 4) {
                                Text("\(viewModel.scannedCount)")
                                Text("file diperiksa")
                            }
                            .font(.subheadline)
                            .foregroundColor(.blue)
                        }
                        Text(viewModel.currentPath)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } else {
                    Text("Siap Memindai Mac Anda")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    viewModel.startScan()
                }) {
                    if viewModel.isScanning {
                        Text("Membatalkan...")
                    } else {
                        Text("Mulai Pindai")
                    }
                }
                .disabled(viewModel.isScanning)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            // Content
            if viewModel.items.isEmpty && !viewModel.isScanning {
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    Text("Pembersih Pintar Siap")
                        .font(.title)
                        .bold()
                    Text("Klik 'Mulai Pindai' di pojok kanan atas untuk mulai mencari.")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                VStack {
                    Picker("Filter", selection: $viewModel.filterMode) {
                        ForEach(FilterMode.allCases, id: \.self) { mode in
                            Text(LocalizedStringKey(mode.rawValue)).tag(mode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding()
                    
                    if fileReviewMode == "swipe" {
                        // Group items by RiskLevel or Category to avoid 10k items
                        let grouped = Dictionary(grouping: viewModel.filteredItems, by: { $0.category })
                        let swipeItems = grouped.map { (category, items) -> SwipeCardItem in
                            let totalSize = items.reduce(0) { $0 + $1.size }
                            
                            return SwipeCardItem(
                                id: category.rawValue,
                                title: "Kategori: \(category.rawValue)",
                                subtitle: "\(items.count) file ditemukan",
                                sizeString: totalSize.formattedSize,
                                categoryString: "Smart Scan",
                                isDirectory: true,
                                fileURL: nil,
                                onSwipeLeft: {
                                    for item in items {
                                        if let idx = viewModel.items.firstIndex(where: { $0.id == item.id }), item.riskLevel != .locked {
                                            viewModel.items[idx].isSelected = true
                                        }
                                    }
                                },
                                onSwipeRight: {
                                    for item in items {
                                        if let idx = viewModel.items.firstIndex(where: { $0.id == item.id }) {
                                            viewModel.items[idx].isSelected = false
                                        }
                                    }
                                }
                            )
                        }
                        SwipeCardContainer(items: swipeItems, isScanning: viewModel.isScanning)
                    } else {
                        List(viewModel.filteredItems) { item in
                            if let index = viewModel.items.firstIndex(where: { $0.id == item.id }) {
                                HStack {
                                    Toggle("", isOn: $viewModel.items[index].isSelected)
                                        .disabled(item.riskLevel == .locked)
                                    
                                    Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                                        .foregroundColor(.secondary)
                                    
                                    VStack(alignment: .leading) {
                                        Text(LocalizedStringKey(item.name)).font(.headline)
                                        Text(item.url.path).font(.caption).foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Text(item.size.formattedSize)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    Text(LocalizedStringKey(item.riskLevel.rawValue))
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
                }
            }
            
            PreviewSavingsBar(totalSize: viewModel.totalSelectedSize, action: { action in
                viewModel.purgeSelected(action: action)
            })
        }
        .onChange(of: viewModel.isScanning) { newValue in
            globalState.isAnyScanning = newValue
        }
    }
}

// MARK: - Mac Health Dashboard

struct HealthRecommendation: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let size: Int64?
    let icon: String
    let color: Color
    let actionLabel: String
    let action: () -> Void
}

@MainActor
class MacHealthViewModel: ObservableObject {
    @Published var healthScore: Int = 100
    @Published var recommendations: [HealthRecommendation] = []
    @Published var isAnalyzing = false
    
    @Published var totalDiskSpace: Int64 = 0
    @Published var freeDiskSpace: Int64 = 0
    @Published var trashSize: Int64 = 0
    @Published var downloadsSize: Int64 = 0
    @Published var xcodeSize: Int64 = 0
    
    var selectionBinding: Binding<NavigationMode?>?
    
    func analyze(selection: Binding<NavigationMode?>) {
        self.selectionBinding = selection
        isAnalyzing = true
        recommendations.removeAll()
        
        Task.detached { [weak self] in
            guard let self = self else { return }
            var score = 100
            var localTotal: Int64 = 0
            var localFree: Int64 = 0
            var localTrash: Int64 = 0
            var localXcode: Int64 = 0
            var localDownloads: Int64 = 0
            var localRecs: [HealthRecommendation] = []
            
            // 1. Disk Space
            if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
               let total = attrs[.systemSize] as? NSNumber,
               let free = attrs[.systemFreeSize] as? NSNumber {
                localTotal = total.int64Value
                localFree = free.int64Value
                
                let freePercentage = Double(localFree) / Double(localTotal)
                if freePercentage < 0.10 {
                    score -= 15
                } else if freePercentage < 0.20 {
                    score -= 5
                }
            }
            
            // 2. FDA Check
            if !FullDiskAccessHelper.hasFullDiskAccess {
                score -= 5
                localRecs.append(HealthRecommendation(
                    title: "Akses Disk Penuh Belum Aktif",
                    description: "Shed tidak bisa memindai file tersembunyi dengan maksimal tanpa izin ini.",
                    size: nil,
                    icon: "exclamationmark.shield.fill",
                    color: .red,
                    actionLabel: "Beri Akses"
                ) {
                    FullDiskAccessHelper.openPrivacySettings()
                })
            }
            
            // 3. Trash Check
            let trashURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
            let tSize = self.calculateFolderSizeFast(url: trashURL)
            localTrash = tSize
            if tSize > 500_000_000 { // 500MB
                score -= 5
                localRecs.append(HealthRecommendation(
                    title: "Kosongkan Tong Sampah",
                    description: "Ada tumpukan file yang sudah dihapus tetapi masih memakan ruang disk.",
                    size: tSize,
                    icon: "trash.fill",
                    color: .orange,
                    actionLabel: "Buka Pembersih"
                ) {
                    Task { @MainActor in selection.wrappedValue = .smartScan }
                })
            }
            
            // 4. Xcode Cache
            let derivedDataURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Developer/Xcode/DerivedData")
            let xSize = self.calculateFolderSizeFast(url: derivedDataURL)
            localXcode = xSize
            if xSize > 1_000_000_000 {
                score -= 10
                localRecs.append(HealthRecommendation(
                    title: "Bersihkan Cache Xcode",
                    description: "Sisa build (DerivedData) dari project lama memakan ruang yang sangat besar.",
                    size: xSize,
                    icon: "hammer.fill",
                    color: .blue,
                    actionLabel: "Hapus Sekarang"
                ) {
                    Task { @MainActor in self.quickTrashFolder(url: derivedDataURL, size: xSize) }
                })
            }
            
            // 5. Downloads
            let downloadsURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
            let dSize = self.calculateFolderSizeFast(url: downloadsURL)
            localDownloads = dSize
            if dSize > 3_000_000_000 {
                score -= 2
                localRecs.append(HealthRecommendation(
                    title: "Rapikan Folder Downloads",
                    description: "Folder unduhan Anda menumpuk. Gunakan Organizer untuk merapikannya otomatis.",
                    size: dSize,
                    icon: "folder.badge.gearshape",
                    color: .purple,
                    actionLabel: "Buka Organizer"
                ) {
                    Task { @MainActor in selection.wrappedValue = .organizer }
                })
            }
            
            // 6. Generic Suggestion
            if score >= 90 && localRecs.isEmpty {
                 localRecs.append(HealthRecommendation(
                    title: "Pindai Sisa Aplikasi & Caches",
                    description: "Mac Anda dalam kondisi prima. Jalankan Smart Scan jika ingin mencari file sisa yang tersembunyi.",
                    size: nil,
                    icon: "wand.and.stars",
                    color: .green,
                    actionLabel: "Mulai Smart Scan"
                ) {
                    Task { @MainActor in selection.wrappedValue = .smartScan }
                })
            }
            
            let finalTotal = localTotal
            let finalFree = localFree
            let finalTrash = localTrash
            let finalXcode = localXcode
            let finalDownloads = localDownloads
            let finalRecs = localRecs
            let finalScore = score
            await MainActor.run {
                self.totalDiskSpace = finalTotal
                self.freeDiskSpace = finalFree
                self.trashSize = finalTrash
                self.xcodeSize = finalXcode
                self.downloadsSize = finalDownloads
                self.recommendations = finalRecs
                self.healthScore = max(0, finalScore)
                self.isAnalyzing = false
            }
        }
    }
    
    nonisolated private func calculateFolderSizeFast(url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return 0 }
        
        var total: Int64 = 0
        var count = 0
        for case let fileURL as URL in enumerator {
            if let rv = try? fileURL.resourceValues(forKeys: Set(keys)), rv.isDirectory != true {
                total += Int64(rv.fileSize ?? 0)
                count += 1
            }
            if count > 50_000 { break } 
        }
        return total
    }
    
    private func quickTrashFolder(url: URL, size: Int64) {
        Task {
            do {
                var actualDeleted: Int64 = 0
                if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
                    for case let fileURL as URL in enumerator {
                        let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                        do {
                            try FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
                            actualDeleted += Int64(fileSize)
                        } catch {
                            // Ignored
                        }
                    }
                }
                DailyReportManager.shared.addSavings(actualDeleted)
                
                if let selection = self.selectionBinding {
                    await MainActor.run {
                        self.analyze(selection: selection)
                    }
                }
            }
        }
    }
}

struct MacHealthDashboardView: View {
    @Binding var selection: NavigationMode?
    @StateObject private var viewModel = MacHealthViewModel()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Top Health Score Section
                HStack(spacing: 40) {
                    ZStack {
                        Circle()
                            .stroke(lineWidth: 16)
                            .opacity(0.2)
                            .foregroundColor(.secondary)
                        
                        Circle()
                            .trim(from: 0.0, to: CGFloat(viewModel.healthScore) / 100.0)
                            .stroke(style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round))
                            .foregroundColor(healthColor)
                            .rotationEffect(Angle(degrees: 270.0))
                            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: viewModel.healthScore)
                        
                        VStack(spacing: 4) {
                            Text("\(viewModel.healthScore)")
                                .font(.system(size: 64, weight: .bold, design: .rounded))
                                .foregroundColor(healthColor)
                            Text("Mac Health")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 180, height: 180)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text(LocalizedStringKey(healthTitle))
                            .font(.largeTitle)
                            .bold()
                        Text(LocalizedStringKey(healthDescription))
                            .font(.title3)
                            .foregroundColor(.secondary)
                        
                        if viewModel.isAnalyzing {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Menganalisis kondisi sistem...")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 8)
                        }
                    }
                    Spacer()
                }
                .padding(40)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(20)
                
                // Quick Stats Section
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                    StatCardView(title: "Penyimpanan", value: "\((viewModel.totalDiskSpace - viewModel.freeDiskSpace).formattedSize)", icon: "internaldrive.fill", color: .blue)
                    StatCardView(title: "Sampah", value: "\(viewModel.trashSize.formattedSize)", icon: "trash.fill", color: .orange)
                    StatCardView(title: "Unduhan", value: "\(viewModel.downloadsSize.formattedSize)", icon: "arrow.down.circle.fill", color: .purple)
                    StatCardView(title: "Xcode Cache", value: "\(viewModel.xcodeSize.formattedSize)", icon: "hammer.fill", color: .green)
                }
                
                // Recommendations Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Rekomendasi Cerdas")
                        .font(.title2)
                        .bold()
                    
                    if viewModel.recommendations.isEmpty && !viewModel.isAnalyzing {
                        Text("Tidak ada masalah mendesak yang ditemukan.")
                            .foregroundColor(.secondary)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(viewModel.recommendations) { rec in
                                HealthRecommendationRow(rec: rec)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                
                Spacer(minLength: 40)
            }
            .padding(30)
        }
        .onAppear {
            viewModel.analyze(selection: $selection)
        }
    }
    
    @MainActor private var healthColor: Color {
        if viewModel.healthScore >= 90 { return .green }
        if viewModel.healthScore >= 70 { return .orange }
        return .red
    }
    
    @MainActor private var healthTitle: String {
        if viewModel.healthScore >= 90 { return "Mac Anda dalam kondisi prima." }
        if viewModel.healthScore >= 70 { return "Mac Anda butuh sedikit perhatian." }
        return "Sistem perlu segera dibersihkan."
    }
    
    @MainActor private var healthDescription: String {
        if viewModel.healthScore >= 90 { return "Penyimpanan lega dan tidak ada penumpukan cache yang signifikan." }
        if viewModel.healthScore >= 70 { return "Ada penumpukan file yang bisa dibersihkan untuk membebaskan ruang." }
        return "Ruang penyimpanan kritis atau ada sampah besar yang memperlambat sistem."
    }
}

struct HealthRecommendationRow: View {
    let rec: HealthRecommendation
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(rec.color.opacity(0.1))
                    .frame(width: 54, height: 54)
                Image(systemName: rec.icon)
                    .font(.title2)
                    .foregroundColor(rec.color)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(LocalizedStringKey(rec.title))
                        .font(.headline)
                    if let size = rec.size {
                        Text(size.formattedSize)
                            .font(.caption)
                            .bold()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                Text(LocalizedStringKey(rec.description))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: rec.action) {
                Text(LocalizedStringKey(rec.actionLabel))
                    .font(.subheadline).bold()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(isHovered ? rec.color : rec.color.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .onHover { hover in
                isHovered = hover
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
}

struct StatCardView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.1))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.system(size: 14, weight: .bold))
                }
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(LocalizedStringKey(title))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
}

import SwiftUI

// MARK: - Duplicates View
@MainActor
class DuplicatesViewModel: ObservableObject {
    @Published var groups: [DuplicateGroup] = []
    @Published var isScanning = false
    @Published var errorMessage: String? = nil
    @Published var showError: Bool = false
    @Published var selectedURLs: Set<URL> = []
    
    var totalSelectedSize: Int64 {
        var total: Int64 = 0
        for group in groups {
            for url in group.files where selectedURLs.contains(url) {
                total += group.size
            }
        }
        return total
    }
    
    func startScan() {
        isScanning = true
        groups.removeAll()
        selectedURLs.removeAll()
        
        Task {
            let finder = DuplicateFinderActor()
            self.groups = await finder.startScan()
            self.isScanning = false
            
            // Auto-select everything except the first item (the original)
            for group in self.groups {
                let duplicates = group.files.dropFirst()
                for url in duplicates {
                    self.selectedURLs.insert(url)
                }
            }
        }
    }
    
    func purgeSelected(action: PurgeAction) {
        let size = self.totalSelectedSize
        Task {
            do {
                let itemsToDelete = selectedURLs.map { ScannedItem(url: $0, size: 0, category: .uncategorized, riskLevel: .safe, isDirectory: false) }
                try await PurgeService.execute(action, items: itemsToDelete)
                
                // Hapus dari list
                for i in groups.indices.reversed() {
                    groups[i].files.removeAll { selectedURLs.contains($0) }
                    if groups[i].files.count < 2 {
                        groups.remove(at: i)
                    }
                }
                selectedURLs.removeAll()
                
                DailyReportManager.shared.addSavings(Int64(size))
            } catch {
                print(error)
            }
        }
    }
}

struct DuplicatesView: View {
    @StateObject private var viewModel = DuplicatesViewModel()
    @EnvironmentObject var globalState: GlobalAppState
    @AppStorage("fileReviewMode") private var fileReviewMode: String = "list"
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pencari Berkas Kembar")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { viewModel.startScan() }) {
                    if viewModel.isScanning { Text("Mencari...") }
                    else { Text("Cari Duplikat") }
                }
                .disabled(viewModel.isScanning)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            if viewModel.isScanning {
                VStack {
                    Spacer()
                    ProgressView("Mengolah hash file di Documents & Downloads...")
                    Spacer()
                }
            } else if viewModel.groups.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("Pencari Berkas Kembar")
                        .font(.largeTitle)
                        .bold()
                    Text("Temukan file ganda yang menghabiskan ruang disk Anda.")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                if fileReviewMode == "swipe" {
                    // Flatten duplicates into swipe items, but SKIP the original (first item in group)
                    let swipeItems = viewModel.groups.flatMap { group -> [SwipeCardItem] in
                        // Drop the first item (we assume it's the original to keep)
                        let copies = Array(group.files.dropFirst())
                        return copies.map { url in
                            SwipeCardItem(
                                id: url.path,
                                title: url.lastPathComponent,
                                subtitle: "Salinan dari: " + (group.files.first?.lastPathComponent ?? "File Asli"),
                                sizeString: group.size.formattedSize,
                                categoryString: "Duplikat",
                                isDirectory: false,
                                fileURL: url,
                                onSwipeLeft: {
                                    viewModel.selectedURLs.insert(url)
                                },
                                onSwipeRight: {
                                    viewModel.selectedURLs.remove(url)
                                }
                            )
                        }
                    }
                    SwipeCardContainer(items: swipeItems, isScanning: viewModel.isScanning)
                } else {
                    List {
                        ForEach(viewModel.groups) { group in
                            Section(header: Text("Grup Duplikat: \(group.size.formattedSize)").font(.headline)) {
                                ForEach(group.files, id: \.self) { url in
                                    HStack {
                                        let isSelected = viewModel.selectedURLs.contains(url)
                                        Toggle("", isOn: Binding(
                                            get: { isSelected },
                                            set: { val in
                                                if val { viewModel.selectedURLs.insert(url) }
                                                else { viewModel.selectedURLs.remove(url) }
                                            }
                                        ))
                                        
                                        Image(systemName: "doc")
                                        VStack(alignment: .leading) {
                                            Text(url.lastPathComponent).font(.subheadline).bold()
                                            Text(url.path).font(.caption2).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Button(action: { NSWorkspace.shared.activateFileViewerSelecting([url]) }) {
                                            Image(systemName: "magnifyingglass.circle.fill")
                                        }.buttonStyle(BorderlessButtonStyle())
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                }
            }
            
            PreviewSavingsBar(totalSize: viewModel.totalSelectedSize, action: { action in
                viewModel.purgeSelected(action: action)
            })
        }
        .onChange(of: viewModel.isScanning) { newValue in
            globalState.isAnyScanning = newValue
        }
    }
}

// MARK: - Large Files View
@MainActor
class LargeFilesViewModel: ObservableObject {
    @Published var items: [ScannedItem] = []
    @Published var isScanning = false
    @Published var errorMessage: String? = nil
    @Published var showError: Bool = false
    @Published var scannedCount = 0
    @Published var currentPath = ""
    
    var totalSelectedSize: Int64 {
        items.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
    }
    
    func startScan() {
        items.removeAll()
        isScanning = true
        scannedCount = 0
        currentPath = "Memulai radar..."
        
        let cache = ScanCacheManager.shared.largeFilesCache
        if !cache.isEmpty {
            Task {
                let sortedCache = cache.sorted { $0.size > $1.size }
                withAnimation(.spring()) {
                    self.items = sortedCache
                }
                self.isScanning = false
                self.currentPath = "Selesai (dari Cache)"
            }
            return
        }
        
        Task {
            let actor = LargeFilesActor()
            let stream = await actor.startScan()
            
            for await event in stream {
                switch event {
                case .progress(let count, let path):
                    self.scannedCount = count
                    self.currentPath = path
                case .batch(let batch):
                    withAnimation(.spring()) {
                        for item in batch {
                            if let index = self.items.firstIndex(where: { $0.size < item.size }) {
                                self.items.insert(item, at: index)
                            } else {
                                self.items.append(item)
                            }
                        }
                    }
                }
            }
            ScanCacheManager.shared.largeFilesCache = self.items
            self.isScanning = false
            self.currentPath = "Pencarian Selesai"
        }
    }
    
    func purgeSelected(action: PurgeAction) {
        let sizeToPurge = self.totalSelectedSize
        Task {
            do {
                try await PurgeService.execute(action, items: items)
                withAnimation {
                    items.removeAll { $0.isSelected }
                }
                DailyReportManager.shared.addSavings(Int64(sizeToPurge))
            } catch {
                print("Error purging: \(error)")
            }
        }
    }
}

struct LargeFilesView: View {
    @StateObject private var viewModel = LargeFilesViewModel()
    @EnvironmentObject var globalState: GlobalAppState
    @AppStorage("fileReviewMode") private var fileReviewMode: String = "list"
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if viewModel.isScanning {
                    VStack(alignment: .leading) {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("\(viewModel.scannedCount) file disisir")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }
                        Text(viewModel.currentPath)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } else {
                    VStack(alignment: .leading) {
                        Text("Radar Berkas Raksasa")
                            .font(.headline)
                        Text("Temukan file >1GB, installer lama, atau proyek usang.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    viewModel.startScan()
                }) {
                    if viewModel.isScanning {
                        Text("Mencari...")
                    } else {
                        Text("Mulai Radar")
                    }
                }
                .disabled(viewModel.isScanning)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            if viewModel.items.isEmpty && !viewModel.isScanning {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("Radar Berkas Raksasa")
                        .font(.largeTitle)
                        .bold()
                    Text("Deteksi file berukuran super besar dan usang.")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                if fileReviewMode == "swipe" {
                    SwipeCardContainer(items: viewModel.items.map { item in
                        SwipeCardItem(
                            id: item.id.uuidString,
                            title: item.name,
                            subtitle: item.url.path,
                            sizeString: item.size.formattedSize,
                            categoryString: item.category.rawValue,
                            isDirectory: item.isDirectory,
                            fileURL: item.url,
                            onSwipeLeft: {
                                if let idx = viewModel.items.firstIndex(where: { $0.id == item.id }) {
                                    viewModel.items[idx].isSelected = true
                                }
                            },
                            onSwipeRight: {
                                if let idx = viewModel.items.firstIndex(where: { $0.id == item.id }) {
                                    viewModel.items[idx].isSelected = false
                                }
                            }
                        )
                    }, isScanning: viewModel.isScanning)
                } else {
                    List($viewModel.items) { $item in
                        HStack {
                        Toggle("", isOn: $item.isSelected)
                        
                        Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading) {
                            Text(LocalizedStringKey(item.name)).font(.headline)
                            Text(item.url.path).font(.caption).foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(item.size.formattedSize)
                            .font(.subheadline)
                            .bold()
                            .foregroundColor(.orange)
                        
                        Text(LocalizedStringKey(item.category.rawValue))
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .clipShape(Capsule())
                        
                        Button(action: {
                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                        }) {
                            Image(systemName: "magnifyingglass.circle.fill")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    .padding(.vertical, 4)
                }
                } // End if swipe
            }
            
            PreviewSavingsBar(totalSize: viewModel.totalSelectedSize, action: { action in
                viewModel.purgeSelected(action: action)
            })
        }
        .onChange(of: viewModel.isScanning) { newValue in
            globalState.isAnyScanning = newValue
        }
    }
}
import SwiftUI


// MARK: - RAM Manager
import Darwin

struct RAMInfo {
    var total: Int64
    var used: Int64
    var free: Int64
    var percentage: Double {
        total > 0 ? Double(used) / Double(total) : 0
    }
}

class RAMManager {
    static let shared = RAMManager()
    
    func getRAMInfo() -> RAMInfo {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        
        let hostPort = mach_host_self()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        mach_port_deallocate(mach_task_self_, hostPort)
        
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        
        if result == KERN_SUCCESS {
            let pageSize = Int64(getpagesize())
            let freeMemory = Int64(stats.free_count) * pageSize
            let inactiveMemory = Int64(stats.inactive_count) * pageSize
            
            // In macOS, free memory + inactive memory is generally considered "available" RAM.
            // Some apps also count speculative or cached files as free, but we stick to basic free + inactive.
            let available = freeMemory + inactiveMemory
            let used = total - available
            
            return RAMInfo(total: total, used: used, free: available)
        } else {
            return RAMInfo(total: total, used: total / 2, free: total / 2)
        }
    }
    
    func freeUpRAM() async -> Int64 {
        let before = getRAMInfo().free
        
        // Allocate a massive amount of memory to trigger macOS memory pressure and compression.
        // We will try to allocate about 15% of total physical memory.
        let total = ProcessInfo.processInfo.physicalMemory
        let allocationSize = Int(Double(total) * 0.15)
        
        // Allocate
        if let pointer = malloc(allocationSize) {
            // Write dummy data to ensure the memory is actually paged/backed by physical RAM (not just virtual).
            // We only write sparse data to speed it up (1 byte every 4MB) to trigger physical pages.
            let pageSize = 4 * 1024 * 1024 // 4MB jumps
            let ptr8 = pointer.bindMemory(to: UInt8.self, capacity: allocationSize)
            for i in stride(from: 0, to: allocationSize, by: pageSize) {
                ptr8[i] = 1
            }
            
            // Hold it for 1.5 seconds so macOS realizes there is memory pressure and purges inactive memory.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            
            // Free the memory
            free(pointer)
        }
        
        // Wait a tiny bit for the OS to settle
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        let after = getRAMInfo().free
        let freed = after - before
        return freed > 0 ? freed : 0
    }
}

struct MenuBarPopupView: View {
    @AppStorage("totalSavedBytes") private var totalSavedBytes: Double = 0
    @State private var isCleaning = false
    @State private var isFreeingRAM = false
    @State private var statusMessage = ""
    @State private var ramInfo: RAMInfo = RAMInfo(total: 1, used: 0, free: 0)
    
    // Timer to update RAM every 2 seconds
    let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 16) {
            
            // ZONA ATAS (Identitas & Penghematan)
            HStack {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shed Mini")
                        .font(.headline)
                    HStack(spacing: 4) {
                        Text("Total Dihemat:")
                        Text(Int64(totalSavedBytes).formattedSize)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)
            
            Divider()
            
            // ZONA TENGAH (Monitor RAM)
            VStack(spacing: 12) {
                Text("Monitor Memori (RAM)")
                    .font(.subheadline)
                    .bold()
                
                ZStack {
                    Circle()
                        .stroke(lineWidth: 10)
                        .opacity(0.3)
                        .foregroundColor(.secondary)
                    
                    let percentage = ramInfo.percentage
                    Circle()
                        .trim(from: 0.0, to: CGFloat(min(percentage, 1.0)))
                        .stroke(style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                        .foregroundColor(percentage > 0.85 ? .red : (percentage > 0.7 ? .orange : .blue))
                        .rotationEffect(Angle(degrees: 270.0))
                    
                    VStack {
                        Text("\(Int(percentage * 100))%")
                            .font(.title3)
                            .bold()
                            .foregroundColor(percentage > 0.85 ? .red : .primary)
                    }
                }
                .frame(width: 80, height: 80)
                
                HStack(spacing: 4) {
                    Text(ramInfo.used.formattedSize)
                    Text("/")
                    Text(ramInfo.total.formattedSize)
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                if !statusMessage.isEmpty && statusMessage.contains("RAM") {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(.green)
                        .multilineTextAlignment(.center)
                        .frame(height: 15)
                }
                
                Button(action: freeUpMemory) {
                    if isFreeingRAM {
                        ProgressView().controlSize(.small)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Bebaskan RAM")
                            .bold()
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isFreeingRAM || isCleaning)
                .padding(.horizontal)
            }
            
            Divider()
            
            // ZONA BAWAH (Pembersih Caches)
            VStack(spacing: 10) {
                if !statusMessage.isEmpty && statusMessage.contains("Caches") {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(.green)
                        .multilineTextAlignment(.center)
                        .frame(height: 15)
                }
                
                Button(action: quickCleanCaches) {
                    if isCleaning {
                        ProgressView().controlSize(.small)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Bersihkan Caches Sekarang")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isCleaning || isFreeingRAM)
                .padding(.horizontal)
            }
            
            Divider()
            
            // KONTROL BAWAH
            HStack {
                Button("Buka Shed") {
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
                .buttonStyle(.borderless)
                .foregroundColor(.blue)
                
                Spacer()
                
                Button("Keluar") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 16)
        .frame(width: 280)
        .onAppear {
            ramInfo = RAMManager.shared.getRAMInfo()
        }
        .onReceive(timer) { _ in
            if !isFreeingRAM {
                withAnimation {
                    ramInfo = RAMManager.shared.getRAMInfo()
                }
            }
        }
    }
    
    private func freeUpMemory() {
        isFreeingRAM = true
        statusMessage = NSLocalizedString("Memaksa kompresi RAM...", comment: "")
        
        Task {
            let freedBytes = await RAMManager.shared.freeUpRAM()
            ramInfo = RAMManager.shared.getRAMInfo()
            isFreeingRAM = false
            
            if freedBytes > 0 {
                statusMessage = String(format: NSLocalizedString("%@ RAM berhasil dibebaskan!", comment: ""), freedBytes.formattedSize)
            } else {
                statusMessage = NSLocalizedString("RAM sudah dalam kondisi optimal.", comment: "")
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                statusMessage = ""
            }
        }
    }
    
    private func quickCleanCaches() {
        isCleaning = true
        statusMessage = NSLocalizedString("Membersihkan Caches...", comment: "")
        
        Task {
            var sizeCleared: Int64 = 0
            do {
                let cacheURLs = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
                for cacheURL in cacheURLs {
                    if let enumerator = FileManager.default.enumerator(at: cacheURL, includingPropertiesForKeys: [.fileSizeKey]) {
                        for case let fileURL as URL in enumerator {
                            let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                            if let fileSize = resourceValues.fileSize {
                                sizeCleared += Int64(fileSize)
                            }
                            try FileManager.default.removeItem(at: fileURL)
                        }
                    }
                }
                
                withAnimation {
                    DailyReportManager.shared.addSavings(sizeCleared)
                    statusMessage = String(format: NSLocalizedString("%@ Caches dibersihkan!", comment: ""), sizeCleared.formattedSize)
                }
            } catch {
                statusMessage = NSLocalizedString("Gagal membersihkan cache.", comment: "")
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation {
                    isCleaning = false
                    statusMessage = ""
                }
            }
        }
    }
}


// MARK: - Onboarding View
struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentStep = 1
    @State private var hasFDA = FullDiskAccessHelper.hasFullDiskAccess
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor).edgesIgnoringSafeArea(.all)
            
            VStack {
                if currentStep == 1 {
                    step1
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                } else if currentStep == 2 {
                    step2
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                } else if currentStep == 3 {
                    step3
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                } else if currentStep == 4 {
                    step4
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                }
            }
            .frame(maxWidth: 800, maxHeight: 600)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut, value: currentStep)
        .onReceive(timer) { _ in
            if currentStep == 2 {
                hasFDA = FullDiskAccessHelper.hasFullDiskAccess
            }
        }
    }
    
    var step1: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "trash.circle.fill")
                .font(.system(size: 100))
                .foregroundColor(.blue)
            
            Text("Selamat Datang di Shed")
                .font(.system(size: 32, weight: .bold))
            
            Text("Mari buat Mac Anda kembali lega dan ngebut bak mesin baru.\nShed akan membantu Anda membuang file sampah yang tersembunyi dengan aman.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            
            Spacer()
            
            Button(action: { currentStep = 2 }) {
                Text("Lanjut")
                    .font(.headline)
                    .frame(width: 200, height: 44)
            }
            .buttonStyle(DefaultButtonStyle())
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .padding(.bottom, 40)
        }
    }
    
    var step2: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: hasFDA ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.system(size: 80))
                .foregroundColor(hasFDA ? .green : .orange)
            
            Text("Izin Akses Terdalam")
                .font(.system(size: 28, weight: .bold))
            
            Text("Agar Shed bisa menyapu bersih sisa aplikasi dan cache tersembunyi,\nmohon berikan Akses Disk Penuh (Full Disk Access).")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            
            if !hasFDA {
                Button("Buka Pengaturan Privasi") {
                    FullDiskAccessHelper.openPrivacySettings()
                }
                .buttonStyle(DefaultButtonStyle())
                .padding(.top, 10)
                
                Text("Menunggu izin diberikan...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Akses Diberikan! Terima kasih.")
                    .font(.headline)
                    .foregroundColor(.green)
                    .padding(.top, 10)
            }
            
            Spacer()
            
            Button(action: { currentStep = 3 }) {
                Text(hasFDA ? "Lanjut" : "Lewati Dulu")
                    .font(.headline)
                    .frame(width: 200, height: 44)
            }
            .buttonStyle(DefaultButtonStyle())
            .controlSize(.large)
            .padding(.bottom, 40)
        }
    }
    
    var step3: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "menubar.rectangle")
                .font(.system(size: 80))
                .foregroundColor(.primary)
            
            Text("Selalu Siap Sedia")
                .font(.system(size: 28, weight: .bold))
            
            Text("Shed juga hidup di Menu Bar Anda (pojok kanan atas).\nKapan pun Mac terasa penuh, bersihkan Caches hanya dengan satu klik.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            
            Spacer()
            
            Button(action: {
                withAnimation {
                    currentStep = 4
                }
            }) {
                Text("Lanjut")
                    .font(.headline)
                    .frame(width: 240, height: 44)
            }
            .buttonStyle(DefaultButtonStyle())
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .padding(.bottom, 40)
        }
    }


    var step4: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 80))
                .foregroundColor(.purple)
            
            Text("Izin Notifikasi Harian")
                .font(.system(size: 28, weight: .bold))
            
            Text("Shed akan mengirimkan ringkasan Laporan Malam setiap jam 21:00.\nMohon izinkan saat macOS meminta akses notifikasi.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            
            Spacer()
            
            Button(action: {
                DailyReportManager.shared.setupNotifications()
                withAnimation {
                    hasCompletedOnboarding = true
                }
            }) {
                Text("Izinkan & Mulai Gunakan Shed!")
                    .font(.headline)
                    .frame(width: 280, height: 44)
            }
            .buttonStyle(DefaultButtonStyle())
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @State private var selection: String? = "Umum"
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    
    var body: some View {
        if !hasCompletedOnboarding {
            VStack {
                Text("Harap selesaikan Onboarding terlebih dahulu.")
            }
            .frame(width: 400, height: 200)
            .onAppear {
                DispatchQueue.main.async {
                    NSApp.windows.filter { $0.title == "Settings" || $0.title == "Pengaturan" || $0.identifier?.rawValue.contains("settings") == true }.first?.close()
                }
            }
        } else {
        NavigationView {
            List {
                NavigationLink(destination: SettingsGeneralView(), tag: "Umum", selection: $selection) {
                    Label("Umum", systemImage: "gearshape")
                }
                NavigationLink(destination: SettingsCleaningView(), tag: "Pembersihan", selection: $selection) {
                    Label("Pembersihan", systemImage: "wand.and.stars")
                }
                NavigationLink(destination: SettingsWhitelistView(), tag: "Pengecualian", selection: $selection) {
                    Label("Pengecualian", systemImage: "shield.fill")
                }
                NavigationLink(destination: SettingsAdvancedView(), tag: "Lanjutan", selection: $selection) {
                    Label("Lanjutan", systemImage: "exclamationmark.triangle")
                }
            }
            .listStyle(SidebarListStyle())
            .frame(minWidth: 180)
            
            SettingsGeneralView()
        }
        .frame(minWidth: 700, minHeight: 450)
        .background(WindowAccessor())
        }
    }
}

struct SettingsGeneralView: View {
    @AppStorage("appLanguage") private var appLanguage = "id"
    @AppStorage("fileReviewMode") private var fileReviewMode: String = "list"
    @AppStorage("selectedDiskPath") private var selectedDiskPath = "/"
    @AppStorage("appAppearance") private var appAppearance = "system"
    @State private var mountedDisks: [(name: String, path: String, icon: String)] = []
    
    var body: some View {
        VStack {
            Form {
                Section {
                Picker("Bahasa (Language)", selection: $appLanguage) {
                    Text("Bahasa Indonesia").tag("id")
                    Text("English").tag("en")
                }
                .pickerStyle(.menu)
                .padding(.bottom, 10)
                
                Picker("Tema Tampilan", selection: $appAppearance) {
                    Text("Ikuti Sistem").tag("system")
                    Text("Terang (Light)").tag("light")
                    Text("Gelap (Dark)").tag("dark")
                }
                .pickerStyle(.menu)
                .padding(.bottom, 10)
                

                
                Picker("Gaya Tampilan Scan", selection: $fileReviewMode) {
                    Text("Mode Daftar (List)").tag("list")
                    Text("Mode Kartu (Swipe)").tag("swipe")
                }
                .pickerStyle(.menu)
                .padding(.bottom, 10)
                
                Picker("Target Disk", selection: $selectedDiskPath) {
                    ForEach(mountedDisks, id: \.path) { disk in
                        HStack {
                            Image(systemName: disk.icon)
                            Text(disk.name)
                        }.tag(disk.path)
                    }
                }
                .pickerStyle(.menu)
            }
            }
            Spacer()
        }
        .padding(30)
        .font(.system(size: 14))
        .navigationTitle("Umum")
        .onAppear {
            fetchDisks()
        }
    }
    
    private func fetchDisks() {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsInternalKey, .volumeIsRemovableKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else { return }
        
        var disks: [(String, String, String)] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let name = values.volumeName ?? url.lastPathComponent
            var icon = "externaldrive"
            if values.volumeIsInternal == true { icon = "internaldrive" }
            disks.append((name, url.path, icon))
        }
        self.mountedDisks = disks
        if !mountedDisks.contains(where: { $0.path == selectedDiskPath }) {
            selectedDiskPath = "/"
        }
    }
}

struct SettingsCleaningView: View {
    @AppStorage("defaultPurgeAction") private var defaultPurgeAction = "trash"
    @AppStorage("autoDeleteQuarantine") private var autoDeleteQuarantine = false
    
    var body: some View {
        VStack {
            Form {
                Section {
                Picker("Tindakan Default", selection: $defaultPurgeAction) {
                    Text("Pindahkan ke Tong Sampah").tag("trash")
                    Text("Karantina (Folder Aman)").tag("quarantine")
                    Text("Hapus Permanen").tag("permanent")
                }
                .pickerStyle(.radioGroup)
            }
            .padding(.bottom, 20)
            
            Section(header: Text("Otomatisasi").font(.headline)) {
                Toggle("Hapus file Karantina otomatis setelah 30 hari", isOn: $autoDeleteQuarantine)
            }
            }
            Spacer()
        }
        .padding(30)
        .font(.system(size: 14))
        .navigationTitle("Pembersihan")
    }
}

struct SettingsAdvancedView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @AppStorage("totalSavedBytes") private var totalSavedBytes: Double = 0
    @AppStorage("selectedDiskPath") private var selectedDiskPath = "/"
    
    var body: some View {
        VStack {
            Form {
                Section {
                Text("Perhatian: Ini akan mengembalikan aplikasi ke kondisi awal seperti baru diinstal.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 10)
                    
                Button(action: {
                    hasCompletedOnboarding = false
                    totalSavedBytes = 0
                    selectedDiskPath = "/"
                    NSApplication.shared.keyWindow?.close()
                }) {
                    Text("Reset Aplikasi (Ulangi Onboarding)")
                        .font(.system(size: 14, weight: .bold))
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            }
            Spacer()
        }
        .padding(30)
        .navigationTitle("Lanjutan")
    }
}

// MARK: - Dashboard View (New)
struct DashboardView: View {
    @Binding var selection: NavigationMode?
    
    var body: some View {
        MacHealthDashboardView(selection: $selection)
            .navigationTitle("Dashboard")
    }
}

// MARK: - Settings Whitelist View
struct SettingsWhitelistView: View {
    @AppStorage("whitelistPaths") private var whitelistPathsString: String = ""
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Daftar Pengecualian (Whitelist)")
                    .font(.headline)
                Spacer()
                if presentationMode.wrappedValue.isPresented {
                    Button("Tutup") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .padding(.bottom, 10)
            
            Text("Shed tidak akan pernah memindai atau menghapus file yang berada di dalam folder-folder ini. Gunakan ini untuk melindungi proyek kerja atau folder rahasia Anda.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            let paths = getPaths()
            
            List {
                ForEach(paths, id: \.self) { path in
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.blue)
                        Text(path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(action: { removePath(path) }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .border(Color.secondary.opacity(0.2))
            
            HStack {
                Spacer()
                Button(action: addPath) {
                    Label("Tambah Folder...", systemImage: "plus")
                }
            }
        }
        .padding()
    }
    
    private func getPaths() -> [String] {
        if whitelistPathsString.isEmpty { return [] }
        return whitelistPathsString.components(separatedBy: "|")
    }
    
    private func removePath(_ path: String) {
        var paths = getPaths()
        paths.removeAll { $0 == path }
        whitelistPathsString = paths.joined(separator: "|")
    }
    
    private func addPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Kecualikan"
        
        if panel.runModal() == .OK {
            var paths = getPaths()
            for url in panel.urls {
                if !paths.contains(url.path) {
                    paths.append(url.path)
                }
            }
            whitelistPathsString = paths.joined(separator: "|")
        }
    }
}

// MARK: - Window Accessor Hack for Settings
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.styleMask.insert(.resizable)
                window.styleMask.insert(.miniaturizable)
                window.standardWindowButton(.zoomButton)?.isEnabled = true
                window.standardWindowButton(.miniaturizeButton)?.isEnabled = true
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - App Uninstaller Model
struct AppUninstallItem: Identifiable {
    let id = UUID()
    let name: String
    let bundleId: String
    let appURL: URL? // Optional for leftovers
    let icon: NSImage
    let appSize: Int64
    let associatedURLs: [URL]
    let associatedSize: Int64
    var isLeftover: Bool = false
    var isSelected: Bool = false
    
    var totalSize: Int64 { appSize + associatedSize }
}

// MARK: - App Uninstaller Actor
actor AppUninstallerActor {
    private func getDirectorySize(url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var size: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = attrs.fileSize else { continue }
            size += Int64(fileSize)
        }
        return size
    }
    
    func scanApps() -> AsyncStream<AppUninstallItem> {
        AsyncStream { continuation in
            Task {
                let fileManager = FileManager.default
                let appDirs = [
                    URL(fileURLWithPath: "/Applications"),
                    fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
                ]
                
                let workspace = NSWorkspace.shared
                
                let libraryURL = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library")
                let searchPaths = [
                    libraryURL.appendingPathComponent("Application Support"),
                    libraryURL.appendingPathComponent("Caches"),
                    libraryURL.appendingPathComponent("Preferences"),
                    libraryURL.appendingPathComponent("Containers"),
                    libraryURL.appendingPathComponent("Logs"),
                    libraryURL.appendingPathComponent("Saved Application State")
                ]
                
                var installedBundleIDs: Set<String> = []
                
                // Pass 1: Installed Apps
                for dir in appDirs {
                    guard let urls = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
                    
                    for url in urls where url.pathExtension == "app" {
                        guard let bundle = Bundle(url: url),
                              let bundleId = bundle.bundleIdentifier else { continue }
                        
                        if bundleId.starts(with: "com.apple.") { continue }
                        
                        installedBundleIDs.insert(bundleId)
                        
                        let name = bundle.infoDictionary?["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent
                        let icon = workspace.icon(forFile: url.path)
                        let appSize = self.getDirectorySize(url: url)
                        
                        var associatedURLs: [URL] = []
                        var associatedSize: Int64 = 0
                        
                        for searchPath in searchPaths {
                            guard let contents = try? fileManager.contentsOfDirectory(at: searchPath, includingPropertiesForKeys: nil) else { continue }
                            for contentURL in contents {
                                let filename = contentURL.lastPathComponent
                                if filename.contains(bundleId) || filename == name || filename == "\(bundleId).plist" {
                                    associatedURLs.append(contentURL)
                                    associatedSize += self.getDirectorySize(url: contentURL)
                                }
                            }
                        }
                        
                        let item = AppUninstallItem(
                            name: name,
                            bundleId: bundleId,
                            appURL: url,
                            icon: icon,
                            appSize: appSize,
                            associatedURLs: associatedURLs,
                            associatedSize: associatedSize,
                            isLeftover: false
                        )
                        continuation.yield(item)
                    }
                }
                
                // Pass 2: Leftovers
                for searchPath in searchPaths {
                    guard let contents = try? fileManager.contentsOfDirectory(at: searchPath, includingPropertiesForKeys: nil) else { continue }
                    for contentURL in contents {
                        let filename = contentURL.lastPathComponent
                        let isBundleIDFormat = filename.starts(with: "com.") || filename.starts(with: "org.") || filename.starts(with: "net.") || filename.starts(with: "io.")
                        if isBundleIDFormat && !filename.starts(with: "com.apple.") {
                            let potentialBundleId = (contentURL.pathExtension == "plist") ? contentURL.deletingPathExtension().lastPathComponent : filename
                            
                            if !installedBundleIDs.contains(potentialBundleId) {
                                // Group by bundleId? For now, yield each as its own item.
                                let size = self.getDirectorySize(url: contentURL)
                                // Skip tiny leftover files like empty plists
                                if size > 1024 {
                                    let fallbackIcon = NSImage(systemSymbolName: "trash.slash.fill", accessibilityDescription: nil) ?? NSImage()
                                    let item = AppUninstallItem(
                                        name: "Sisa: \(potentialBundleId)",
                                        bundleId: potentialBundleId,
                                        appURL: nil,
                                        icon: fallbackIcon,
                                        appSize: 0,
                                        associatedURLs: [contentURL],
                                        associatedSize: size,
                                        isLeftover: true
                                    )
                                    continuation.yield(item)
                                }
                            }
                        }
                    }
                }
                
                continuation.finish()
            }
        }
    }
}

// MARK: - App Uninstaller ViewModel
@MainActor
class AppUninstallerViewModel: ObservableObject {
    @Published var apps: [AppUninstallItem] = []
    @Published var isScanning = false
    @Published var errorMessage: String? = nil
    @Published var showError: Bool = false
    
    var selectedAppsSize: Int64 {
        apps.filter { $0.isSelected }.reduce(0) { $0 + $1.totalSize }
    }
    
    func startScan() {
        isScanning = true
        apps.removeAll()
        
        let cache = ScanCacheManager.shared.uninstallerCache
        if !cache.isEmpty {
            Task {
                let sortedCache = cache.sorted { $0.totalSize > $1.totalSize }
                withAnimation(.spring()) {
                    self.apps = sortedCache
                }
                self.isScanning = false
            }
            return
        }
        
        Task {
            let actor = AppUninstallerActor()
            let stream = await actor.scanApps()
            for await item in stream {
                // Insert in sorted order by totalSize
                if let index = self.apps.firstIndex(where: { $0.totalSize < item.totalSize }) {
                    self.apps.insert(item, at: index)
                } else {
                    self.apps.append(item)
                }
            }
            ScanCacheManager.shared.uninstallerCache = self.apps
            self.isScanning = false
        }
    }
    
    func uninstallSelected() {
        let workspace = NSWorkspace.shared
        let selectedApps = apps.filter { $0.isSelected }
        
        var urlsToTrash: [URL] = []
        for app in selectedApps {
            if let appURL = app.appURL {
                urlsToTrash.append(appURL)
            }
            urlsToTrash.append(contentsOf: app.associatedURLs)
        }
        
        guard !urlsToTrash.isEmpty else { return }
        
        workspace.recycle(urlsToTrash) { _, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Gagal menghapus: \(error.localizedDescription)")
                } else {
                    let saved = selectedApps.reduce(0) { $0 + $1.totalSize }
                    DailyReportManager.shared.addSavings(saved)
                    self.apps.removeAll { $0.isSelected }
                }
            }
        }
    }
}

// MARK: - App UninstallerView
struct AppUninstallerView: View {
    @State private var showingConfirm = false
    @StateObject private var viewModel = AppUninstallerViewModel()
    @EnvironmentObject var globalState: GlobalAppState
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("fileReviewMode") private var fileReviewMode: String = "list"
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("App Uninstaller & Leftovers")
                        .font(.largeTitle)
                        .bold()
                    Text("Hapus aplikasi beserta seluruh sisa file tersembunyinya, termasuk sisa dari aplikasi lama.")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: {
                    viewModel.startScan()
                }) {
                    if viewModel.isScanning {
                        Text("Memindai...")
                    } else {
                        Text("Mulai Pindai Aplikasi")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isScanning)
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor))
            
            if viewModel.apps.isEmpty && !viewModel.isScanning {
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "trash.square")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    Text("Siap Mencari Aplikasi")
                        .font(.title)
                        .bold()
                    Text("Klik 'Mulai Pindai Aplikasi' untuk melihat daftar aplikasi pihak ketiga.")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                if fileReviewMode == "swipe" {
                    SwipeCardContainer(items: viewModel.apps.map { app in
                        SwipeCardItem(
                            id: app.id.uuidString,
                            title: app.name,
                            subtitle: app.bundleId + "\n" + (app.associatedSize > 0 ? "+ \(app.associatedSize.formattedSize) data sisa" : ""),
                            sizeString: app.totalSize.formattedSize,
                            categoryString: "App",
                            isDirectory: true, // We don't want the default doc icon
                            fileURL: app.appURL, // Using app bundle URL will trigger QuickLook thumbnail for the app icon!
                            onSwipeLeft: {
                                if let idx = viewModel.apps.firstIndex(where: { $0.id == app.id }) {
                                    viewModel.apps[idx].isSelected = true
                                }
                            },
                            onSwipeRight: {
                                if let idx = viewModel.apps.firstIndex(where: { $0.id == app.id }) {
                                    viewModel.apps[idx].isSelected = false
                                }
                            }
                        )
                    }, isScanning: viewModel.isScanning)
                } else {
                    List(viewModel.apps) { app in
                        HStack {
                            if let idx = viewModel.apps.firstIndex(where: { $0.id == app.id }) {
                                Toggle("", isOn: $viewModel.apps[idx].isSelected)
                            }
                            
                            Image(nsImage: app.icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 32, height: 32)
                                .padding(.horizontal, 8)
                            
                            VStack(alignment: .leading) {
                                Text(app.name).font(.headline)
                                Text(app.bundleId).font(.caption).foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing) {
                                Text(app.totalSize.formattedSize)
                                    .font(.subheadline)
                                    .bold()
                                if app.associatedSize > 0 {
                                    HStack(spacing: 2) {
                                        Text("+")
                                        Text(app.associatedSize.formattedSize)
                                        Text("data sisa")
                                    }
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // Footer
                HStack {
                    VStack(alignment: .leading) {
                        HStack(spacing: 4) {
                            Text("Terpilih:")
                            Text(viewModel.selectedAppsSize.formattedSize)
                        }
                        .font(.headline)
                    }
                    Spacer()
                    Button(action: {
                        showingConfirm = true
                    }) {
                        Text("Copot Pemasangan (Uninstall)")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(viewModel.selectedAppsSize == 0)
                }
                .padding()
                .background(.regularMaterial)
            }
        }
        .alert(isPresented: $showingConfirm) {
            Alert(
                title: Text(LocalizedStringKey("Konfirmasi Penghapusan")),
                message: Text(LocalizedStringKey("Apakah Anda yakin ingin menghapus aplikasi terpilih? Ini tidak dapat dibatalkan.")),
                primaryButton: .destructive(Text(LocalizedStringKey("Hapus"))) {
                    viewModel.uninstallSelected()
                },
                secondaryButton: .cancel(Text(LocalizedStringKey("Batal")))
            )
        }
        .onChange(of: viewModel.isScanning) { newValue in
            globalState.isAnyScanning = newValue
        }
    }
}

// MARK: - Folder Organizer Models

enum OrganizerCategory: String, CaseIterable, Identifiable {
    case images = "Images"
    case videos = "Videos"
    case audio = "Audio"
    case documents = "Documents"
    case archives = "Archives"
    case installers = "Installers"
    case others = "Others"
    
    var id: String { self.rawValue }
    
    var iconName: String {
        switch self {
        case .images: return "photo.fill"
        case .videos: return "video.fill"
        case .audio: return "music.note"
        case .documents: return "doc.text.fill"
        case .archives: return "doc.zipper"
        case .installers: return "shippingbox.fill"
        case .others: return "doc.fill"
        }
    }
    
    static func category(for extensionString: String) -> OrganizerCategory {
        let ext = extensionString.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "svg", "bmp", "tiff":
            return .images
        case "mp4", "mov", "mkv", "avi", "webm", "flv", "wmv":
            return .videos
        case "mp3", "wav", "aac", "flac", "ogg", "m4a":
            return .audio
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "csv", "rtf":
            return .documents
        case "zip", "rar", "7z", "tar", "gz", "bz2":
            return .archives
        case "dmg", "pkg", "app":
            return .installers
        default:
            return .others
        }
    }
}

struct FolderOrganizerItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let name: String
    let size: Int64
    let category: OrganizerCategory
    var isSelected: Bool = true
}

// MARK: - Folder Organizer Actor

actor FolderOrganizerActor {
    func scanFolder(url: URL) -> AsyncStream<FolderOrganizerItem> {
        AsyncStream { continuation in
            Task {
                let fileManager = FileManager.default
                guard let urls = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
                    continuation.finish()
                    return
                }
                
                for fileURL in urls {
                    // Skip subdirectories to prevent deep nesting mess, EXCEPT for .app bundles
                    let isDirectory = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    if isDirectory && fileURL.pathExtension.lowercased() != "app" {
                        continue
                    }
                    let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    let ext = fileURL.pathExtension
                    let category = OrganizerCategory.category(for: ext)
                    
                    let item = FolderOrganizerItem(
                        url: fileURL,
                        name: fileURL.lastPathComponent,
                        size: Int64(size),
                        category: category
                    )
                    
                    continuation.yield(item)
                    try? await Task.sleep(nanoseconds: 2_000_000)
                }
                
                continuation.finish()
            }
        }
    }
    
    func organize(items: [FolderOrganizerItem], in targetURL: URL) throws {
        let fileManager = FileManager.default
        
        for item in items where item.isSelected {
            let categoryFolder = targetURL.appendingPathComponent(item.category.rawValue)
            
            if !fileManager.fileExists(atPath: categoryFolder.path) {
                try fileManager.createDirectory(at: categoryFolder, withIntermediateDirectories: true)
            }
            
            let destinationURL = categoryFolder.appendingPathComponent(item.name)
            
            // Handle filename collisions
            var finalDestination = destinationURL
            var counter = 1
            while fileManager.fileExists(atPath: finalDestination.path) {
                let nameWithoutExtension = item.url.deletingPathExtension().lastPathComponent
                let ext = item.url.pathExtension
                let newName = ext.isEmpty ? "\(nameWithoutExtension) (\(counter))" : "\(nameWithoutExtension) (\(counter)).\(ext)"
                finalDestination = categoryFolder.appendingPathComponent(newName)
                counter += 1
            }
            
            try fileManager.moveItem(at: item.url, to: finalDestination)
        }
    }
}

// MARK: - Folder Organizer ViewModel

@MainActor
class FolderOrganizerViewModel: ObservableObject {
    @Published var items: [FolderOrganizerItem] = []
    @Published var isScanning = false
    @Published var errorMessage: String? = nil
    @Published var showError: Bool = false
    @Published var selectedFolderURL: URL? = nil
    @Published var isOrganizing = false
    @Published var showSuccessAlert = false
    
    var categorizedItems: [OrganizerCategory: [FolderOrganizerItem]] {
        Dictionary(grouping: items, by: { $0.category })
    }
    
    struct CategoryGroup: Identifiable {
        let id: String
        let category: OrganizerCategory
        let items: [FolderOrganizerItem]
    }
    
    var categoryGroups: [CategoryGroup] {
        OrganizerCategory.allCases.compactMap { category in
            let catItems = categorizedItems[category] ?? []
            return catItems.isEmpty ? nil : CategoryGroup(id: category.rawValue, category: category, items: catItems)
        }
    }
    
    var totalSelectedItems: Int {
        items.filter { $0.isSelected }.count
    }
    
    func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = NSLocalizedString("Pilih", comment: "")
        
        if panel.runModal() == .OK, let url = panel.url {
            self.selectedFolderURL = url
            startScan(url: url)
        }
    }
    
    func startScan(url: URL) {
        items.removeAll()
        isScanning = true
        
        // Cache check
        if ScanCacheManager.shared.organizerLastURL == url && !ScanCacheManager.shared.organizerCache.isEmpty {
            Task {
                for item in ScanCacheManager.shared.organizerCache {
                    withAnimation(.spring()) {
                        self.items.append(item)
                    }
                    try? await Task.sleep(nanoseconds: 2_000_000)
                }
                self.isScanning = false
            }
            return
        }
        
        Task {
            let actor = FolderOrganizerActor()
            let stream = await actor.scanFolder(url: url)
            
            for await item in stream {
                withAnimation(.spring()) {
                    self.items.append(item)
                }
            }
            
            ScanCacheManager.shared.organizerCache = self.items
            ScanCacheManager.shared.organizerLastURL = url
            self.isScanning = false
        }
    }
    
    func organizeSelected() {
        guard let targetURL = selectedFolderURL else { return }
        isOrganizing = true
        
        Task {
            do {
                let actor = FolderOrganizerActor()
                try await actor.organize(items: items, in: targetURL)
                
                // Remove moved items from UI
                withAnimation {
                    self.items.removeAll { $0.isSelected }
                }
                
                ScanCacheManager.shared.organizerCache = self.items
                self.showSuccessAlert = true
            } catch {
                print("Gagal merapikan folder: \(error)")
            }
            self.isOrganizing = false
        }
    }
}

// MARK: - Folder Organizer View

struct FolderOrganizerView: View {
    @State private var showingConfirm = false
    @StateObject private var viewModel = FolderOrganizerViewModel()
    @EnvironmentObject var globalState: GlobalAppState
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            
            if viewModel.selectedFolderURL == nil {
                emptyStateView
            } else if viewModel.items.isEmpty && !viewModel.isScanning {
                cleanStateView
            } else {
                listView
                Divider()
                footerView
            }
        }
        .onChange(of: viewModel.isScanning) { scanning in
            globalState.isAnyScanning = scanning
        }
        .alert(isPresented: $viewModel.showSuccessAlert) {
            Alert(
                title: Text("Berhasil!"),
                message: Text("Folder berhasil dirapikan. File Anda sekarang terorganisir di dalam sub-folder."),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Folder Organizer")
                    .font(.title2)
                    .bold()
                Text("Kelompokkan file Anda ke dalam sub-folder secara otomatis berdasarkan jenisnya.")
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: {
                viewModel.selectFolder()
            }) {
                Text(viewModel.selectedFolderURL == nil ? "Pilih Folder..." : "Ganti Folder...")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isScanning || viewModel.isOrganizing)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            Text("Pilih Folder Untuk Dirapikan")
                .font(.title)
                .bold()
            Text("Pilih folder yang berantakan (seperti Downloads atau Desktop) untuk mulai.")
                .foregroundColor(.secondary)
            Spacer()
        }
    }
    
    private var cleanStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            Text("Folder Ini Sudah Rapi!")
                .font(.title)
                .bold()
            Text("Tidak ada file berserakan yang perlu dipindahkan.")
                .foregroundColor(.secondary)
            Spacer()
        }
    }
    
    private var listView: some View {
        List {
            ForEach(viewModel.categoryGroups) { group in
                Section(header: Text(group.category.rawValue).font(.headline).bold()) {
                    ForEach(group.items) { item in
                        OrganizerItemRow(item: item, category: group.category, viewModel: viewModel)
                    }
                }
            }
        }
    }
    
    private var footerView: some View {
        HStack {
            if viewModel.isScanning {
                ProgressView()
                    .controlSize(.small)
                Text("Memindai folder...")
                    .foregroundColor(.secondary)
            } else {
                Text("\(viewModel.totalSelectedItems) file dipilih")
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: {
                showingConfirm = true
            }) {
                if viewModel.isOrganizing {
                    Text("Merapikan...")
                } else {
                    Text("Rapikan Sekarang!")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.totalSelectedItems == 0 || viewModel.isScanning || viewModel.isOrganizing)
        }
        .padding()
        .alert(isPresented: $showingConfirm) {
            Alert(
                title: Text(LocalizedStringKey("Rapikan Folder")),
                message: Text(LocalizedStringKey("File akan dipindahkan ke dalam sub-folder. Lanjutkan?")),
                primaryButton: .default(Text(LocalizedStringKey("Ya"))) {
                    viewModel.organizeSelected()
                },
                secondaryButton: .cancel(Text(LocalizedStringKey("Batal")))
            )
        }
        .onChange(of: viewModel.isScanning) { newValue in
            globalState.isAnyScanning = newValue
        }
        .onChange(of: viewModel.isOrganizing) { newValue in
            globalState.isAnyScanning = newValue
        }
    }
}

struct OrganizerItemRow: View {
    let item: FolderOrganizerItem
    let category: OrganizerCategory
    @ObservedObject var viewModel: FolderOrganizerViewModel
    
    var body: some View {
        let binding = Binding<Bool>(
            get: {
                if let idx = viewModel.items.firstIndex(where: { $0.id == item.id }) {
                    return viewModel.items[idx].isSelected
                }
                return false
            },
            set: { newValue in
                if let idx = viewModel.items.firstIndex(where: { $0.id == item.id }) {
                    viewModel.items[idx].isSelected = newValue
                }
            }
        )
        
        HStack {
            Toggle("", isOn: binding)
            Image(systemName: category.iconName)
                .foregroundColor(.blue)
                .frame(width: 20)
            Text(LocalizedStringKey(item.name))
            Spacer()
            Text(item.size.formattedSize)
                .foregroundColor(.secondary)
        }
    }
}


// MARK: - Startup Manager Models

struct StartupItem: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let plistURL: URL
    var isEnabled: Bool
    let type: String // e.g., "User Agent", "System Agent"
    let canModify: Bool
}

actor StartupManagerActor {
    func scanStartupItems() -> [StartupItem] {
        var items: [StartupItem] = []
        let fileManager = FileManager.default
        
        let userAgentsURL = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        let systemAgentsURL = URL(fileURLWithPath: "/Library/LaunchAgents")
        let systemDaemonsURL = URL(fileURLWithPath: "/Library/LaunchDaemons")
        
        items.append(contentsOf: scanFolder(url: userAgentsURL, type: "User Agent", canModify: true))
        items.append(contentsOf: scanFolder(url: systemAgentsURL, type: "System Agent", canModify: false))
        items.append(contentsOf: scanFolder(url: systemDaemonsURL, type: "System Daemon", canModify: false))
        
        return items.sorted { $0.name < $1.name }
    }
    
    private func scanFolder(url: URL, type: String, canModify: Bool) -> [StartupItem] {
        var results: [StartupItem] = []
        let fileManager = FileManager.default
        
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) else {
            return results
        }
        
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "plist" {
                if let dict = NSDictionary(contentsOf: fileURL) as? [String: Any] {
                    let label = dict["Label"] as? String ?? fileURL.deletingPathExtension().lastPathComponent
                    let name = formatName(label)
                    
                    // A LaunchAgent is enabled if RunAtLoad is true, or if KeepAlive is true.
                    // If RunAtLoad is missing, it's typically false unless it's a Daemon.
                    let runAtLoad = dict["RunAtLoad"] as? Bool ?? false
                    let keepAlive = dict["KeepAlive"] as? Bool ?? false
                    let isEnabled = runAtLoad || keepAlive
                    
                    results.append(StartupItem(name: name, plistURL: fileURL, isEnabled: isEnabled, type: type, canModify: canModify))
                }
            }
        }
        return results
    }
    
    private func formatName(_ label: String) -> String {
        // e.g., com.google.keystone.agent -> Google Keystone Agent
        var parts = label.components(separatedBy: ".")
        if parts.count > 2 {
            parts.removeFirst(2) // remove com.company
        }
        return parts.joined(separator: " ").capitalized
    }
    
    func toggleItem(_ item: StartupItem, isEnabled: Bool) -> Bool {
        guard item.canModify else { return false }
        
        do {
            let data = try Data(contentsOf: item.plistURL)
            var format: PropertyListSerialization.PropertyListFormat = .xml
            guard var dict = try PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: &format) as? [String: Any] else {
                return false
            }
            
            // Set RunAtLoad explicitly
            dict["RunAtLoad"] = isEnabled
            
            // If turning off, also disable KeepAlive to completely stop it
            if !isEnabled {
                dict["KeepAlive"] = false
            }
            
            let newData = try PropertyListSerialization.data(fromPropertyList: dict, format: format, options: 0)
            try newData.write(to: item.plistURL)
            
            // Integrate with launchctl
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            let domain = "gui/\(getuid())"
            let action = isEnabled ? "bootstrap" : "bootout"
            process.arguments = [action, domain, item.plistURL.path]
            try? process.run()
            
            return true
        } catch {
            print("Gagal mengubah plist: \(error)")
            return false
        }
    }
}

class StartupViewModel: ObservableObject {
    @Published var items: [StartupItem] = []
    @Published var isScanning = false
    @Published var errorMessage: String? = nil
    @Published var showError: Bool = false
    @Published var showSuccessAlert = false
    
    func loadItems() {
        isScanning = true
        Task {
            let actor = StartupManagerActor()
            let fetched = await actor.scanStartupItems()
            DispatchQueue.main.async {
                self.items = fetched
                self.isScanning = false
            }
        }
    }
    
    func toggle(item: StartupItem, newValue: Bool) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].isEnabled = newValue
            
            Task {
                let actor = StartupManagerActor()
                let success = await actor.toggleItem(item, isEnabled: newValue)
                if !success {
                    // Revert UI on failure
                    DispatchQueue.main.async {
                        self.items[index].isEnabled = !newValue
                    }
                }
            }
        }
    }
}

// MARK: - Startup Manager View

struct StartupManagerView: View {
    @StateObject private var viewModel = StartupViewModel()
    @EnvironmentObject var globalState: GlobalAppState
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if viewModel.isScanning {
                    ProgressView().controlSize(.small)
                        .padding(.trailing, 4)
                    Text("Mencari agen startup...")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                } else {
                    Text("Pengelola Startup")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    viewModel.loadItems()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isScanning)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            // Content
            if viewModel.isScanning && viewModel.items.isEmpty {
                VStack {
                    Spacer()
                    ProgressView("Memindai LaunchAgents dan LaunchDaemons...")
                    Spacer()
                }
            } else if viewModel.items.isEmpty {
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "bolt.horizontal.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    Text("Startup Bersih!")
                        .font(.title)
                        .bold()
                    Text("Tidak ada agen tersembunyi yang berjalan.")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    let grouped = Dictionary(grouping: viewModel.items, by: { $0.type })
                    ForEach(["User Agent", "System Agent", "System Daemon"], id: \.self) { type in
                        if let typeItems = grouped[type], !typeItems.isEmpty {
                            Section(header: Text(LocalizedStringKey(type)).font(.headline).bold()) {
                                ForEach(typeItems) { item in
                                    StartupItemRow(item: item, viewModel: viewModel)
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            if viewModel.items.isEmpty {
                viewModel.loadItems()
            }
        }
        .onChange(of: viewModel.isScanning) { scanning in
            globalState.isAnyScanning = scanning
        }
    }
}

struct StartupItemRow: View {
    let item: StartupItem
    @ObservedObject var viewModel: StartupViewModel
    
    var body: some View {
        let binding = Binding<Bool>(
            get: { item.isEnabled },
            set: { newValue in
                viewModel.toggle(item: item, newValue: newValue)
            }
        )
        
        HStack {
            Image(systemName: item.canModify ? "app.badge.checkmark" : "lock.fill")
                .foregroundColor(item.canModify ? .blue : .secondary)
                .frame(width: 24)
            
            VStack(alignment: .leading) {
                Text(LocalizedStringKey(item.name))
                    .font(.body)
                    .foregroundColor(item.isEnabled ? .primary : .secondary)
                Text(item.plistURL.lastPathComponent)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if item.canModify {
                Toggle("", isOn: binding)
                    .toggleStyle(SwitchToggleStyle(tint: .green))
            } else {
                Text("Hanya Baca")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.trailing, 8)
            }
        }
        .padding(.vertical, 4)
    }
}


// MARK: - Daily Report Manager
import UserNotifications

class DailyReportManager: ObservableObject {
    static let shared = DailyReportManager()
    
    @AppStorage("dailySavedBytes") var dailySavedBytes: Double = 0
    @AppStorage("lastResetDate") var lastResetDate: Double = Date().timeIntervalSince1970
    
    // Health Metrics
    @Published var trashSize: Int64 = 0
    @Published var downloadsSize: Int64 = 0
    @Published var uptimeDays: Int = 0
    
    // For debugging / time machine feature
    @Published var forceNightMode: Bool = false
    
    @Published var isReportTime: Bool = false
    
    private var timer: Timer?
    
    init() {
        checkTimeAndResetIfNeeded()
        // Check every minute
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkTimeAndResetIfNeeded()
        }
    }
    
    func fetchHealthMetrics() {
        DispatchQueue.global(qos: .userInitiated).async {
            // Uptime
            let uptime = ProcessInfo.processInfo.systemUptime
            let days = Int(uptime / 86400)
            
            // Trash Size
            let trashURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
            var tSize: Int64 = 0
            if let enumerator = FileManager.default.enumerator(at: trashURL, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    if let rv = try? fileURL.resourceValues(forKeys: [.fileSizeKey]), let fs = rv.fileSize { tSize += Int64(fs) }
                }
            }
            
            // Downloads Size
            let downURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
            var dSize: Int64 = 0
            if let enumerator = FileManager.default.enumerator(at: downURL, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    if let rv = try? fileURL.resourceValues(forKeys: [.fileSizeKey]), let fs = rv.fileSize { dSize += Int64(fs) }
                }
            }
            
            DispatchQueue.main.async {
                self.uptimeDays = days
                self.trashSize = tSize
                self.downloadsSize = dSize
            }
        }
    }
    
    func checkTimeAndResetIfNeeded() {
        let now = Date()
        let calendar = Calendar.current
        
        let lastReset = Date(timeIntervalSince1970: lastResetDate)
        
        // If we crossed 6:00 AM since last reset, we reset
        // To simplify, if it's currently >= 6:00 AM and last reset was before today's 6:00 AM
        // Or if days have passed.
        
        var today6AMComponents = calendar.dateComponents([.year, .month, .day], from: now)
        today6AMComponents.hour = 6
        today6AMComponents.minute = 0
        today6AMComponents.second = 0
        
        if let today6AM = calendar.date(from: today6AMComponents) {
            if now >= today6AM && lastReset < today6AM {
                // Time to reset
                DispatchQueue.main.async {
                    self.dailySavedBytes = 0
                    self.lastResetDate = now.timeIntervalSince1970
                }
            } else if now < today6AM {
                // If it's 2 AM, today's 6 AM is in the future.
                // We check yesterday's 6 AM
                if let yesterday6AM = calendar.date(byAdding: .day, value: -1, to: today6AM) {
                    if lastReset < yesterday6AM {
                        DispatchQueue.main.async {
                            self.dailySavedBytes = 0
                            self.lastResetDate = now.timeIntervalSince1970
                        }
                    }
                }
            }
        }
        
        updateReportVisibility(now: now)
    }
    
    func updateReportVisibility(now: Date) {
        if forceNightMode {
            DispatchQueue.main.async {
                self.isReportTime = true
            }
            return
        }
        
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        
        // Report time is between 21:00 and 05:59
        let isNight = (hour >= 21 || hour < 6)
        
        DispatchQueue.main.async {
            self.isReportTime = isNight
        }
    }
    
    func addSavings(_ bytes: Int64) {
        DispatchQueue.main.async {
            self.dailySavedBytes += Double(bytes)
            let total = UserDefaults.standard.double(forKey: "totalSavedBytes")
            UserDefaults.standard.set(total + Double(bytes), forKey: "totalSavedBytes")
        }
    }
    
    func setupNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                self.scheduleDailyNotification()
            }
        }
    }
    
    private func scheduleDailyNotification() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        
        let content = UNMutableNotificationContent()
        content.title = "Laporan Harian Mac Anda Siap! 🌙"
        content.body = "Yuk, cek berapa banyak ruang yang berhasil Anda hemat hari ini sebelum tidur."
        content.sound = UNNotificationSound.default
        
        var dateComponents = DateComponents()
        dateComponents.hour = 21
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "dailyReport", content: content, trigger: trigger)
        
        center.add(request)
    }
}


// MARK: - Daily Report View

struct DailyReportView: View {
    @StateObject private var dailyManager = DailyReportManager.shared
    @State private var ramInfo = RAMManager.shared.getRAMInfo()
    @Environment(\.colorScheme) var colorScheme
    @Binding var selection: NavigationMode?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.purple)
                    Text("Malam! Kerja bagus hari ini.")
                        .font(.largeTitle)
                        .bold()
                    if dailyManager.dailySavedBytes > 0 {
                        Text("Anda berhasil membebaskan **\(Int64(dailyManager.dailySavedBytes).formattedSize)** ruang penyimpanan hari ini.")
                            .font(.title3)
                        
                        // Analogi
                        let gigabytes = dailyManager.dailySavedBytes / 1_000_000_000
                        if gigabytes > 1 {
                            Text("Itu setara dengan mengosongkan ruang untuk menyimpan **\(Int(gigabytes * 300)) foto resolusi tinggi** lho!")
                                .foregroundColor(.secondary)
                        } else {
                            Text("Itu setara dengan menyimpan puluhan lagu tambahan di Mac Anda!")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("Anda belum membuang sampah apa pun hari ini. Mac Anda masih bersih!")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 40)
                
                // Dashboard Grid
                let columns = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: 20) {
                    // Rapor Kesehatan Mac
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Rapor Kesehatan Mac")
                            .font(.headline)
                        
                        HStack {
                            Image(systemName: "internaldrive.fill")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text("Ruang Hard Disk")
                                    .font(.subheadline)
                                HStack(spacing: 4) {
                                    Text("Aman & Lega")
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                        
                        HStack {
                            Image(systemName: "memorychip.fill")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading) {
                                Text("Performa RAM")
                                    .font(.subheadline)
                                Text("Rata-rata sisa \(ramInfo.free.formattedSize)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    
                    // 2. Status Penyimpanan
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Status Penyimpanan")
                            .font(.headline)
                        
                        HStack {
                            Image(systemName: "trash.fill").foregroundColor(.red)
                            VStack(alignment: .leading) {
                                Text("Tempat Sampah (Trash)")
                                    .font(.subheadline)
                                if dailyManager.trashSize > 0 {
                                    Text(String(format: NSLocalizedString("Ada %@ sampah", comment: ""), dailyManager.trashSize.formattedSize))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    HStack(spacing: 4) {
                                        Text("Bersih")
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        HStack {
                            Image(systemName: "arrow.down.circle.fill").foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text("Folder Downloads")
                                    .font(.subheadline)
                                Text(String(format: NSLocalizedString("Berisi %@ file", comment: ""), dailyManager.downloadsSize.formattedSize))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    
                    // 3. Waktu Istirahat Mac
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Waktu Istirahat Mac")
                            .font(.headline)
                        
                        HStack {
                            Image(systemName: "clock.fill").foregroundColor(.purple)
                            VStack(alignment: .leading) {
                                Text("System Uptime")
                                    .font(.subheadline)
                                if dailyManager.uptimeDays >= 7 {
                                    Text(String(format: NSLocalizedString("Menyala %@ hari. Waktunya Restart!", comment: ""), String(dailyManager.uptimeDays)))
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                } else {
                                    HStack(spacing: 4) {
                                        Text(String(format: NSLocalizedString("Menyala %@ hari. Masih segar", comment: ""), String(dailyManager.uptimeDays)))
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    
                    // Lifetime Achievement
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Penghematan Total")
                            .font(.headline)
                        
                        HStack {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .font(.system(size: 30))
                            
                            VStack(alignment: .leading) {
                                let total = UserDefaults.standard.double(forKey: "totalSavedBytes")
                                Text(Int64(total).formattedSize)
                                    .font(.title2)
                                    .bold()
                                Text("Total sampah dibuang selamanya")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                
                // Saran Pintar
                VStack(alignment: .leading, spacing: 16) {
                    Text("Saran Pintar Untuk Besok")
                        .font(.headline)
                        .padding(.horizontal, 40)
                    
                    VStack(spacing: 0) {
                        SuggestionRow(
                            icon: "folder.badge.gearshape",
                            color: .blue,
                            title: "Rapikan Folder Downloads",
                            subtitle: "Shed mendeteksi banyak file berserakan. Ingin merapikannya ke dalam sub-folder?",
                            buttonText: "Buka Organizer",
                            action: { selection = .organizer }
                        )
                        Divider().padding(.leading, 60)
                        SuggestionRow(
                            icon: "bolt.horizontal.fill",
                            color: .green,
                            title: "Cek Aplikasi Startup",
                            subtitle: "Ada beberapa aplikasi yang ngotot menyala saat Mac dihidupkan.",
                            buttonText: "Kelola Startup",
                            action: { selection = .startup }
                        )
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    .padding(.horizontal, 40)
                }
                
                Spacer(minLength: 40)
            }
        }
        .background(colorScheme == .dark ? Color.black : Color(NSColor.windowBackgroundColor).opacity(0.8))
        .onAppear {
            ramInfo = RAMManager.shared.getRAMInfo()
            dailyManager.fetchHealthMetrics()
        }
    }
}

struct SuggestionRow: View {
    let icon: String
    let color: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let buttonText: LocalizedStringKey
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .bold()
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: action) {
                Text(buttonText)
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}



import QuickLookThumbnailing

struct SwipeCardItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let sizeString: String
    let categoryString: String
    let isDirectory: Bool
    let fileURL: URL?
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void
    
    static func == (lhs: SwipeCardItem, rhs: SwipeCardItem) -> Bool {
        return lhs.id == rhs.id
    }
}

struct SwipeCardView: View {
    let item: SwipeCardItem
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void
    
    @State private var offset: CGSize = .zero
    @State private var thumbnail: NSImage?
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 5)
            
            VStack {
                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 150)
                        .cornerRadius(8)
                } else {
                    Image(systemName: item.isDirectory ? "folder.fill" : (item.fileURL == nil ? "app.fill" : "doc.fill"))
                        .resizable()
                        .scaledToFit()
                        .frame(height: 100)
                        .foregroundColor(.secondary)
                }
                
                Text(item.title).font(.title3).bold().padding(.top, 10).multilineTextAlignment(.center)
                Text(item.subtitle).font(.caption).foregroundColor(.secondary).lineLimit(2).multilineTextAlignment(.center)
                
                Spacer()
                
                HStack {
                    Text(item.sizeString).foregroundColor(.orange).bold()
                    Spacer()
                    if !item.categoryString.isEmpty {
                        Text(item.categoryString)
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.orange.opacity(0.2)).cornerRadius(8).foregroundColor(.orange)
                    }
                }
            }
            .padding()
            
            if offset.width > 0 {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.green.opacity(0.2))
                Text("SIMPAN")
                    .font(.largeTitle).bold().foregroundColor(.green)
                    .rotationEffect(.degrees(-15))
            } else if offset.width < 0 {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.red.opacity(0.2))
                Text("HAPUS")
                    .font(.largeTitle).bold().foregroundColor(.red)
                    .rotationEffect(.degrees(15))
            }
        }
        .frame(width: 320, height: 420)
        .offset(x: offset.width, y: offset.height * 0.1)
        .rotationEffect(.degrees(Double(offset.width / 20)))
        .gesture(
            DragGesture()
                .onChanged { value in
                    offset = value.translation
                }
                .onEnded { value in
                    if value.translation.width > 120 {
                        withAnimation { offset = CGSize(width: 500, height: 0) }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onSwipeRight() }
                    } else if value.translation.width < -120 {
                        withAnimation { offset = CGSize(width: -500, height: 0) }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onSwipeLeft() }
                    } else {
                        withAnimation { offset = .zero }
                    }
                }
        )
        .onAppear {
            generateThumbnail()
        }
    }
    
    func generateThumbnail() {
        guard let url = item.fileURL else { return }
        let size = CGSize(width: 300, height: 300)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: NSScreen.main?.backingScaleFactor ?? 1.0, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateRepresentations(for: request) { (thumbnail, type, error) in
            if let img = thumbnail?.nsImage {
                DispatchQueue.main.async { self.thumbnail = img }
            }
        }
    }
}

struct SwipeCardContainer: View {
    let items: [SwipeCardItem]
    var isScanning: Bool = false
    @State private var currentIndex: Int = 0
    
    var body: some View {
        VStack {
            Spacer()
            ZStack {
                if currentIndex >= items.count {
                    VStack(spacing: 16) {
                        if isScanning {
                            ProgressView()
                                .controlSize(.large)
                            Text(LocalizedStringKey("Mencari item..."))
                                .font(.title)
                            Text(LocalizedStringKey("Harap tunggu, proses pemindaian masih berjalan."))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.green)
                            Text(LocalizedStringKey("Semua item telah diulas!"))
                                .font(.title)
                            Text(LocalizedStringKey("Jangan lupa klik tombol eksekusi di bawah jika ada yang dipilih."))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    let safeIndex = min(currentIndex, max(0, items.count - 1))
                    let topIndex = min(safeIndex + 3, items.count)
                    if safeIndex < topIndex {
                        ForEach((safeIndex..<topIndex).reversed(), id: \.self) { i in
                            SwipeCardView(item: items[i], onSwipeLeft: {
                                items[i].onSwipeLeft()
                                withAnimation { currentIndex += 1 }
                            }, onSwipeRight: {
                                items[i].onSwipeRight()
                                withAnimation { currentIndex += 1 }
                            })
                            .offset(y: CGFloat(i - safeIndex) * 10)
                            .scaleEffect(1.0 - CGFloat(i - safeIndex) * 0.05)
                            .disabled(i != safeIndex)
                        }
                    }
                }
            }
            .frame(height: 450)
            
            Spacer()
            
            if currentIndex < items.count {
                HStack(spacing: 60) {
                    Button(action: {
                        items[currentIndex].onSwipeLeft()
                        withAnimation { currentIndex += 1 }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .resizable()
                            .frame(width: 60, height: 60)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        items[currentIndex].onSwipeRight()
                        withAnimation { currentIndex += 1 }
                    }) {
                        Image(systemName: "heart.circle.fill")
                            .resizable()
                            .frame(width: 60, height: 60)
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 20)
            }
        }
    }
}



// MARK: - Quarantine Vault
class QuarantineVaultViewModel: ObservableObject {
    @Published var items: [QuarantineMetadata] = []
    
    var totalSelectedSize: Int64 {
        items.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
    }
    
    func loadItems() {
        self.items = QuarantineManager.shared.getQuarantinedItems().sorted { $0.quarantinedAt > $1.quarantinedAt }
    }
    
    func restoreSelected() {
        let selected = items.filter { $0.isSelected }
        for item in selected {
            do {
                try QuarantineManager.shared.restoreItem(item)
            } catch {
                print("Restore error: \(error)")
            }
        }
        loadItems()
    }
    
    func destroySelected() {
        let selected = items.filter { $0.isSelected }
        var sizePurged: Int64 = 0
        for item in selected {
            do {
                try QuarantineManager.shared.destroyItem(item)
                sizePurged += item.size
            } catch {
                print("Destroy error: \(error)")
            }
        }
        loadItems()
        DailyReportManager.shared.addSavings(sizePurged)
    }
}

struct QuarantineVaultView: View {
    @State private var showingConfirm = false
    @EnvironmentObject var globalState: GlobalAppState
    @StateObject private var viewModel = QuarantineVaultViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ruang Karantina")
                        .font(.largeTitle)
                        .bold()
                    Text("File yang diamankan sebelum dihapus permanen.")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: {
                    viewModel.loadItems()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            if viewModel.items.isEmpty {
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "shield.checkerboard")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    Text("Karantina Kosong")
                        .font(.title)
                        .bold()
                    Text("Tidak ada file yang sedang dikarantina.")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List(viewModel.items) { item in
                    HStack {
                        if let idx = viewModel.items.firstIndex(where: { $0.id == item.id }) {
                            Toggle("", isOn: $viewModel.items[idx].isSelected)
                        }
                        
                        Image(systemName: "doc.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 24))
                            .frame(width: 32)
                        
                        VStack(alignment: .leading) {
                            Text(item.fileName).font(.headline)
                            Text(item.originalPath).font(.caption).foregroundColor(.secondary).lineLimit(1)
                            Text("Dikarantina: \(item.quarantinedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                        
                        Spacer()
                        
                        Text(item.size.formattedSize)
                            .font(.subheadline)
                            .bold()
                    }
                    .padding(.vertical, 4)
                }
                
                // Footer
                HStack {
                    VStack(alignment: .leading) {
                        HStack(spacing: 4) {
                            Text("Terpilih:")
                            Text(viewModel.totalSelectedSize.formattedSize)
                        }
                        .font(.headline)
                    }
                    Spacer()
                    Button(action: {
                        viewModel.restoreSelected()
                    }) {
                        Text("Pulihkan (Restore)")
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                    .disabled(viewModel.totalSelectedSize == 0)
                    
                    Button(action: {
                        showingConfirm = true
                    }) {
                        Text("Hapus Permanen")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(viewModel.totalSelectedSize == 0)
                }
                .padding()
                .background(.regularMaterial)
            }
        }
        .alert(isPresented: $showingConfirm) {
            Alert(
                title: Text(LocalizedStringKey("Hapus Permanen")),
                message: Text(LocalizedStringKey("File yang dihapus permanen tidak dapat dikembalikan. Lanjutkan?")),
                primaryButton: .destructive(Text(LocalizedStringKey("Hapus"))) {
                    viewModel.destroySelected()
                },
                secondaryButton: .cancel(Text(LocalizedStringKey("Batal")))
            )
        }
        .onAppear {
            viewModel.loadItems()
        }
    }
}
import SwiftUI
import Foundation

@MainActor
class StorageAnalyzerViewModel: ObservableObject {
    @Published var totalDiskSpace: Int64 = 0
    @Published var freeDiskSpace: Int64 = 0
    
    @Published var categories: [StorageNode] = []
    
    // For drill down
    @Published var currentNode: StorageNode? = nil
    @Published var currentChildren: [StorageNode] = []
    @Published var isScanningChildren = false
    
    init() {
        fetchDiskSpace()
    }
    
    func fetchDiskSpace() {
        do {
            let path = "/"
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: path)
            if let total = attrs[.systemSize] as? NSNumber,
               let free = attrs[.systemFreeSize] as? NSNumber {
                self.totalDiskSpace = total.int64Value
                self.freeDiskSpace = free.int64Value
            }
        } catch {}
    }
    
    func scanRootCategories(force: Bool = false) {
        if !force {
            if !ScanCacheManager.shared.storageAnalyzerCache.isEmpty {
                self.categories = ScanCacheManager.shared.storageAnalyzerCache
                return
            }
            guard categories.isEmpty else { return }
        }
        
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        
        // Inisialisasi awal dengan size = -1 (sebagai tanda loading)
        let appsNode = StorageNode(id: UUID(), name: "Applications", url: nil, size: -1, isDirectory: true, iconName: "app.badge.fill", color: .blue)
        let docsNode = StorageNode(id: UUID(), name: "Documents", url: home.appendingPathComponent("Documents"), size: -1, isDirectory: true, iconName: "doc.text.fill", color: .orange)
        let photosNode = StorageNode(id: UUID(), name: "Photos", url: home.appendingPathComponent("Pictures"), size: -1, isDirectory: true, iconName: "photo.fill", color: .green)
        let downloadsNode = StorageNode(id: UUID(), name: "Downloads", url: home.appendingPathComponent("Downloads"), size: -1, isDirectory: true, iconName: "arrow.down.circle.fill", color: .purple)
        let systemNode = StorageNode(id: UUID(), name: "System Data & Other", url: nil, size: -1, isDirectory: true, iconName: "gearshape.fill", color: .gray)
        
        self.categories = [appsNode, docsNode, photosNode, downloadsNode, systemNode]
        
        // Progress tracking actor
        actor ProgressTracker {
            var completedCount = 0
            var sumOfCategories: Int64 = 0
            func addSize(_ size: Int64) -> Bool {
                sumOfCategories += size
                completedCount += 1
                return completedCount == 4
            }
            func getSum() -> Int64 { return sumOfCategories }
        }
        let tracker = ProgressTracker()
        
        func updateNode(name: String, size: Int64) {
            if let idx = self.categories.firstIndex(where: { $0.name == name }) {
                self.categories[idx].size = size
                self.categories.sort {
                    if $0.size == -1 && $1.size != -1 { return false }
                    if $1.size == -1 && $0.size != -1 { return true }
                    return $0.size > $1.size
                }
            }
        }
        
        func finishSystemData() {
            Task { @MainActor in
                let sum = await tracker.getSum()
                let used = self.totalDiskSpace - self.freeDiskSpace
                var systemSize = used - sum
                if systemSize < 0 { systemSize = 0 }
                updateNode(name: "System Data & Other", size: systemSize)
                ScanCacheManager.shared.storageAnalyzerCache = self.categories
            }
        }
        
        // Menjalankan tugas secara paralel (bersamaan) dengan aktor masing-masing agar tidak antre
        Task {
            let scanner = FolderSizeScannerActor()
            let size = await scanner.calculateSize(for: URL(fileURLWithPath: "/Applications")) + scanner.calculateSize(for: home.appendingPathComponent("Applications"))
            await MainActor.run {
                updateNode(name: "Applications", size: size)
            }
            if await tracker.addSize(size) { finishSystemData() }
        }
        Task {
            let scanner = FolderSizeScannerActor()
            let size = await scanner.calculateSize(for: home.appendingPathComponent("Documents"))
            await MainActor.run {
                updateNode(name: "Documents", size: size)
            }
            if await tracker.addSize(size) { finishSystemData() }
        }
        Task {
            let scanner = FolderSizeScannerActor()
            let size = await scanner.calculateSize(for: home.appendingPathComponent("Pictures"))
            await MainActor.run {
                updateNode(name: "Photos", size: size)
            }
            if await tracker.addSize(size) { finishSystemData() }
        }
        Task {
            let scanner = FolderSizeScannerActor()
            let size = await scanner.calculateSize(for: home.appendingPathComponent("Downloads"))
            await MainActor.run {
                updateNode(name: "Downloads", size: size)
            }
            if await tracker.addSize(size) { finishSystemData() }
        }
    }
    
    func scanChildren(for node: StorageNode) {
        // 'Other' has no url, it's abstract
        if node.name == "Other" { return }
        
        isScanningChildren = true
        currentChildren = []
        
        Task {
            let scanner = FolderSizeScannerActor()
            var urlsToScan: [URL] = []
            
            if node.name == "Applications" && node.url == nil {
                urlsToScan = [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
            } else if node.name == "System Data" && node.url == nil {
                urlsToScan = [URL(fileURLWithPath: "/System"), URL(fileURLWithPath: "/Library"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")]
            } else if let url = node.url {
                urlsToScan = [url]
            }
            
            let children = await scanner.scanChildren(of: urlsToScan)
            self.currentChildren = children
            self.isScanningChildren = false
        }
    }
}

struct StorageAnalyzerView: View {
    @StateObject private var viewModel = StorageAnalyzerViewModel()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(LocalizedStringKey("Storage"))
                    .font(.largeTitle)
                    .bold()
                Spacer()
                Button(action: {
                    viewModel.scanRootCategories(force: true)
                }) {
                    Label(LocalizedStringKey("Scan Ulang"), systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.categories.contains { $0.size == -1 }) // Disable during scan
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            ScrollView {
                VStack(spacing: 30) {
                    // Disk Map Visualization
                    DiskMapCard(viewModel: viewModel)
                    
                    Divider()
                    
                    // Categories
                    VStack(spacing: 12) {
                        ForEach(viewModel.categories) { node in
                            if node.name == "System Data & Other" {
                                StorageNodeRow(node: node, canDrillDown: false)
                            } else {
                                NavigationLink(destination: StorageNodeDetailView(node: node)) {
                                    StorageNodeRow(node: node, canDrillDown: true)
                                }
                                .buttonStyle(.plain)
                                .disabled(node.size == -1) // Disable clicking if still loading
                            }
                        }
                    }
                }
                .padding(30)
            }
        }
        .onAppear {
            viewModel.scanRootCategories()
        }
    }
}

struct DiskMapCard: View {
    @ObservedObject var viewModel: StorageAnalyzerViewModel
    @State private var animationProgress: CGFloat = 0.0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LocalizedStringKey("Macintosh HD"))
                .font(.headline)
            
            let used = viewModel.totalDiskSpace - viewModel.freeDiskSpace
            let percentage = viewModel.totalDiskSpace > 0 ? Double(used) / Double(viewModel.totalDiskSpace) : 0
            
            // Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 24)
                    
                    if !viewModel.categories.isEmpty {
                        HStack(spacing: 0) {
                            ForEach(viewModel.categories) { cat in
                                let catSize = cat.size < 0 ? 0 : cat.size
                                let catRatio = viewModel.totalDiskSpace > 0 ? Double(catSize) / Double(viewModel.totalDiskSpace) : 0
                                let catWidth = max(0, geo.size.width * CGFloat(catRatio))
                                if catWidth > 0 {
                                    Rectangle()
                                        .fill(cat.color)
                                        .frame(width: catWidth * animationProgress, height: 24)
                                        .help(Text(LocalizedStringKey(cat.name)) + Text(" (\(catSize.formattedSize))"))
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue)
                            .frame(width: max(0, geo.size.width * CGFloat(percentage) * animationProgress), height: 24)
                    }
                }
            }
            .frame(height: 24)
            
            HStack {
                Text("\(Int(percentage * 100))% Terpakai")
                    .bold()
                Spacer()
                Text("Used: \(used.formattedSize)")
                    .foregroundColor(.secondary)
                Text(" | ")
                    .foregroundColor(.secondary)
                Text("Available: \(viewModel.freeDiskSpace.formattedSize)")
                    .foregroundColor(.secondary)
            }
            .font(.subheadline)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .onAppear {
            animationProgress = 0.0
            withAnimation(.spring(response: 1.0, dampingFraction: 0.8, blendDuration: 0).delay(0.1)) {
                animationProgress = 1.0
            }
        }
    }
}

struct StorageNodeRow: View {
    let node: StorageNode
    let canDrillDown: Bool
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: node.iconName)
                .font(.title2)
                .foregroundColor(node.color)
                .frame(width: 30)
            
            Text(LocalizedStringKey(node.name))
                .font(.headline)
            
            Spacer()
            
            if node.size == -1 {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Menghitung...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                Text(node.size.formattedSize)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            if canDrillDown && node.size != -1 {
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(isHovered && canDrillDown && node.size != -1 ? Color.secondary.opacity(0.1) : Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
        .onHover { hover in
            isHovered = hover
        }
    }
}

struct StorageNodeDetailView: View {
    let node: StorageNode
    @StateObject private var viewModel = StorageAnalyzerViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(node.name)
                    .font(.title2)
                    .bold()
                Spacer()
                Text(node.size.formattedSize)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            if viewModel.isScanningChildren {
                Spacer()
                ProgressView("Menghitung ukuran folder...")
                Spacer()
            } else if viewModel.currentChildren.isEmpty {
                Spacer()
                Text("Kosong")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List(viewModel.currentChildren) { child in
                    if child.isDirectory {
                        NavigationLink(destination: StorageNodeDetailView(node: child)) {
                            StorageNodeRow(node: child, canDrillDown: true)
                        }
                    } else {
                        StorageNodeRow(node: child, canDrillDown: false)
                    }
                }
            }
        }
        .onAppear {
            viewModel.scanChildren(for: node)
        }
    }
}

// MARK: - Developer Cleanup Center
struct DeveloperCleanupItem: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let urls: [URL]
    let size: Int64
    var isSelected: Bool = false
}

actor DeveloperCleanupActor {
    private func getDirectorySize(url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var size: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey]), let fileSize = attrs.fileSize {
                size += Int64(fileSize)
            }
        }
        return size
    }
    
    func scanDeveloperFolders() -> AsyncStream<DeveloperCleanupItem> {
        AsyncStream { continuation in
            Task {
                let fm = FileManager.default
                let home = fm.homeDirectoryForCurrentUser
                
                // Targets
                let targets = [
                    ("Xcode DerivedData", "File hasil kompilasi Xcode", home.appendingPathComponent("Library/Developer/Xcode/DerivedData")),
                    ("Xcode iOS DeviceSupport", "File cache untuk simulator iOS", home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport")),
                    ("Xcode Archives", "Arsip build Xcode lama", home.appendingPathComponent("Library/Developer/Xcode/Archives")),
                    ("CocoaPods Cache", "Cache library CocoaPods", home.appendingPathComponent("Library/Caches/CocoaPods")),
                    ("NPM Cache", "Cache package Node.js", home.appendingPathComponent(".npm/_cacache")),
                    ("Gradle Cache", "Cache package Java/Android", home.appendingPathComponent(".gradle/caches"))
                ]
                
                for target in targets {
                    var exists = false
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: target.2.path, isDirectory: &isDir) {
                        exists = isDir.boolValue
                    }
                    
                    if exists {
                        let size = self.getDirectorySize(url: target.2)
                        if size > 0 {
                            let item = DeveloperCleanupItem(name: target.0, description: target.1, urls: [target.2], size: size, isSelected: false)
                            continuation.yield(item)
                        }
                    }
                }
                continuation.finish()
            }
        }
    }
}

@MainActor
class DeveloperCleanupViewModel: ObservableObject {
    @Published var items: [DeveloperCleanupItem] = []
    @Published var isScanning = false
    @Published var errorMessage: String? = nil
    @Published var showError: Bool = false
    
    var selectedSize: Int64 {
        items.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
    }
    
    func startScan() {
        isScanning = true
        items.removeAll()
        Task {
            let actor = DeveloperCleanupActor()
            let stream = await actor.scanDeveloperFolders()
            for await item in stream {
                self.items.append(item)
            }
            self.items.sort { $0.size > $1.size }
            self.isScanning = false
        }
    }
    
    func cleanSelected() {
        let workspace = NSWorkspace.shared
        let selected = items.filter { $0.isSelected }
        var urlsToTrash: [URL] = []
        for item in selected {
            urlsToTrash.append(contentsOf: item.urls)
        }
        
        guard !urlsToTrash.isEmpty else { return }
        
        workspace.recycle(urlsToTrash) { _, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Gagal menghapus: \(error.localizedDescription)")
                } else {
                    let saved = selected.reduce(0) { $0 + $1.size }
                    DailyReportManager.shared.addSavings(saved)
                    self.items.removeAll { $0.isSelected }
                }
            }
        }
    }
}

struct DeveloperCleanupView: View {
    @State private var showingConfirm = false
    @EnvironmentObject var globalState: GlobalAppState
    @StateObject private var viewModel = DeveloperCleanupViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Developer Cleanup Center")
                        .font(.largeTitle)
                        .bold()
                    Text("Hapus cache compiler, logs, dan derived data dengan aman.")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: {
                    viewModel.startScan()
                }) {
                    if viewModel.isScanning {
                        Text("Memindai...")
                    } else {
                        Text("Mulai Pindai")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.isScanning)
            }
            .padding(30)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            if viewModel.items.isEmpty && !viewModel.isScanning {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "terminal")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Pusat developer bersih. Tidak ada file cache yang ditemukan.")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach($viewModel.items) { $item in
                        HStack(spacing: 16) {
                            Toggle("", isOn: $item.isSelected)
                                .toggleStyle(.checkbox)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(LocalizedStringKey(item.name))
                                    .font(.headline)
                                Text(LocalizedStringKey(item.description))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(item.size.formattedSize)
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
                .listStyle(.inset)
                
                Divider()
                
                // Footer
                HStack {
                    Text("\(viewModel.items.filter { $0.isSelected }.count) dipilih")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("Total: \(viewModel.selectedSize.formattedSize)")
                        .font(.title3)
                        .bold()
                    
                    Button(action: {
                        showingConfirm = true
                    }) {
                        Text("Hapus Terpilih")
                            .bold()
                            .padding(.horizontal, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)
                    .disabled(viewModel.selectedSize == 0)
                }
                .padding(20)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .alert(isPresented: $showingConfirm) {
            Alert(
                title: Text(LocalizedStringKey("Hapus Cache")),
                message: Text(LocalizedStringKey("Apakah Anda yakin ingin menghapus cache developer terpilih?")),
                primaryButton: .destructive(Text(LocalizedStringKey("Hapus"))) {
                    viewModel.cleanSelected()
                },
                secondaryButton: .cancel(Text(LocalizedStringKey("Batal")))
            )
        }
        .onAppear {
            if viewModel.items.isEmpty && !viewModel.isScanning {
                viewModel.startScan()
            }
        }
        .onChange(of: viewModel.isScanning) { newValue in
            globalState.isAnyScanning = newValue
        }
    }
}
