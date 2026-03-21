import SwiftUI
import CoreLocation

// MARK: - Commons Photo Model
struct CommonsPhoto: Identifiable {
    let id: String // pageid as string
    let title: String // File:xxx.jpg
    let thumbUrl: String
    let fullUrl: String
    let wikidataId: String? // QID extracted from {{on Wikidata|Qxxx}}
    let monumentLabel: String?
    let latitude: Double?
    let longitude: Double?
    let uploadDate: Date?
    let uploaderName: String?
    let dateTaken: String? // EXIF DateTimeOriginal
}

// MARK: - Monument needing photo
struct MonumentNeedingPhoto: Identifiable {
    let id: String // QID
    let name: String
    let description: String
    let latitude: Double?
    let longitude: Double?
    var distance: Double? // in meters, computed client-side
    let instanceOf: String?
    let adminEntity: String?
    let heritageDesig: String?
    let architect: String?
    let archStyle: String?
}

// MARK: - Photos ViewModel
@Observable
class PhotosViewModel {
    // Recent photos
    var photos: [CommonsPhoto] = []
    var isLoading = false
    var errorMessage: String?
    var hasMore = true
    private var currentTask: URLSessionDataTask?

    // Category total count
    var categoryTotalCount: Int = 0

    // Monuments needing photos
    var needingPhotos: [MonumentNeedingPhoto] = []
    var isLoadingNeeding = false
    var needingError: String?
    var needingStats: (total: Int, withPhoto: Int)? = nil
    var isRefreshingNeeding = false
    private var needingTask: URLSessionDataTask?
    private var removedQIDs: Set<String> = []

    // MARK: - Dual category support
    private static let category2026 = "Category:Images from Wiki Loves Monuments 2026 in Turkey"
    private static let category2025 = "Category:Images from Wiki Loves Monuments 2025 in Turkey"
    private var activeCategory: String = PhotosViewModel.category2026
    private var fallbackUsed = false
    private var continueToken2026: String?
    private var continueToken2025: String?
    private var hasMore2026 = true
    private var hasMore2025 = true

    // MARK: - Fetch recent from category
    func fetchRecent(reset: Bool = false) {
        if reset {
            photos = []
            continueToken2026 = nil
            continueToken2025 = nil
            hasMore2026 = true
            hasMore2025 = true
            activeCategory = Self.category2026
            fallbackUsed = false
            hasMore = true
        }

        guard hasMore, !isLoading else { return }
        isLoading = true
        errorMessage = nil

        let currentCategory = activeCategory
        let currentToken: String? = (currentCategory == Self.category2026) ? continueToken2026 : continueToken2025

        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "categorymembers"),
            URLQueryItem(name: "cmtitle", value: currentCategory),
            URLQueryItem(name: "cmtype", value: "file"),
            URLQueryItem(name: "cmsort", value: "timestamp"),
            URLQueryItem(name: "cmdir", value: "desc"),
            URLQueryItem(name: "cmlimit", value: "40"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
        ]

        if let token = currentToken {
            queryItems.append(URLQueryItem(name: "cmcontinue", value: token))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("WLMTurkey/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let l = AppSettings.shared.l
        currentTask?.cancel()
        currentTask = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isLoading = false

                if let error = error as? URLError, error.code == .cancelled { return }
                if let error = error {
                    self.errorMessage = "\(l.errorPrefix): \(error.localizedDescription)"
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let query = json["query"] as? [String: Any],
                      let members = query["categorymembers"] as? [[String: Any]] else {
                    self.errorMessage = l.dataUnavailable
                    return
                }

                // Update continue token for current category
                if let cont = json["continue"] as? [String: Any],
                   let cmcont = cont["cmcontinue"] as? String {
                    if currentCategory == Self.category2026 {
                        self.continueToken2026 = cmcont
                    } else {
                        self.continueToken2025 = cmcont
                    }
                } else {
                    if currentCategory == Self.category2026 {
                        self.hasMore2026 = false
                    } else {
                        self.hasMore2025 = false
                    }
                }

                let pageIds = members.compactMap { m -> Int? in
                    m["pageid"] as? Int
                }

                // If 2026 category is empty/exhausted and we haven't tried 2025 yet, switch
                if currentCategory == Self.category2026 && pageIds.isEmpty && !self.fallbackUsed {
                    self.activeCategory = Self.category2025
                    self.fallbackUsed = true
                    self.isLoading = false
                    self.fetchRecent()
                    return
                }

                // If 2026 had some results but is now exhausted, continue with 2025
                if currentCategory == Self.category2026 && !self.hasMore2026 && !self.fallbackUsed {
                    self.activeCategory = Self.category2025
                    self.fallbackUsed = true
                }

                // Update overall hasMore
                if self.activeCategory == Self.category2026 {
                    self.hasMore = self.hasMore2026 || self.hasMore2025
                } else {
                    self.hasMore = self.hasMore2025
                }

                if pageIds.isEmpty { return }
                self.fetchImageInfo(pageIds: pageIds)
            }
        }
        currentTask?.resume()
    }

