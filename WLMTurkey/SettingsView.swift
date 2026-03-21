import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var cacheSize: String = "..."
    @State private var showClearConfirm = false
    @State private var monumentCount: Int = 0

    var body: some View {
        @Bindable var settings = settings
        let l = settings.l

        List {
            // Appearance
            Section(l.appearance) {
                Picker(l.appearance, selection: $settings.theme) {
                    Text(l.themeSystem).tag("system")
                    Text(l.themeLight).tag("light")
                    Text(l.themeDark).tag("dark")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            // Language
            Section(l.languageTitle) {
                Picker(l.languageTitle, selection: $settings.language) {
                    Text("Türkçe").tag("tr")
                    Text("English").tag("en")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            // Default License (B)
            Section {
                Picker(l.isTR ? "Varsayılan Lisans" : "Default License", selection: $settings.defaultLicense) {
                    Text("CC BY-SA 4.0").tag("CC BY-SA 4.0")
                    Text("CC BY 4.0").tag("CC BY 4.0")
                    Text("CC0 1.0").tag("CC0 1.0")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text(l.isTR ? "Varsayılan Lisans" : "Default License")
            } footer: {
                Text(l.isTR
                     ? "Fotoğraf yüklerken bu lisans otomatik seçilir"
                     : "This license will be pre-selected when uploading photos")
            }

            // Data Management
            Section {
                Button(role: .destructive) {
                    SearchHistory.shared.clearAll()
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                        Text(l.clearSearchHistory)
                    }
                }
                .disabled(SearchHistory.shared.items.isEmpty)

                // Cache (C)
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text(l.isTR ? "Önbelleği temizle" : "Clear cache")
                        Spacer()
                        Text(cacheSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .confirmationDialog(
                    l.isTR ? "Önbellek temizlensin mi?" : "Clear cache?",
                    isPresented: $showClearConfirm,
                    titleVisibility: .visible
                ) {
                    Button(l.isTR ? "Temizle" : "Clear", role: .destructive) {
                        clearCache()
                    }
                } message: {
                    Text(l.isTR
                         ? "İndirilen harita verileri ve OSM sınırları silinecek. Gömülü anıt verileri korunur."
                         : "Downloaded map data and OSM boundaries will be deleted. Bundled monument data is preserved.")
                }
            } header: {
                Text(l.isTR ? "Veri" : "Data")
            }

            // System settings
            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "gear")
                        Text(l.isTR ? "Sistem Ayarları" : "System Settings")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // Data Source (G)
            Section {
                HStack {
                    Text(l.isTR ? "Veri kaynağı" : "Data source")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(l.isTR ? "Vikiveri" : "Wikidata")
                }
                .font(.caption)

                HStack {
                    Text(l.isTR ? "Anıt sayısı" : "Monuments")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(NumberFormatter.localizedString(from: NSNumber(value: monumentCount), number: .decimal))
                }
                .font(.caption)

                if let version = UserDefaults.standard.string(forKey: "monuments_remote_version") {
                    HStack {
                        Text(l.isTR ? "Veri sürümü" : "Data version")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(version)
                    }
                    .font(.caption)
                }
            } header: {
                Text(l.isTR ? "Veri Kaynağı" : "Data Source")
            }

            // About (E)
            Section {
                HStack {
                    Text(l.isTR ? "Sürüm" : "Version")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(appVersion)
                }
                .font(.caption)

                HStack {
                    Text(l.isTR ? "Geliştirici" : "Developer")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Adem Özcan")
                }
                .font(.caption)

                Button {
                    if let url = URL(string: "https://commons.wikimedia.org/w/index.php?title=Commons_talk:Wiki_Loves_Monuments_in_Turkey") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                        Text(l.isTR ? "Geri bildirim gönder" : "Send feedback")
                    }
                    .font(.caption)
                }

                Button {
                    if let url = URL(string: "https://github.com") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                        Text(l.isTR ? "Açık kaynak lisansları" : "Open source licenses")
                    }
                    .font(.caption)
                }
            } header: {
                Text(l.isTR ? "Hakkında" : "About")
            }
        }
        .navigationTitle(l.settings)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            calculateCacheSize()
            monumentCount = MonumentStore.load().count
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func calculateCacheSize() {
        DispatchQueue.global(qos: .utility).async {
            var total: Int64 = 0
            let fm = FileManager.default
            let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!

            // Remote monuments cache
            let remoteFile = docs.appendingPathComponent("monuments_remote.json")
            if let attrs = try? fm.attributesOfItem(atPath: remoteFile.path),
               let size = attrs[.size] as? Int64 {
                total += size
            }

            // OSM boundaries cache
            let osmFile = docs.appendingPathComponent("osm_boundaries_cache.json")
            if let attrs = try? fm.attributesOfItem(atPath: osmFile.path),
               let size = attrs[.size] as? Int64 {
                total += size
            }

            let formatted = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            DispatchQueue.main.async {
                cacheSize = formatted
            }
        }
    }

    private func clearCache() {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!

        // Delete remote monuments cache
        try? fm.removeItem(at: docs.appendingPathComponent("monuments_remote.json"))
        UserDefaults.standard.removeObject(forKey: "monuments_last_remote_check")
        UserDefaults.standard.removeObject(forKey: "monuments_remote_version")

        // Delete OSM boundaries cache
        try? fm.removeItem(at: docs.appendingPathComponent("osm_boundaries_cache.json"))

        // Recalculate
        calculateCacheSize()
    }
}
