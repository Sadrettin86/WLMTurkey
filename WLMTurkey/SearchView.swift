import SwiftUI

// MARK: - Search Result Model
struct SearchResult: Identifiable {
    let id: String // Wikidata QID
    let label: String
    let description: String
    let hasImage: Bool
    let imageUrl: String?
    let latitude: Double?
    let longitude: Double?
    // Detail properties
    let instanceOf: String?
    let adminEntity: String?
    let heritageDesig: String?
    let architect: String?
    let archStyle: String?
}

// MARK: - Search ViewModel
@Observable
class SearchViewModel {
    var results: [SearchResult] = []
    var isSearching = false
    var errorMessage: String?
    var hasSearched = false // true after at least one completed search
    private var searchTask: URLSessionDataTask?
    private var debounceTimer: Timer?

    func search(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        debounceTimer?.invalidate()
        searchTask?.cancel()

        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            hasSearched = false
            return
        }

        // Show searching state immediately and clear previous results
        isSearching = true
        hasSearched = false
        results = []
        errorMessage = nil

        // Debounce: wait 0.4s before firing the actual request
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.executeSearch(query: trimmed)
        }
    }

    /// Sanitize input for SPARQL injection prevention
    private func sanitizeSPARQL(_ input: String) -> String {
        input.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
    }

    private func executeSearch(query: String) {
        let escaped = sanitizeSPARQL(query)
        let l = AppSettings.shared.l
        isSearching = true
        errorMessage = nil

        let lang = AppSettings.shared.language
        let langFallback = lang == "tr" ? "tr,en" : "en,tr"
        let sparql = """
        SELECT ?item ?itemLabel ?itemDescription
               (SAMPLE(?lat_) AS ?lat) (SAMPLE(?lon_) AS ?lon)
               (SAMPLE(?image_) AS ?image)
               (SAMPLE(?typeLabel_) AS ?typeLabel)
               (SAMPLE(?adminLabel_) AS ?adminLabel)
               (SAMPLE(?heritageLabel_) AS ?heritageLabel)
               (SAMPLE(?architectLabel_) AS ?architectLabel)
               (SAMPLE(?styleLabel_) AS ?styleLabel)
        WHERE {
          ?item wdt:P17 wd:Q43;
                wdt:P11729 [];
                rdfs:label ?label.
          FILTER(LANG(?label) = "tr")
          FILTER(CONTAINS(LCASE(?label), "\(escaped.lowercased())"))
          OPTIONAL {
            ?item p:P625 [ psv:P625 [ wikibase:geoLatitude ?lat_; wikibase:geoLongitude ?lon_ ] ].
          }
          OPTIONAL { ?item wdt:P18 ?image_. }
          OPTIONAL { ?item wdt:P31 ?type_. ?type_ rdfs:label ?typeLabel_. FILTER(LANG(?typeLabel_) = "\(lang)") }
          OPTIONAL { ?item wdt:P131 ?admin_. ?admin_ rdfs:label ?adminLabel_. FILTER(LANG(?adminLabel_) = "\(lang)") }
          OPTIONAL { ?item wdt:P5816 ?heritage_. ?heritage_ rdfs:label ?heritageLabel_. FILTER(LANG(?heritageLabel_) = "\(lang)") }
          OPTIONAL { ?item wdt:P84 ?architect_. ?architect_ rdfs:label ?architectLabel_. FILTER(LANG(?architectLabel_) = "\(lang)") }
          OPTIONAL { ?item wdt:P149 ?style_. ?style_ rdfs:label ?styleLabel_. FILTER(LANG(?styleLabel_) = "\(lang)") }
          SERVICE wikibase:label { bd:serviceParam wikibase:language "\(langFallback)". }
        }
        GROUP BY ?item ?itemLabel ?itemDescription
        LIMIT 50
        """

        var components = URLComponents(string: "https://query.wikidata.org/sparql")!
        components.queryItems = [
            URLQueryItem(name: "query", value: sparql),
            URLQueryItem(name: "format", value: "json")
        ]

        guard let url = components.url else {
            isSearching = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("WLMTurkey/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        searchTask = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isSearching = false

                if let error = error as? URLError, error.code == .cancelled {
                    return
                }

                if let error = error {
                    self.errorMessage = "\(l.errorPrefix): \(error.localizedDescription)"
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let resultsObj = json["results"] as? [String: Any],
                      let bindings = resultsObj["bindings"] as? [[String: Any]] else {
                    self.errorMessage = l.dataUnavailable
                    return
                }

                self.hasSearched = true
                self.results = bindings.compactMap { b in
                    guard let itemVal = (b["item"] as? [String: Any])?["value"] as? String else { return nil }
                    let qid = itemVal.components(separatedBy: "/").last ?? ""
                    let label = (b["itemLabel"] as? [String: Any])?["value"] as? String ?? l.unnamed
                    let desc = (b["itemDescription"] as? [String: Any])?["value"] as? String ?? ""
                    let imageUrl = (b["image"] as? [String: Any])?["value"] as? String
                    let lat = (b["lat"] as? [String: Any])?["value"] as? String
                    let lon = (b["lon"] as? [String: Any])?["value"] as? String
                    let typeLabel = (b["typeLabel"] as? [String: Any])?["value"] as? String
                    let adminLabel = (b["adminLabel"] as? [String: Any])?["value"] as? String
                    let heritageLabel = (b["heritageLabel"] as? [String: Any])?["value"] as? String
                    let architectLabel = (b["architectLabel"] as? [String: Any])?["value"] as? String
                    let styleLabel = (b["styleLabel"] as? [String: Any])?["value"] as? String

                    return SearchResult(
                        id: qid,
                        label: label,
                        description: desc,
                        hasImage: imageUrl != nil,
                        imageUrl: imageUrl,
                        latitude: lat.flatMap { Double($0) },
                        longitude: lon.flatMap { Double($0) },
                        instanceOf: typeLabel,
                        adminEntity: adminLabel,
                        heritageDesig: heritageLabel,
                        architect: architectLabel,
                        archStyle: styleLabel
                    )
                }
            }
        }
        searchTask?.resume()
    }
}