    // MARK: - Fetch monuments needing photos (from local CSV data)
    func fetchNeedingPhotos(lat: Double, lon: Double) {
        guard !isLoadingNeeding else { return }
        isLoadingNeeding = true
        needingError = nil

        let allMonuments = MonumentStore.load()
        let userLocation = CLLocation(latitude: lat, longitude: lon)

        let results = allMonuments
            .filter { !$0.hasPhoto && !removedQIDs.contains($0.wikidataId) }
            .map { m -> (Monument, Double) in
                let dist = userLocation.distance(from: CLLocation(latitude: m.latitude, longitude: m.longitude))
                return (m, dist)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(30)

        needingPhotos = results.map { m, dist in
            MonumentNeedingPhoto(
                id: m.wikidataId,
                name: m.name,
                description: "",
                latitude: m.latitude,
                longitude: m.longitude,
                distance: dist,
                instanceOf: m.instanceOf,
                adminEntity: m.adminEntity,
                heritageDesig: m.heritageDesig,
                architect: m.architect,
                archStyle: m.archStyle
            )
        }

        isLoadingNeeding = false
    }

    // MARK: - Remove monument from needing list (after P18 set)
    func removeFromNeeding(qid: String) {
        removedQIDs.insert(qid)
        needingPhotos.removeAll { $0.id == qid }
    }

    // MARK: - Pull-to-refresh: validate via SPARQL which ones still need photos
    func refreshNeedingPhotos(lat: Double, lon: Double) {
        guard !isRefreshingNeeding else { return }

        let qids = needingPhotos.map { $0.id }
        guard !qids.isEmpty else {
            fetchNeedingPhotos(lat: lat, lon: lon)
            return
        }

        isRefreshingNeeding = true

        // Check which of our listed QIDs now have P18
        let values = qids.map { "wd:\($0)" }.joined(separator: " ")
        let sparql = """
        SELECT ?item WHERE {
          VALUES ?item { \(values) }
          ?item wdt:P18 [].
        }
        """

        var components = URLComponents(string: "https://query.wikidata.org/sparql")!
        components.queryItems = [
            URLQueryItem(name: "query", value: sparql),
            URLQueryItem(name: "format", value: "json"),
        ]

        guard let url = components.url else {
            isRefreshingNeeding = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("WLMTurkey/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        needingTask?.cancel()
        needingTask = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isRefreshingNeeding = false

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let resultsObj = json["results"] as? [String: Any],
                      let bindings = resultsObj["bindings"] as? [[String: Any]] else {
                    // On error, just reload from CSV
                    self.fetchNeedingPhotos(lat: lat, lon: lon)
                    return
                }

                // Extract QIDs that NOW have photos
                let nowHavePhoto = Set(bindings.compactMap { b -> String? in
                    guard let uri = (b["item"] as? [String: Any])?["value"] as? String else { return nil }
                    return uri.components(separatedBy: "/").last
                })

                // Remove them from the list
                for qid in nowHavePhoto {
                    self.removedQIDs.insert(qid)
                }
                self.needingPhotos.removeAll { nowHavePhoto.contains($0.id) }

                // Refill to 30 from CSV if we removed some
                if self.needingPhotos.count < 30 {
                    self.fetchNeedingPhotos(lat: lat, lon: lon)
                }
            }
        }
        needingTask?.resume()
    }

    // MARK: - Fetch image info for page IDs
    private func fetchImageInfo(pageIds: [Int]) {
        let idsStr = pageIds.map { String($0) }.joined(separator: "|")

        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "pageids", value: idsStr),
            URLQueryItem(name: "prop", value: "imageinfo|coordinates|revisions"),
            URLQueryItem(name: "iiprop", value: "url|timestamp|user|extmetadata"),
            URLQueryItem(name: "iiurlwidth", value: "400"),
            URLQueryItem(name: "rvprop", value: "content"),
            URLQueryItem(name: "rvslots", value: "main"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
        ]

        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.setValue("WLMTurkey/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            DispatchQueue.main.async {
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let query = json["query"] as? [String: Any],
                      let pages = query["pages"] as? [[String: Any]] else {
                    return
                }

                let parsed = self.parsePages(pages)
                self.photos.append(contentsOf: parsed)
            }
        }.resume()
    }

    // MARK: - Parse pages response
    private func parsePages(_ pages: [[String: Any]]) -> [CommonsPhoto] {
        return pages.compactMap { page -> CommonsPhoto? in
            guard let pageid = page["pageid"] as? Int,
                  let title = page["title"] as? String else { return nil }

            let imageinfo = (page["imageinfo"] as? [[String: Any]])?.first
            let thumbUrl = imageinfo?["thumburl"] as? String ?? ""
            let fullUrl = imageinfo?["url"] as? String ?? ""
            let uploaderName = imageinfo?["user"] as? String

            var uploadDate: Date?
            if let timestamp = imageinfo?["timestamp"] as? String {
                let fmt = ISO8601DateFormatter()
                uploadDate = fmt.date(from: timestamp)
            }

            var lat: Double?
            var lon: Double?
            if let coords = page["coordinates"] as? [[String: Any]], let first = coords.first {
                lat = first["lat"] as? Double
                lon = first["lon"] as? Double
            }

            // Extract date taken from EXIF extmetadata
            var dateTaken: String?
            if let extmetadata = imageinfo?["extmetadata"] as? [String: Any],
               let dto = extmetadata["DateTimeOriginal"] as? [String: Any],
               let value = dto["value"] as? String {
                let cleaned = value.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    dateTaken = cleaned
                }
            }

            var wikidataId: String?
            if let revisions = page["revisions"] as? [[String: Any]],
               let rev = revisions.first,
               let slots = rev["slots"] as? [String: Any],
               let main = slots["main"] as? [String: Any],
               let content = main["content"] as? String {
                wikidataId = extractQID(from: content)
            }

            // Look up monument label from bundled data
            var monumentLabel: String?
            if let qid = wikidataId {
                monumentLabel = MonumentStore.labelForQID(qid)
            }

            return CommonsPhoto(
                id: String(pageid),
                title: title,
                thumbUrl: thumbUrl,
                fullUrl: fullUrl,
                wikidataId: wikidataId,
                monumentLabel: monumentLabel,
                latitude: lat,
                longitude: lon,
                uploadDate: uploadDate,
                uploaderName: uploaderName,
                dateTaken: dateTaken
            )
        }
    }

    // MARK: - Extract QID from wikitext
    private func extractQID(from wikitext: String) -> String? {
        let patterns = [
            "\\{\\{[Oo]n [Ww]ikidata\\|\\s*(Q\\d+)",
            "\\{\\{[Ww]ikidata [Ii]nfobox\\|\\s*qid\\s*=\\s*(Q\\d+)",
            "\\|\\s*wikidata\\s*=\\s*(Q\\d+)",
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: wikitext, range: NSRange(wikitext.startIndex..., in: wikitext)),
               let range = Range(match.range(at: 1), in: wikitext) {
                return String(wikitext[range])
            }
        }
        return nil
    }

    // My uploads
    var myUploadPhotos: [CommonsPhoto] = []
    var isLoadingMyUploads = false
    var myUploadsError: String?
    var hasMoreMyUploads = true
    private var myUploadsContinueToken: String?
    private var myUploadsTask: URLSessionDataTask?

    // MARK: - Fetch my uploads
    func fetchMyUploads(reset: Bool = false) {
        guard let username = WikimediaAuth.shared.username else {
            myUploadsError = AppSettings.shared.l.myUploadsLoginRequired
            return
        }

        if reset {
            myUploadPhotos = []
            myUploadsContinueToken = nil
            hasMoreMyUploads = true
        }

        guard hasMoreMyUploads, !isLoadingMyUploads else { return }
        isLoadingMyUploads = true
        myUploadsError = nil

        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "allimages"),
            URLQueryItem(name: "aiuser", value: username),
            URLQueryItem(name: "aisort", value: "timestamp"),
            URLQueryItem(name: "aidir", value: "descending"),
            URLQueryItem(name: "ailimit", value: "40"),
            URLQueryItem(name: "aiprop", value: "timestamp"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
        ]

        if let token = myUploadsContinueToken {
            queryItems.append(URLQueryItem(name: "aicontinue", value: token))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            isLoadingMyUploads = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("VASturkiye/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let l = AppSettings.shared.l
        myUploadsTask?.cancel()
        myUploadsTask = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let error = error as? URLError, error.code == .cancelled { return }
                if let error = error {
                    self.isLoadingMyUploads = false
                    self.myUploadsError = "\(l.errorPrefix): \(error.localizedDescription)"
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let query = json["query"] as? [String: Any],
                      let images = query["allimages"] as? [[String: Any]] else {
                    self.isLoadingMyUploads = false
                    self.myUploadsError = l.dataUnavailable
                    return
                }

                if let cont = json["continue"] as? [String: Any],
                   let aicont = cont["aicontinue"] as? String {
                    self.myUploadsContinueToken = aicont
                } else {
                    self.hasMoreMyUploads = false
                }

                let titles = images.compactMap { img -> String? in
                    guard let name = img["name"] as? String else { return nil }
                    return "File:\(name)"
                }

                if titles.isEmpty {
                    self.isLoadingMyUploads = false
                    return
                }

                // Fetch full image info (thumb, full URL, wikitext, coordinates, uploader)
                self.fetchMyUploadsImageInfo(titles: titles)
            }
        }
        myUploadsTask?.resume()
    }

    private func fetchMyUploadsImageInfo(titles: [String]) {
        let titlesStr = titles.joined(separator: "|")

        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "titles", value: titlesStr),
            URLQueryItem(name: "prop", value: "imageinfo|coordinates|revisions"),
            URLQueryItem(name: "iiprop", value: "url|timestamp|user|extmetadata"),
            URLQueryItem(name: "iiurlwidth", value: "400"),
            URLQueryItem(name: "rvprop", value: "content"),
            URLQueryItem(name: "rvslots", value: "main"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
        ]

        guard let url = components.url else {
            isLoadingMyUploads = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("VASturkiye/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isLoadingMyUploads = false
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let query = json["query"] as? [String: Any],
                      let pages = query["pages"] as? [[String: Any]] else { return }

                let parsed = self.parsePages(pages)
                // Sort by upload date descending
                let sorted = parsed.sorted { ($0.uploadDate ?? .distantPast) > ($1.uploadDate ?? .distantPast) }
                self.myUploadPhotos.append(contentsOf: sorted)
            }
        }.resume()
    }

    // MARK: - Fetch category total count
    private static let lastKnownCountKey = "wlm_category_last_known_count"
    private static let lastSeenCountKey = "wlm_category_last_seen_count"

    /// Fetch total number of files in both WLM Turkey categories (2025 + 2026)
    func fetchCategoryCount() {
        let categories = [
            "Category:Images from Wiki Loves Monuments 2025 in Turkey",
            "Category:Images from Wiki Loves Monuments 2026 in Turkey"
        ]
        let titles = categories.joined(separator: "|")
        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "titles", value: titles),
            URLQueryItem(name: "prop", value: "categoryinfo"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
        ]
        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.setValue("WLMTurkey/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let query = json["query"] as? [String: Any],
                      let pages = query["pages"] as? [[String: Any]] else { return }
                var total = 0
                for page in pages {
                    if let catInfo = page["categoryinfo"] as? [String: Any],
                       let files = catInfo["files"] as? Int {
                        total += files
                    }
                }
                self.categoryTotalCount = total
                UserDefaults.standard.set(total, forKey: Self.lastKnownCountKey)
            }
        }.resume()
    }

    /// Number of new photos since user last visited the Photos tab
    var newPhotosSinceLastVisit: Int {
        let lastSeen = UserDefaults.standard.integer(forKey: Self.lastSeenCountKey)
        guard lastSeen > 0, categoryTotalCount > lastSeen else { return 0 }
        return categoryTotalCount - lastSeen
    }

    /// Mark current count as "seen" (called when user opens Photos tab)
    func markCategoryCountAsSeen() {
        if categoryTotalCount > 0 {
            UserDefaults.standard.set(categoryTotalCount, forKey: Self.lastSeenCountKey)
        }
    }
}

