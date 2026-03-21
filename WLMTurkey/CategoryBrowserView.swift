import SwiftUI

// MARK: - Category Browser View
struct CategoryBrowserView: View {
    let categoryName: String
    @Environment(\.dismiss) private var dismiss
    @State private var photos: [CategoryPhoto] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasMore = true
    @State private var continueToken: String?
    @State private var selectedPhotoIndex: Int?

    struct CategoryPhoto: Identifiable {
        let id: String
        let title: String
        let thumbUrl: String
        let fullUrl: String
        let uploadDate: Date?
        let uploaderName: String?
        let dateTaken: String?
    }

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    var body: some View {
        let l = AppSettings.shared.l
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.blue)
                    Text(categoryName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))

                if isLoading && photos.isEmpty {
                    VStack {
                        Spacer()
                        ProgressView(l.photosLoadingShort)
                            .font(.subheadline)
                        Spacer()
                    }
                } else if let error = errorMessage, photos.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 36))
                            .foregroundStyle(.red.opacity(0.6))
                            .accessibilityHidden(true)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else if photos.isEmpty && !isLoading {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 48))
                            .foregroundStyle(.quaternary)
                            .accessibilityHidden(true)
                        Text(l.noCategoryPhotos)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else {
                    ZStack {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
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
                                    .accessibilityLabel(photo.title.replacingOccurrences(of: "File:", with: ""))
                                    .onTapGesture {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            selectedPhotoIndex = index
                                        }
                                    }
                                    .onAppear {
                                        if hasMore, photo.id == photos.last?.id {
                                            fetchPhotos()
                                        }
                                    }
                                }
                            }

                            if isLoading {
                                ProgressView()
                                    .padding()
                            }

                            if !hasMore && !photos.isEmpty {
                                Text(l.photoCount(photos.count))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                            }

                            if let encoded = categoryName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                               let url = URL(string: "https://commons.wikimedia.org/wiki/Category:\(encoded)") {
                                Link(destination: url) {
                                    HStack(spacing: 6) {
                                        commonsLogo(size: 18)
                                        Text(l.viewOnCommons)
                                            .font(.subheadline.weight(.medium))
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                            .font(.caption)
                                    }
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 14)
                                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                                }
                                .padding(.horizontal)
                                .padding(.bottom, 16)
                            }
                        }

                        if let idx = selectedPhotoIndex {
                            CategoryPhotoViewer(
                                photos: photos,
                                currentIndex: Binding(
                                    get: { idx },
                                    set: { selectedPhotoIndex = $0 }
                                ),
                                onDismiss: {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        selectedPhotoIndex = nil
                                    }
                                }
                            )
                            .transition(.opacity)
                        }
                    }
                }
            }
            .navigationTitle(l.categoryPhotosTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.caption.weight(.semibold))
                            Text(l.backToForm)
                                .font(.subheadline)
                        }
                    }
                }
            }
            .onAppear {
                if photos.isEmpty {
                    fetchPhotos()
                }
            }
        }
    }

    // MARK: - Fetch category photos
    private func fetchPhotos() {
        guard hasMore, !isLoading else { return }
        isLoading = true
        errorMessage = nil

        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "categorymembers"),
            URLQueryItem(name: "cmtitle", value: "Category:\(categoryName)"),
            URLQueryItem(name: "cmtype", value: "file|subcat"),
            URLQueryItem(name: "cmsort", value: "timestamp"),
            URLQueryItem(name: "cmdir", value: "desc"),
            URLQueryItem(name: "cmlimit", value: "50"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
        ]

        if let token = continueToken {
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

        URLSession.shared.dataTask(with: request) { [self] data, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.isLoading = false
                    if self.photos.isEmpty {
                        self.errorMessage = "\(AppSettings.shared.l.errorPrefix): \(error.localizedDescription)"
                    }
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let query = json["query"] as? [String: Any],
                      let members = query["categorymembers"] as? [[String: Any]] else {
                    self.isLoading = false
                    if self.photos.isEmpty {
                        self.errorMessage = AppSettings.shared.l.dataUnavailable
                    }
                    return
                }

                if let cont = json["continue"] as? [String: Any],
                   let cmcont = cont["cmcontinue"] as? String {
                    self.continueToken = cmcont
                } else {
                    self.hasMore = false
                }

                let filePageIds = members.compactMap { m -> Int? in
                    guard let ns = m["ns"] as? Int, ns == 6 else { return nil }
                    return m["pageid"] as? Int
                }

                let subcats = members.compactMap { m -> String? in
                    guard let ns = m["ns"] as? Int, ns == 14,
                          let title = m["title"] as? String else { return nil }
                    return title
                }

                if !filePageIds.isEmpty {
                    self.fetchImageInfo(pageIds: filePageIds)
                } else {
                    self.isLoading = false
                }

                if self.photos.isEmpty {
                    for subcat in subcats.prefix(5) {
                        self.fetchSubcategoryFiles(category: subcat)
                    }
                }
            }
        }.resume()
    }

    private func fetchSubcategoryFiles(category: String) {
        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "categorymembers"),
            URLQueryItem(name: "cmtitle", value: category),
            URLQueryItem(name: "cmtype", value: "file"),
            URLQueryItem(name: "cmsort", value: "timestamp"),
            URLQueryItem(name: "cmdir", value: "desc"),
            URLQueryItem(name: "cmlimit", value: "20"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
        ]

        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.setValue("WLMTurkey/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let query = json["query"] as? [String: Any],
                      let members = query["categorymembers"] as? [[String: Any]] else { return }

                let pageIds = members.compactMap { $0["pageid"] as? Int }
                if !pageIds.isEmpty {
                    self.fetchImageInfo(pageIds: pageIds)
                }
            }
        }.resume()
    }

    private func fetchImageInfo(pageIds: [Int]) {
        let idsStr = pageIds.map { String($0) }.joined(separator: "|")

        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "pageids", value: idsStr),
            URLQueryItem(name: "prop", value: "imageinfo"),
            URLQueryItem(name: "iiprop", value: "url|timestamp|user|extmetadata"),
            URLQueryItem(name: "iiurlwidth", value: "400"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
        ]

        guard let url = components.url else {
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("WLMTurkey/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                self.isLoading = false

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let query = json["query"] as? [String: Any],
                      let pages = query["pages"] as? [[String: Any]] else { return }

                let newPhotos = pages.compactMap { page -> CategoryPhoto? in
                    guard let pageid = page["pageid"] as? Int,
                          let title = page["title"] as? String else { return nil }
                    let imageinfo = (page["imageinfo"] as? [[String: Any]])?.first
                    let thumbUrl = imageinfo?["thumburl"] as? String ?? ""
                    let fullUrl = imageinfo?["url"] as? String ?? ""
                    let uploaderName = imageinfo?["user"] as? String

                    var uploadDate: Date?
                    if let timestamp = imageinfo?["timestamp"] as? String {
                        uploadDate = ISO8601DateFormatter().date(from: timestamp)
                    }

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

                    let idStr = String(pageid)
                    if self.photos.contains(where: { $0.id == idStr }) { return nil }

                    return CategoryPhoto(
                        id: idStr,
                        title: title,
                        thumbUrl: thumbUrl,
                        fullUrl: fullUrl,
                        uploadDate: uploadDate,
                        uploaderName: uploaderName,
                        dateTaken: dateTaken
                    )
                }

                self.photos.append(contentsOf: newPhotos)
            }
        }.resume()
    }
}

// MARK: - Category Photo Viewer (Fullscreen with swipe)
struct CategoryPhotoViewer: View {
    let photos: [CategoryBrowserView.CategoryPhoto]
    @Binding var currentIndex: Int
    let onDismiss: () -> Void
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

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
                                .accessibilityLabel(photo.title.replacingOccurrences(of: "File:", with: ""))
                        } else if phase.error != nil {
                            VStack(spacing: 8) {
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundStyle(.gray)
                                Text(AppSettings.shared.l.couldNotLoad)
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

            VStack {
                HStack {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .accessibilityLabel(AppSettings.shared.l.isTR ? "Kapat" : "Close")

                    Spacer()

                    Text("\(currentIndex + 1) / \(photos.count)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Spacer()

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
    }
}