// MARK: - Search History
@Observable
class SearchHistory {
    static let shared = SearchHistory()
    private static let key = "search_history"
    private static let maxItems = 20

    var items: [String] = []

    private init() {
        items = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
    }

    func add(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        items.removeAll { $0.lowercased() == trimmed.lowercased() }
        items.insert(trimmed, at: 0)
        if items.count > Self.maxItems {
            items = Array(items.prefix(Self.maxItems))
        }
        UserDefaults.standard.set(items, forKey: Self.key)
    }

    func remove(_ query: String) {
        items.removeAll { $0 == query }
        UserDefaults.standard.set(items, forKey: Self.key)
    }

    func clearAll() {
        items = []
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}

// MARK: - Search View
struct SearchView: View {
    var onShowOnMap: ((Double, Double) -> Void)?
    @Environment(AppSettings.self) private var settings
    @State private var vm = SearchViewModel()
    @State private var searchText = ""
    @State private var uploadMonument: UploadMonumentInfo?
    @State private var history = SearchHistory.shared

    var body: some View {
        let l = settings.l

        NavigationStack {
            Group {
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if history.items.isEmpty {
                        // No history — show hint
                        VStack(spacing: 16) {
                            Spacer()
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 48))
                                .foregroundStyle(.quaternary)
                            Text(l.searchHint)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(l.searchSubhint)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                            Spacer()
                        }
                    } else {
                        // Show search history
                        List {
                            Section {
                                ForEach(history.items, id: \.self) { term in
                                    Button {
                                        searchText = term
                                        vm.search(query: term)
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "clock.arrow.circlepath")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                            Text(term)
                                                .font(.subheadline)
                                                .foregroundStyle(.primary)
                                            Spacer()
                                            Image(systemName: "arrow.up.left")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            history.remove(term)
                                        } label: {
                                            Label(l.isTR ? "Sil" : "Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            } header: {
                                Text(l.recentSearches)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .textCase(nil)
                            }
                        }
                        .listStyle(.plain)
                    }
                } else if let error = vm.errorMessage {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 36))
                            .foregroundStyle(.red.opacity(0.6))
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        Button(l.retryButton) {
                            vm.search(query: searchText)
                        }
                        .font(.subheadline)
                        Spacer()
                    }
                } else if vm.isSearching && vm.results.isEmpty {
                    // Searching, no results yet
                    VStack(spacing: 12) {
                        Spacer()
                        ProgressView()
                            .controlSize(.large)
                        Text(l.searching)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(l.searchingFor(searchText.trimmingCharacters(in: .whitespacesAndNewlines)))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                } else if vm.results.isEmpty && !vm.isSearching && vm.hasSearched {
                    // Search completed, no results found
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 36))
                            .foregroundStyle(.quaternary)
                        Text(l.noResults)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(l.noResultsFor(searchText.trimmingCharacters(in: .whitespacesAndNewlines)))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                } else if vm.results.isEmpty && !vm.hasSearched {
                    // Typed but not enough characters or waiting for debounce
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "character.cursor.ibeam")
                            .font(.system(size: 36))
                            .foregroundStyle(.quaternary)
                        Text(l.keepTyping)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(vm.results) { result in
                            SearchResultRow(result: result, onUploadTap: {
                                var thumbUrl = ""
                                if let imgUrl = result.imageUrl,
                                   let filename = imgUrl.components(separatedBy: "/").last {
                                    thumbUrl = "https://commons.wikimedia.org/wiki/Special:FilePath/\(filename)?width=120"
                                }
                                uploadMonument = UploadMonumentInfo(
                                    name: result.label,
                                    wikidataId: result.id,
                                    imageUrl: thumbUrl,
                                    instanceOf: result.instanceOf,
                                    adminEntity: result.adminEntity,
                                    heritageDesig: result.heritageDesig,
                                    architect: result.architect,
                                    archStyle: result.archStyle
                                )
                            }, onShowOnMap: result.latitude != nil && result.longitude != nil ? {
                                onShowOnMap?(result.latitude!, result.longitude!)
                            } : nil)
                        }

                        // Show searching indicator at end of list while updating
                        if vm.isSearching {
                            HStack(spacing: 8) {
                                Spacer()
                                ProgressView()
                                    .controlSize(.small)
                                Text(l.updating)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(l.searchTitle)
            .searchable(text: $searchText, prompt: l.searchPrompt)
            .onChange(of: searchText) { _, newValue in
                vm.search(query: newValue)
            }
            .onChange(of: vm.hasSearched) { _, searched in
                if searched && !vm.results.isEmpty {
                    history.add(searchText)
                }
            }
            .sheet(item: Binding<UploadMonumentInfo?>(
                get: { uploadMonument },
                set: { uploadMonument = $0 }
            )) { info in
                UploadSheetView(monument: info)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

// MARK: - Search Result Row
struct SearchResultRow: View {
    @Environment(AppSettings.self) private var settings
    let result: SearchResult
    let onUploadTap: () -> Void
    var onShowOnMap: (() -> Void)?

    var body: some View {
        let l = settings.l

        HStack(spacing: 12) {
            // Thumbnail
            if let imgUrl = result.imageUrl,
               let filename = imgUrl.components(separatedBy: "/").last {
                let thumbUrl = "https://commons.wikimedia.org/wiki/Special:FilePath/\(filename)?width=120"
                AsyncImage(url: URL(string: thumbUrl)) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else if phase.error != nil {
                        photoPlaceholder
                    } else {
                        ProgressView()
                            .frame(width: 56, height: 56)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                photoPlaceholder
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(result.label)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                // Detail info line (type · admin)
                if let type = result.instanceOf {
                    HStack(spacing: 4) {
                        Text(type)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let admin = result.adminEntity {
                            Text("·")
                                .font(.caption)
                                .foregroundStyle(.quaternary)
                            Text(admin)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                } else if let admin = result.adminEntity {
                    Text(admin)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if !result.description.isEmpty {
                    Text(result.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                // Extra details
                if result.architect != nil || result.archStyle != nil || result.heritageDesig != nil {
                    HStack(spacing: 6) {
                        if let arch = result.architect {
                            Label(arch, systemImage: "person.fill")
                                .font(.caption2)
                                .foregroundStyle(.purple)
                                .lineLimit(1)
                        }
                        if let style = result.archStyle {
                            Label(style, systemImage: "paintpalette.fill")
                                .font(.caption2)
                                .foregroundStyle(.teal)
                                .lineLimit(1)
                        }
                    }
                }

                if let heritage = result.heritageDesig, !heritage.isEmpty {
                    Text(heritage)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(heritageColor(heritage))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Show on map button
            if result.latitude != nil && result.longitude != nil, let onShowOnMap {
                Button {
                    onShowOnMap()
                } label: {
                    Image(systemName: "map.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }

            // Upload button
            Button {
                onUploadTap()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func heritageColor(_ value: String) -> Color {
        let lower = value.lowercased()
        // Negative: destroyed, ruined, submerged, partially destroyed, location unknown
        let negative = ["yıkılmış", "harabe", "kısmen yıkılmış", "yok olmuş", "sular altında",
                        "belirsiz", "temelleri kalmış", "kazı çalışması yapılmamış",
                        "destroyed", "ruin", "partially", "submerged", "unknown", "unexcavated",
                        "foundations remain"]
        if negative.contains(where: { lower.contains($0) }) {
            return .red
        }
        return .green
    }

    private var photoPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray5))
            Image(systemName: "building.columns")
                .font(.title3)
                .foregroundStyle(.quaternary)
        }
        .frame(width: 56, height: 56)
    }
}