// MARK: - Distance formatter
private func formatDistance(_ meters: Double) -> String {
    if meters < 1000 {
        return "\(Int(meters)) m"
    } else {
        return String(format: "%.1f km", meters / 1000)
    }
}

// MARK: - Photos View
struct PhotosView: View {
    var onShowOnMap: ((Double, Double) -> Void)?
    @Environment(AppSettings.self) private var settings
    @State private var vm = PhotosViewModel()
    @State private var selectedTab = 1 // 0 = Fotoğraf Bekleyenler, 1 = Son Yüklenenler
    @State private var locationManager = LocationManager()
    @State private var showPhotoDetail = false
    @State private var selectedPhotoIndex: Int = 0
    @State private var detailPhotos: [CommonsPhoto] = []
    @State private var uploadMonument: UploadMonumentInfo?
    @State private var lastNeedingFetchLocation: CLLocation?

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    var body: some View {
        let l = settings.l

        ZStack {
            NavigationStack {
                VStack(spacing: 0) {
                    // Segment picker
                    Picker("", selection: $selectedTab) {
                        Text(l.needingPhotos).tag(0)
                        Text(l.recentUploads).tag(1)
                        Text(l.myUploads).tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    // Content
                    if selectedTab == 0 {
                        needingPhotosContent
                    } else if selectedTab == 1 {
                        recentContent
                    } else {
                        myUploadsContent
                    }
                }
                .navigationTitle(l.photosTitle)
                .onChange(of: selectedTab) { _, newValue in
                    if newValue == 0 {
                        loadNeedingPhotosIfNeeded()
                    } else if newValue == 1 && vm.photos.isEmpty {
                        vm.fetchRecent(reset: true)
                    } else if newValue == 2 && vm.myUploadPhotos.isEmpty {
                        vm.fetchMyUploads(reset: true)
                    }
                }
                .onAppear {
                    vm.fetchCategoryCount()
                    if selectedTab == 0 {
                        loadNeedingPhotosIfNeeded()
                    } else if selectedTab == 1 && vm.photos.isEmpty {
                        vm.fetchRecent(reset: true)
                    } else if selectedTab == 2 && vm.myUploadPhotos.isEmpty {
                        vm.fetchMyUploads(reset: true)
                    }
                }
                .onChange(of: settings.language) { _, _ in
                    // Re-fetch with new language labels
                    lastNeedingFetchLocation = nil
                    vm.needingPhotos = []
                    loadNeedingPhotosIfNeeded()
                }
                .onReceive(NotificationCenter.default.publisher(for: .monumentPhotoUpdated)) { notification in
                    if let qid = notification.userInfo?["qid"] as? String {
                        vm.removeFromNeeding(qid: qid)
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

            // Fullscreen photo viewer overlay
            if showPhotoDetail, !detailPhotos.isEmpty {
                RecentPhotoViewer(
                    photos: detailPhotos,
                    currentIndex: $selectedPhotoIndex,
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showPhotoDetail = false
                        }
                    }
                )
                .transition(.opacity)
            }
        }
    }

    // MARK: - Needing Photos Content
    private var needingPhotosContent: some View {
        let l = settings.l

        return Group {
            if vm.isLoadingNeeding && vm.needingPhotos.isEmpty {
                VStack {
                    Spacer()
                    ProgressView(l.searchingNeedingPhotos)
                        .font(.subheadline)
                    Spacer()
                }
            } else if let error = vm.needingError, vm.needingPhotos.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "location.slash")
                        .font(.system(size: 36))
                        .foregroundStyle(.quaternary)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Button(l.retryButton) {
                        lastNeedingFetchLocation = nil
                        loadNeedingPhotosIfNeeded()
                    }
                    .font(.subheadline)
                    Spacer()
                }
            } else if vm.needingPhotos.isEmpty && !vm.isLoadingNeeding {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(.green.opacity(0.5))
                    Text(l.allHavePhotos)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(l.discoverNew)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Spacer()
                }
            } else {
                VStack(spacing: 0) {
                    // Stats banner
                    HStack(spacing: 8) {
                        Image(systemName: "camera.badge.ellipsis")
                            .foregroundStyle(.orange)
                        Text(.init(l.needingPhotoCount(vm.needingPhotos.count)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.08))

                    List {
                        ForEach(vm.needingPhotos) { monument in
                            NeedingPhotoRow(monument: monument, onUploadTap: {
                                uploadMonument = UploadMonumentInfo(
                                    name: monument.name,
                                    wikidataId: monument.id,
                                    imageUrl: "",
                                    instanceOf: monument.instanceOf,
                                    adminEntity: monument.adminEntity,
                                    heritageDesig: monument.heritageDesig,
                                    architect: monument.architect,
                                    archStyle: monument.archStyle
                                )
                            }, onShowOnMap: {
                                if let lat = monument.latitude, let lon = monument.longitude {
                                    onShowOnMap?(lat, lon)
                                }
                            })
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        guard let loc = locationManager.location else { return }
                        vm.refreshNeedingPhotos(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
                        // Wait for refresh to complete
                        while vm.isRefreshingNeeding {
                            try? await Task.sleep(nanoseconds: 100_000_000)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Recent Content
    private var recentContent: some View {
        let l = settings.l

        return Group {
            if vm.isLoading && vm.photos.isEmpty {
                VStack {
                    Spacer()
                    ProgressView(l.photosLoadingShort)
                        .font(.subheadline)
                    Spacer()
                }
            } else if let error = vm.errorMessage, vm.photos.isEmpty {
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
                        vm.fetchRecent(reset: true)
                    }
                    .font(.subheadline)
                    Spacer()
                }
            } else {
                VStack(spacing: 0) {
                    // Stats banner
                    HStack(spacing: 8) {
                        Image(systemName: "photo.stack.fill")
                            .foregroundStyle(.orange)
                        Text(.init(l.wlmStats(vm.categoryTotalCount > 0 ? vm.categoryTotalCount : 0)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))

                    photoGrid(
                        photos: vm.photos,
                        isLoadingMore: vm.isLoading,
                        canLoadMore: vm.hasMore,
                        loadMore: { vm.fetchRecent() }
                    )
                }
            }
        }
    }

    // MARK: - My Uploads Content
    private var myUploadsContent: some View {
        let l = settings.l

        return Group {
            if !WikimediaAuth.shared.isLoggedIn {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.gray.opacity(0.4))
                    Text(l.myUploadsLoginRequired)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Spacer()
                }
            } else if vm.isLoadingMyUploads && vm.myUploadPhotos.isEmpty {
                VStack {
                    Spacer()
                    ProgressView(l.photosLoadingShort)
                        .font(.subheadline)
                    Spacer()
                }
            } else if let error = vm.myUploadsError, vm.myUploadPhotos.isEmpty {
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
                        vm.fetchMyUploads(reset: true)
                    }
                    .font(.subheadline)
                    Spacer()
                }
            } else if vm.myUploadPhotos.isEmpty && !vm.isLoadingMyUploads {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 48))
                        .foregroundStyle(.gray.opacity(0.4))
                    Text(l.myUploadsEmpty)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(l.myUploadsHint)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Spacer()
                }
            } else {
                VStack(spacing: 0) {
                    // Stats banner
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(.blue)
                        Text(l.isTR
                             ? "\(vm.myUploadPhotos.count) fotoğraf yüklendi"
                             : "\(vm.myUploadPhotos.count) photos uploaded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.08))

                    photoGrid(
                        photos: vm.myUploadPhotos,
                        isLoadingMore: vm.isLoadingMyUploads,
                        canLoadMore: vm.hasMoreMyUploads,
                        loadMore: { vm.fetchMyUploads() }
                    )
                }
            }
        }
    }

    // MARK: - Photo Grid
    private func photoGrid(photos: [CommonsPhoto], isLoadingMore: Bool, canLoadMore: Bool, loadMore: @escaping () -> Void) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    PhotoGridCell(photo: photo)
                        .onTapGesture {
                            detailPhotos = photos
                            selectedPhotoIndex = index
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showPhotoDetail = true
                            }
                        }
                        .onAppear {
                            if canLoadMore, photo.id == photos.last?.id {
                                loadMore()
                            }
                        }
                }
            }

            if isLoadingMore {
                ProgressView()
                    .padding()
            }
        }
    }

    // MARK: - Load needing photos
    private func loadNeedingPhotosIfNeeded() {
        guard let loc = locationManager.location else {
            if vm.needingPhotos.isEmpty {
                vm.needingError = settings.l.locationUnavailable
            }
            return
        }

        // Skip if we already have data and location hasn't changed significantly (100m)
        if !vm.needingPhotos.isEmpty,
           let lastLoc = lastNeedingFetchLocation,
           loc.distance(from: lastLoc) < 100 {
            return
        }

        lastNeedingFetchLocation = loc
        vm.fetchNeedingPhotos(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
    }
}

// MARK: - Needing Photo Row
struct NeedingPhotoRow: View {
    let monument: MonumentNeedingPhoto
    let onUploadTap: () -> Void
    let onShowOnMap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Placeholder icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.orange.opacity(0.1))
                Image(systemName: "camera.fill")
                    .font(.title3)
                    .foregroundStyle(.orange.opacity(0.6))
            }
            .frame(width: 56, height: 56)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(monument.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                // Type · Admin
                if let type = monument.instanceOf {
                    HStack(spacing: 4) {
                        Text(type)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let admin = monument.adminEntity {
                            Text("·")
                                .font(.caption)
                                .foregroundStyle(.quaternary)
                            Text(admin)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                } else if let admin = monument.adminEntity {
                    Text(admin)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if !monument.description.isEmpty {
                    Text(monument.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    // QID badge
                    Text(monument.id)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))

                    // Distance
                    if let dist = monument.distance {
                        Label(formatDistance(dist), systemImage: "location.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            // Show on map button
            if monument.latitude != nil && monument.longitude != nil {
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
}

// MARK: - Photo Grid Cell
struct PhotoGridCell: View {
    let photo: CommonsPhoto

    var body: some View {
        AsyncImage(url: URL(string: photo.thumbUrl)) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if phase.error != nil {
                ZStack {
                    Color(.systemGray5)
                    Image(systemName: "photo")
                        .foregroundStyle(.quaternary)
                }
            } else {
                ZStack {
                    Color(.systemGray6)
                    ProgressView()
                }
            }
        }
        .frame(minHeight: 120)
        .clipped()
    }
}

// MARK: - Recent Photo Viewer (Fullscreen with swipe)
struct RecentPhotoViewer: View {
    let photos: [CommonsPhoto]
    @Binding var currentIndex: Int
    let onDismiss: () -> Void
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var dragOffset: CGFloat = 0
    @State private var wikiTitle: String?
    @State private var commonsCategory: String?
    @State private var showWikipedia = false
    @State private var showCategory = false
    @State private var lastFetchedQID: String?
    private let l = AppSettings.shared.l

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    AsyncImage(url: URL(string: photo.fullUrl)) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .scaleEffect(scale)
                                .gesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            scale = max(0.5, lastScale * value)
                                        }
                                        .onEnded { value in
                                            lastScale = scale
                                            if scale < 1.0 {
                                                withAnimation(.easeOut(duration: 0.2)) {
                                                    scale = 1.0
                                                    lastScale = 1.0
                                                }
                                            }
                                        }
                                )
                                .onTapGesture(count: 2) {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        if scale > 1.5 {
                                            scale = 1.0
                                            lastScale = 1.0
                                        } else {
                                            scale = 3.0
                                            lastScale = 3.0
                                        }
                                    }
                                }
                        } else if phase.error != nil {
                            VStack(spacing: 8) {
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundStyle(.gray)
                                Text(l.couldNotLoad)
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                            }
                        } else {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .onChange(of: currentIndex) { _, _ in
                scale = 1.0
                lastScale = 1.0
            }

            // Top bar + info
            VStack(spacing: 0) {
                HStack {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    Spacer()

                    Text("\(currentIndex + 1) / \(photos.count)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // Monument info bar
                if let label = photos[currentIndex].monumentLabel, !label.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "building.columns.fill")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                            Text(label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            Spacer()
                            if let qid = photos[currentIndex].wikidataId {
                                Text(qid)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        HStack(spacing: 12) {
                            if wikiTitle != nil {
                                Button {
                                    showWikipedia = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "book.fill")
                                            .font(.caption2)
                                        Text(l.wikipedia)
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(.white.opacity(0.8))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                                }
                            }
                            if commonsCategory != nil {
                                Button {
                                    showCategory = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "photo.on.rectangle")
                                            .font(.caption2)
                                        Text(l.categoryPhotos)
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(.white.opacity(0.8))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial.opacity(0.5))
                    .environment(\.colorScheme, .dark)
                }

                Spacer()

                // Attribution bar at bottom
                VStack(spacing: 2) {
                    if let uploader = photos[currentIndex].uploaderName {
                        HStack(spacing: 4) {
                            Text("© \(uploader)")
                            if let dateTaken = photos[currentIndex].dateTaken {
                                Text("·")
                                Text(dateTaken)
                            }
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                    } else if let dateTaken = photos[currentIndex].dateTaken {
                        Text(dateTaken)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Text(photos[currentIndex].title.replacingOccurrences(of: "File:", with: ""))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                    Text("Wikimedia Commons · CC BY-SA")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .padding(.bottom, 44)
                .frame(maxWidth: .infinity)
                .background(.black.opacity(0.5))
            }
        }
        .offset(y: dragOffset)
        .opacity(1.0 - Double(abs(dragOffset)) / 400.0)
        .gesture(
            scale <= 1.0 ?
            DragGesture()
                .onChanged { value in
                    if abs(value.translation.height) > abs(value.translation.width) {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if abs(value.translation.height) > 120 || abs(value.predictedEndTranslation.height) > 300 {
                        withAnimation(.easeOut(duration: 0.2)) {
                            dragOffset = value.translation.height > 0 ? 600 : -600
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onDismiss()
                        }
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) {
                            dragOffset = 0
                        }
                    }
                }
            : nil
        )
        .onAppear { fetchLinksForCurrent() }
        .onChange(of: currentIndex) { _, _ in fetchLinksForCurrent() }
        .sheet(isPresented: $showWikipedia) {
            if let title = wikiTitle {
                NavigationStack {
                    WikipediaPreviewView(articleTitle: title)
                }
            }
        }
        .sheet(isPresented: $showCategory) {
            if let cat = commonsCategory {
                NavigationStack {
                    CategoryBrowserView(categoryName: cat)
                }
            }
        }
    }

    private func fetchLinksForCurrent() {
        guard let qid = photos[currentIndex].wikidataId, qid != lastFetchedQID else { return }
        lastFetchedQID = qid
        wikiTitle = nil
        commonsCategory = nil

        var components = URLComponents(string: "https://www.wikidata.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "wbgetentities"),
            URLQueryItem(name: "ids", value: qid),
            URLQueryItem(name: "props", value: "claims|sitelinks"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
        ]

        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.setValue("WLMTurkey/1.0", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let entities = json["entities"] as? [String: Any],
                      let entity = entities[qid] as? [String: Any] else { return }

                if let claims = entity["claims"] as? [String: Any],
                   let p373 = claims["P373"] as? [[String: Any]],
                   let first = p373.first,
                   let mainsnak = first["mainsnak"] as? [String: Any],
                   let datavalue = mainsnak["datavalue"] as? [String: Any],
                   let value = datavalue["value"] as? String {
                    commonsCategory = value
                }

                let lang = AppSettings.shared.language
                let sitelinkKey = lang == "tr" ? "trwiki" : "enwiki"
                if let sitelinks = entity["sitelinks"] as? [String: Any],
                   let wiki = sitelinks[sitelinkKey] as? [String: Any],
                   let title = wiki["title"] as? String {
                    wikiTitle = title
                } else if let sitelinks = entity["sitelinks"] as? [String: Any],
                          let fallback = sitelinks[lang == "tr" ? "enwiki" : "trwiki"] as? [String: Any],
                          let title = fallback["title"] as? String {
                    wikiTitle = title
                }
            }
        }.resume()
    }
}
