import SwiftUI
import PhotosUI
import ImageIO

// MARK: - Per-photo metadata
struct PhotoMetadata: Identifiable {
    let id = UUID()
    var image: UIImage
    var fileName: String
    var descriptionTr: String
    var descriptionEn: String
    var categories: [String]  // category names without [[Category:]] wrapper
    var exifDate: Date?
    var exifLatitude: Double?
    var exifLongitude: Double?
    var subcategoryQID: String? // Wikidata QID of the selected subcategory
    var uploadProgress: Double? // nil = not started, 0..<1 = uploading, 1 = done
    var uploadError: String?
    var uploadedFileName: String? // filename on Commons after successful upload
}

// MARK: - Flow Layout (wrapping tags)
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            guard index < subviews.count else { break }
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}

// MARK: - EXIF Helper
struct EXIFReader {
    static func read(from data: Data) -> (date: Date?, lat: Double?, lon: Double?) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return (nil, nil, nil)
        }

        var date: Date?
        if let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any],
           let dateStr = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy:MM:dd HH:mm:ss"
            fmt.locale = Locale(identifier: "en_US_POSIX")
            date = fmt.date(from: dateStr)
        }

        var lat: Double?
        var lon: Double?
        if let gps = props[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
            if let latitude = gps[kCGImagePropertyGPSLatitude as String] as? Double,
               let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String {
                lat = latRef == "S" ? -latitude : latitude
            }
            if let longitude = gps[kCGImagePropertyGPSLongitude as String] as? Double,
               let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String {
                lon = lonRef == "W" ? -longitude : longitude
            }
        }

        return (date, lat, lon)
    }
}

// MARK: - Zoomable image preview
struct ZoomableImageView: View {
    let image: UIImage
    let onDismiss: () -> Void
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.9)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .padding(20)
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
                                    offset = .zero
                                    lastOffset = .zero
                                }
                            }
                        }
                        .simultaneously(with:
                            DragGesture()
                                .onChanged { value in
                                    if scale > 1.0 {
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        if scale > 1.5 {
                            scale = 1.0
                            lastScale = 1.0
                            offset = .zero
                            lastOffset = .zero
                        } else {
                            scale = 3.0
                            lastScale = 3.0
                        }
                    }
                }
                .onTapGesture {
                    if scale <= 1.0 {
                        onDismiss()
                    }
                }
                .accessibilityLabel(AppSettings.shared.l.isTR ? "Fotoğraf önizleme" : "Photo preview")

            // Close button
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(AppSettings.shared.l.isTR ? "Kapat" : "Close")
            .padding(.top, 54)
            .padding(.trailing, 20)
        }
    }
}

// MARK: - Upload Sheet
struct UploadSheetView: View {
    let monument: UploadMonumentInfo
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photoData: [PhotoMetadata] = []
    @State private var license = AppSettings.shared.defaultLicense
    @State private var showLoginAlert = false
    @State private var expandedPhotoId: UUID?
    @State private var showPreview = false
    @State private var previewImageId: UUID?
    @State private var isLoadingPhotos = false
    @State private var loadedCount = 0
    @State private var monumentPreviewImage: UIImage?
    @State private var showMonumentPreview = false
    @State private var monumentPhotoAttribution: String?
    @State private var monumentPhotoLicense: String?
    @State private var commonsCategory: String?
    @State private var isLoadingCategory = false
    @State private var showCategoryBrowser = false
    @State private var trwikiTitle: String?
    @State private var showWikipediaPreview = false
    @State private var isUploading = false
    @State private var uploadResultMessage: String?
    @State private var labelEn: String?
    @State private var labelTr: String?
    @State private var subcategories: [String] = []
    @State private var showSubcategoryPicker = false
    @State private var subcategoryPhotoIndex: Int?
    @State private var newCategoryText = ""
    @State private var showAddCategory = false
    @State private var addCategoryPhotoIndex: Int?
    @State private var categorySuggestions: [String] = []
    @State private var isSearchingCategories = false
    @State private var monumentHasP18 = true // default true to hide UI until checked
    @State private var selectingP18Photo = false
    @State private var selectedP18Index: Int?
    @State private var showP18Confirm = false
    @State private var isSettingP18 = false
    @State private var p18ResultMessage: String?
    @State private var p18Success = false
    @State private var resolvedImageUrl: String?

    /// All photos uploaded successfully
    private var allUploaded: Bool {
        !photoData.isEmpty && photoData.allSatisfy { ($0.uploadProgress ?? 0) >= 1.0 }
    }
    private struct LicenseOption: Identifiable {
        var id: String { tag }
        let tag: String
        let label: String
        let desc: String
    }

    private var licenseOptions: [LicenseOption] {
        let isTR = AppSettings.shared.l.isTR
        return [
            LicenseOption(
                tag: "CC BY-SA 4.0",
                label: "CC BY-SA 4.0",
                desc: isTR ? "Atıf ver, aynı lisansla paylaş" : "Credit author, share alike"
            ),
            LicenseOption(
                tag: "CC BY 4.0",
                label: "CC BY 4.0",
                desc: isTR ? "Atıf ver, serbestçe kullan" : "Credit author, use freely"
            ),
            LicenseOption(
                tag: "CC0 1.0",
                label: "CC0 1.0",
                desc: isTR ? "Kamu malı, tüm haklar bırakılır" : "Public domain, all rights waived"
            ),
        ]
    }

    private static let tsFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let exifDisplayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy HH:mm:ss"
        f.locale = Locale(identifier: "tr_TR")
        return f
    }()

    @ViewBuilder
    private var monumentDetailRows: some View {
        let l = AppSettings.shared.l
        let details: [(String, String?)] = [
            (l.instanceOf, monument.instanceOf),
            (l.adminEntity, monument.adminEntity),
            (l.heritageDesig, monument.heritageDesig),
            (l.architect, monument.architect),
            (l.archStyle, monument.archStyle),
        ]
        let available = details.filter { $0.1 != nil }
        if !available.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(available, id: \.0) { label, value in
                    HStack(spacing: 4) {
                        Text(label + ":")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(value!)
                            .font(.caption2)
                            .foregroundStyle(label == l.heritageDesig ? heritageColor(value!) : .secondary)
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    private func heritageColor(_ value: String) -> Color {
        let lower = value.lowercased()
        let negative = ["yıkılmış", "harabe", "kısmen yıkılmış", "yok olmuş", "sular altında",
                        "belirsiz", "temelleri kalmış", "kazı çalışması yapılmamış",
                        "destroyed", "ruin", "partially", "submerged", "unknown", "unexcavated",
                        "foundations remain"]
        if negative.contains(where: { lower.contains($0) }) {
            return .red
        }
        return .green
    }

    private func defaultFileName(date: Date?, index: Int) -> String {
        let ts: String
        if let d = date {
            ts = Self.tsFormatter.string(from: d)
        } else {
            ts = Self.tsFormatter.string(from: Date().addingTimeInterval(Double(index)))
        }
        return "\(monument.name) \(ts).jpg"
    }

    private func buildDescriptionWikitext(for p: PhotoMetadata) -> String {
        let qid = p.subcategoryQID ?? monument.wikidataId
        return "{{tr|1=\(p.descriptionTr)}} {{en|1=\(p.descriptionEn)}} {{on Wikidata|\(qid)}}"
    }

    private func licenseTemplate() -> String {
        switch license {
        case "CC BY 4.0": return "{{cc-by-4.0}}"
        case "CC0 1.0": return "{{cc-zero}}"
        default: return "{{cc-by-sa-4.0}}"
        }
    }

    private func wikitextPreview(for p: PhotoMetadata) -> String {
        let desc = buildDescriptionWikitext(for: p)
        var locationLine = ""
        if let lat = p.exifLatitude, let lon = p.exifLongitude {
            locationLine = "\n{{Location|\(String(format: "%.6f", lat))|\(String(format: "%.6f", lon))}}"
        }

        return """
        == {{int:filedesc}} ==
        {{Information
        |description=\(desc)
        |date=\(p.exifDate.map { Self.tsFormatter.string(from: $0) } ?? "")
        |source={{own}}
        |author=~~~
        }}\(locationLine)

        == {{int:license-header}} ==
        \(licenseTemplate())

        [[Category:\(WLMYear.categoryName)]]
        \(p.categories.map { "[[Category:\($0)]]" }.joined(separator: "\n"))
        """
    }

    // MARK: - Category Tags View
    @ViewBuilder
    private func categoryTagsView(photoIndex: Int) -> some View {
        let cats = photoData[photoIndex].categories
        let isTR = AppSettings.shared.l.isTR

        // Split categories: monument-related (P373 or its subcategories) vs others
        let monumentCats = cats.filter { $0 == commonsCategory || subcategories.contains($0) }
        let otherCats = cats.filter { $0 != commonsCategory && !subcategories.contains($0) }
        let hasSubcatSelected = commonsCategory != nil && !cats.contains(commonsCategory!) && !monumentCats.isEmpty

        VStack(alignment: .leading, spacing: 8) {
            // 1) Monument category group (always on top)
            if !monumentCats.isEmpty || commonsCategory != nil {
                VStack(alignment: .leading, spacing: 6) {
                    // "Return to parent" link — shown above the subcategory tag
                    if hasSubcatSelected, let parentCat = commonsCategory {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                photoData[photoIndex].categories.removeAll { subcategories.contains($0) }
                                if !photoData[photoIndex].categories.contains(parentCat) {
                                    photoData[photoIndex].categories.insert(parentCat, at: 0)
                                }
                                let ts: String
                                if let d = photoData[photoIndex].exifDate {
                                    ts = Self.tsFormatter.string(from: d)
                                } else {
                                    ts = Self.tsFormatter.string(from: Date().addingTimeInterval(Double(photoIndex)))
                                }
                                photoData[photoIndex].fileName = "\(parentCat) \(ts).jpg"
                                photoData[photoIndex].subcategoryQID = nil
                                // Restore descriptions from monument labels
                                photoData[photoIndex].descriptionTr = labelTr ?? monument.name
                                photoData[photoIndex].descriptionEn = labelEn ?? monument.name
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.caption2)
                                Text(isTR ? "Üst kategoriye geri dön: \(parentCat)" : "Return to parent: \(parentCat)")
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.orange)
                        }
                    }

                    // Monument category tags
                    FlowLayout(spacing: 6) {
                        ForEach(monumentCats, id: \.self) { cat in
                            categoryTag(cat, photoIndex: photoIndex)
                        }
                    }

                    // "Add subcategories" suggestion — shown right below the P373 tag
                    if let parentCat = commonsCategory,
                       cats.contains(parentCat),
                       !subcategories.isEmpty {
                        Button {
                            subcategoryPhotoIndex = photoIndex
                            showSubcategoryPicker = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.caption2)
                                Text(isTR ? "Alt kategorileri de ekleyebilirsiniz" : "You can also add subcategories")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.blue)
                        }
                    }
                }
            }

            // 2) Other categories + Add button
            FlowLayout(spacing: 6) {
                ForEach(otherCats, id: \.self) { cat in
                    categoryTag(cat, photoIndex: photoIndex)
                }

                // Add category button
                Button {
                    addCategoryPhotoIndex = photoIndex
                    newCategoryText = ""
                    showAddCategory = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                        Text(isTR ? "Ekle" : "Add")
                            .font(.caption2)
                    }
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    @ViewBuilder
    private func readOnlyCategoryTags(photoIndex: Int) -> some View {
        let cats = photoData[photoIndex].categories
        FlowLayout(spacing: 6) {
            ForEach(cats, id: \.self) { cat in
                Text(cat)
                    .font(.caption2)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .foregroundStyle(.secondary)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    @ViewBuilder
    private func categoryTag(_ cat: String, photoIndex: Int) -> some View {
        HStack(spacing: 4) {
            Text(cat)
                .font(.caption2)
                .lineLimit(1)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    photoData[photoIndex].categories.removeAll { $0 == cat }
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6))
    }

    private func fetchSubcategories(of categoryName: String) {
        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "categorymembers"),
            URLQueryItem(name: "cmtitle", value: "Category:\(categoryName)"),
            URLQueryItem(name: "cmtype", value: "subcat"),
            URLQueryItem(name: "cmlimit", value: "50"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
        ]

        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.setValue("VASturkiye/1.0", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let query = json["query"] as? [String: Any],
                      let members = query["categorymembers"] as? [[String: Any]] else { return }

                subcategories = members.compactMap { member in
                    guard let title = member["title"] as? String else { return nil }
                    // Remove "Category:" prefix
                    return title.hasPrefix("Category:") ? String(title.dropFirst(9)) : title
                }
            }
        }.resume()
    }

    /// Fetch the Wikidata QID linked to a Commons category page
    private func fetchCategoryQID(categoryName: String, photoIndex: Int) {
        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "titles", value: "Category:\(categoryName)"),
            URLQueryItem(name: "prop", value: "pageprops"),
            URLQueryItem(name: "ppprop", value: "wikibase_item"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
        ]

        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.setValue("VASturkiye/1.0", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let query = json["query"] as? [String: Any],
                      let pages = query["pages"] as? [[String: Any]],
                      let page = pages.first,
                      let pageprops = page["pageprops"] as? [String: Any],
                      let qid = pageprops["wikibase_item"] as? String else { return }

                if photoIndex < photoData.count {
                    photoData[photoIndex].subcategoryQID = qid
                    // Fetch labels from Wikidata for this QID
                    self.fetchLabelsForQID(qid: qid, photoIndex: photoIndex)
                }
            }
        }.resume()
    }

    /// Fetch TR/EN labels from Wikidata and update photo descriptions
    private func fetchLabelsForQID(qid: String, photoIndex: Int) {
        var components = URLComponents(string: "https://www.wikidata.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "wbgetentities"),
            URLQueryItem(name: "ids", value: qid),
            URLQueryItem(name: "props", value: "labels"),
            URLQueryItem(name: "languages", value: "en|tr"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
        ]

        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.setValue("VASturkiye/1.0", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                guard photoIndex < photoData.count,
                      let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let entities = json["entities"] as? [String: Any],
                      let entity = entities[qid] as? [String: Any],
                      let labels = entity["labels"] as? [String: Any] else { return }

                if let trLabel = labels["tr"] as? [String: Any],
                   let trValue = trLabel["value"] as? String {
                    photoData[photoIndex].descriptionTr = trValue
                }
                if let enLabel = labels["en"] as? [String: Any],
                   let enValue = enLabel["value"] as? String {
                    photoData[photoIndex].descriptionEn = enValue
                }
            }
        }.resume()
    }

    private func deletePhoto(at index: Int) {
        photoData.remove(at: index)
        if index < selectedPhotos.count {
            selectedPhotos.remove(at: index)
        }
    }

    // MARK: - Upload to Wikimedia Commons
    private func uploadPhotos() {
        guard WikimediaAuth.shared.isLoggedIn, !photoData.isEmpty else { return }
        isUploading = true
        uploadResultMessage = nil

        // Reset progress
        for i in photoData.indices {
            photoData[i].uploadProgress = 0
            photoData[i].uploadError = nil
        }

        uploadNextPhoto(at: 0)
    }

    private func uploadNextPhoto(at index: Int) {
        guard index < photoData.count else {
            // All done
            isUploading = false
            let isTR = AppSettings.shared.l.isTR
            let successCount = photoData.filter { ($0.uploadProgress ?? 0) >= 1.0 }.count
            uploadResultMessage = isTR
                ? "\(successCount)/\(photoData.count) fotoğraf başarıyla yüklendi!"
                : "\(successCount)/\(photoData.count) photos uploaded successfully!"
            return
        }

        let meta = photoData[index]
        guard let jpegData = meta.image.jpegData(compressionQuality: 0.92) else {
            photoData[index].uploadError = "JPEG conversion failed"
            photoData[index].uploadProgress = nil
            uploadNextPhoto(at: index + 1)
            return
        }

        let wikitext = wikitextPreview(for: meta)
        let comment = "Uploaded via WLM Turkey app — \(monument.name)"

        WikimediaAuth.shared.uploadFile(
            imageData: jpegData,
            fileName: meta.fileName,
            wikitext: wikitext,
            comment: comment,
            onProgress: { progress in
                if index < photoData.count {
                    photoData[index].uploadProgress = progress * 0.95 // reserve 5% for server processing
                }
            },
            completion: { result in
                switch result {
                case .success(let filename):
                    if index < photoData.count {
                        photoData[index].uploadProgress = 1.0
                        photoData[index].uploadedFileName = filename
                    }
                case .failure(let error):
                    if index < photoData.count {
                        photoData[index].uploadError = error.localizedDescription
                        photoData[index].uploadProgress = nil
                    }
                }
                uploadNextPhoto(at: index + 1)
            }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: 0) {
                        // Monument header
                        HStack(spacing: 14) {
                            if let displayImageUrl = resolvedImageUrl ?? (monument.imageUrl.isEmpty ? nil : monument.imageUrl) {
                                AsyncImage(url: URL(string: displayImageUrl)) { phase in
                                    if let image = phase.image {
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } else {
                                        Rectangle().fill(Color.gray.opacity(0.15))
                                    }
                                }
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .accessibilityLabel(monument.name)
                                .onTapGesture {
                                    Task {
                                        let highResUrl: String
                                        if displayImageUrl.contains("width=") {
                                            highResUrl = displayImageUrl
                                                .replacingOccurrences(of: "width=120", with: "width=1200")
                                                .replacingOccurrences(of: "width=400", with: "width=1200")
                                        } else {
                                            highResUrl = displayImageUrl
                                        }
                                        if let url = URL(string: highResUrl),
                                           let (data, _) = try? await URLSession.shared.data(from: url),
                                           let img = UIImage(data: data) {
                                            monumentPreviewImage = img
                                            withAnimation(.easeInOut(duration: 0.25)) {
                                                showMonumentPreview = true
                                            }
                                        }
                                    }
                                }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(monument.name)
                                    .font(.headline)
                                HStack(spacing: 4) {
                                    Image(systemName: "building.columns")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("\(AppSettings.shared.l.wikidataLabel): \(monument.wikidataId)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                // Monument detail properties
                                monumentDetailRows
                                HStack(spacing: 12) {
                                    if let _ = trwikiTitle {
                                        Button {
                                            showWikipediaPreview = true
                                        } label: {
                                            HStack(spacing: 4) {
                                                wikipediaLogo(size: 16)
                                                Text(AppSettings.shared.l.wikipedia)
                                                    .font(.caption)
                                            }
                                            .foregroundStyle(.primary)
                                        }
                                        .accessibilityLabel(AppSettings.shared.l.wikipedia)
                                    }
                                    if let _ = commonsCategory {
                                        Button {
                                            showCategoryBrowser = true
                                        } label: {
                                            HStack(spacing: 4) {
                                                commonsLogo(size: 16)
                                                Text(AppSettings.shared.l.categoryPhotos)
                                                    .font(.caption)
                                            }
                                            .foregroundStyle(.primary)
                                        }
                                        .accessibilityLabel(AppSettings.shared.l.categoryPhotos)
                                    }
                                }
                                if isLoadingCategory {
                                    HStack(spacing: 4) {
                                        ProgressView()
                                            .controlSize(.mini)
                                        Text(AppSettings.shared.l.infoLoading)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            Spacer()
                        }
                        .padding()
                        .background(Color(.systemBackground))

                        // WLM banner
                        HStack(spacing: 10) {
                            Rectangle()
                                .fill(Color.red)
                                .frame(width: 4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(AppSettings.shared.l.wlmTurkey)
                                    .font(.subheadline.weight(.semibold))
                                Text(AppSettings.shared.l.uploadDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemBackground))

                        VStack(spacing: 20) {
                            // Photo picker (hidden after upload complete)
                            if !allUploaded {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(AppSettings.shared.l.photosLabel, systemImage: "photo.badge.plus")
                                    .font(.subheadline.weight(.semibold))

                                PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 20, matching: .images) {
                                    VStack(spacing: 10) {
                                        if photoData.isEmpty && !isLoadingPhotos {
                                            Image(systemName: "photo.on.rectangle.angled")
                                                .font(.system(size: 36))
                                                .foregroundStyle(.secondary)
                                            Text(AppSettings.shared.l.selectPhotosHint)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                            Text(AppSettings.shared.l.photoFormats)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        } else if isLoadingPhotos {
                                            HStack(spacing: 10) {
                                                ProgressView()
                                                Text(AppSettings.shared.l.photosLoading(loadedCount, selectedPhotos.count))
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                            }
                                        } else {
                                            HStack(spacing: 8) {
                                                Image(systemName: "plus.circle.fill")
                                                    .font(.title2)
                                                    .foregroundStyle(.blue)
                                                Text(AppSettings.shared.l.photosAdded(photoData.count))
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: photoData.isEmpty && !isLoadingPhotos ? 160 : 72)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                                            .foregroundStyle(.quaternary)
                                    )
                                }
                                .onChange(of: selectedPhotos) { _, items in
                                    Task {
                                        isLoadingPhotos = true
                                        loadedCount = 0
                                        photoData = []

                                        for (i, item) in items.enumerated() {
                                            if let data = try? await item.loadTransferable(type: Data.self),
                                               let img = UIImage(data: data) {
                                                let exif = EXIFReader.read(from: data)
                                                var initialCategories: [String] = []
                                                if let p373 = commonsCategory {
                                                    initialCategories.append(p373)
                                                }
                                                let meta = PhotoMetadata(
                                                    image: img,
                                                    fileName: defaultFileName(date: exif.date, index: i),
                                                    descriptionTr: labelTr ?? monument.name,
                                                    descriptionEn: labelEn ?? monument.name,
                                                    categories: initialCategories,
                                                    exifDate: exif.date,
                                                    exifLatitude: exif.lat,
                                                    exifLongitude: exif.lon
                                                )
                                                withAnimation(.easeOut(duration: 0.3)) {
                                                    photoData.append(meta)
                                                    loadedCount = i + 1
                                                }
                                            }
                                        }

                                        isLoadingPhotos = false
                                    }
                                }
                            }
                            } // end if !allUploaded (photo picker)

                            // Per-photo details
                            if !photoData.isEmpty {
                                VStack(spacing: 12) {
                                    ForEach(photoData.indices, id: \.self) { i in
                                        let isExpanded = expandedPhotoId == photoData[i].id
                                            VStack(spacing: 0) {
                                                HStack(spacing: 10) {
                                                    Button {
                                                        withAnimation(.easeInOut(duration: 0.25)) {
                                                            previewImageId = photoData[i].id
                                                        }
                                                    } label: {
                                                        Image(uiImage: photoData[i].image)
                                                            .resizable()
                                                            .aspectRatio(contentMode: .fill)
                                                            .frame(width: 48, height: 48)
                                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                                    }
                                                    .accessibilityLabel(photoData[i].fileName)

                                                    Button {
                                                        withAnimation(.easeInOut(duration: 0.2)) {
                                                            expandedPhotoId = isExpanded ? nil : photoData[i].id
                                                        }
                                                    } label: {
                                                        VStack(alignment: .leading, spacing: 2) {
                                                            Text(photoData[i].fileName)
                                                                .font(.caption.weight(.semibold))
                                                                .foregroundStyle(.primary)
                                                                .lineLimit(1)
                                                            if let lat = photoData[i].exifLatitude,
                                                               let lon = photoData[i].exifLongitude {
                                                                Text(String(format: "%.5f, %.5f", lat, lon))
                                                                    .font(.caption2)
                                                                    .foregroundStyle(.secondary)
                                                            } else {
                                                                Text(AppSettings.shared.l.noLocationInfo)
                                                                    .font(.caption2)
                                                                    .foregroundStyle(.tertiary)
                                                            }
                                                            if let date = photoData[i].exifDate {
                                                                Text(Self.exifDisplayFormatter.string(from: date))
                                                                    .font(.caption2)
                                                                    .foregroundStyle(.secondary)
                                                            } else {
                                                                Text(AppSettings.shared.l.noDateTaken)
                                                                    .font(.caption2)
                                                                    .foregroundStyle(.tertiary)
                                                            }
                                                        }
                                                    }

                                                    Spacer()

                                                    if let uploadedName = photoData[i].uploadedFileName {
                                                        // Commons link after upload
                                                        Button {
                                                            let encoded = uploadedName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? uploadedName
                                                            if let url = URL(string: "https://commons.wikimedia.org/wiki/File:\(encoded)") {
                                                                UIApplication.shared.open(url)
                                                            }
                                                        } label: {
                                                            HStack(spacing: 4) {
                                                                Image(systemName: "arrow.up.right.square")
                                                                    .font(.caption2)
                                                                Text("Commons")
                                                                    .font(.caption2)
                                                            }
                                                            .foregroundStyle(.blue)
                                                            .padding(.horizontal, 8)
                                                            .padding(.vertical, 4)
                                                            .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                                                        }
                                                        .accessibilityLabel("Wikimedia Commons")
                                                    } else {
                                                        // Expand/collapse button
                                                        Button {
                                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                                expandedPhotoId = isExpanded ? nil : photoData[i].id
                                                            }
                                                        } label: {
                                                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                                                .font(.caption.weight(.semibold))
                                                                .foregroundStyle(.secondary)
                                                                .frame(width: 24, height: 24)
                                                        }

                                                        // Delete button
                                                        Button {
                                                            withAnimation(.easeInOut(duration: 0.25)) {
                                                                deletePhoto(at: i)
                                                            }
                                                        } label: {
                                                            Image(systemName: "xmark")
                                                                .font(.caption2.weight(.semibold))
                                                                .foregroundStyle(.secondary)
                                                                .frame(width: 24, height: 24)
                                                                .background(Color(.systemGray5), in: Circle())
                                                        }
                                                        .accessibilityLabel(AppSettings.shared.l.isTR ? "Sil" : "Delete")
                                                    }
                                                }
                                                .padding(12)

                                                if let progress = photoData[i].uploadProgress {
                                                    VStack(spacing: 4) {
                                                        ProgressView(value: progress)
                                                            .tint(progress >= 1 ? .green : .blue)
                                                        HStack {
                                                            if progress >= 1 {
                                                                Label(AppSettings.shared.l.uploaded, systemImage: "checkmark.circle.fill")
                                                                    .font(.caption2)
                                                                    .foregroundStyle(.green)
                                                            } else {
                                                                Text(AppSettings.shared.l.uploadingProgress(Int(progress * 100)))
                                                                    .font(.caption2)
                                                                    .foregroundStyle(.secondary)
                                                            }
                                                            Spacer()
                                                        }
                                                    }
                                                    .padding(.horizontal, 12)
                                                    .padding(.bottom, 8)
                                                }
                                                if let error = photoData[i].uploadError {
                                                    HStack(spacing: 4) {
                                                        Image(systemName: "exclamationmark.triangle.fill")
                                                            .font(.caption2)
                                                            .foregroundStyle(.red)
                                                        Text(error)
                                                            .font(.caption2)
                                                            .foregroundStyle(.red)
                                                        Spacer()
                                                    }
                                                    .padding(.horizontal, 12)
                                                    .padding(.bottom, 8)
                                                }

                                                if isExpanded {
                                                    let isUploaded = (photoData[i].uploadProgress ?? 0) >= 1.0
                                                    VStack(spacing: 14) {
                                                        Divider()
                                                        VStack(alignment: .leading, spacing: 6) {
                                                            Text(AppSettings.shared.l.fileName)
                                                                .font(.caption.weight(.semibold))
                                                                .foregroundStyle(.secondary)
                                                            if isUploaded {
                                                                Text(photoData[i].fileName)
                                                                    .font(.subheadline)
                                                                    .foregroundStyle(.secondary)
                                                            } else {
                                                                TextField("Dosya adı", text: $photoData[i].fileName)
                                                                    .textFieldStyle(.roundedBorder)
                                                                    .font(.subheadline)
                                                            }
                                                        }
                                                        VStack(alignment: .leading, spacing: 6) {
                                                            Label("Türkçe", systemImage: "flag.fill")
                                                                .font(.caption.weight(.semibold))
                                                                .foregroundStyle(.secondary)
                                                            if isUploaded {
                                                                Text(photoData[i].descriptionTr)
                                                                    .font(.subheadline)
                                                                    .foregroundStyle(.secondary)
                                                            } else {
                                                                TextField("Türkçe açıklama", text: $photoData[i].descriptionTr)
                                                                    .textFieldStyle(.roundedBorder)
                                                                    .font(.subheadline)
                                                            }
                                                        }
                                                        VStack(alignment: .leading, spacing: 6) {
                                                            Label("English", systemImage: "globe")
                                                                .font(.caption.weight(.semibold))
                                                                .foregroundStyle(.secondary)
                                                            if isUploaded {
                                                                Text(photoData[i].descriptionEn)
                                                                    .font(.subheadline)
                                                                    .foregroundStyle(.secondary)
                                                            } else {
                                                                TextField("English description", text: $photoData[i].descriptionEn)
                                                                    .textFieldStyle(.roundedBorder)
                                                                    .font(.subheadline)
                                                            }
                                                        }
                                                        VStack(alignment: .leading, spacing: 6) {
                                                            Text(AppSettings.shared.l.categories)
                                                                .font(.caption.weight(.semibold))
                                                                .foregroundStyle(.secondary)
                                                            if isUploaded {
                                                                readOnlyCategoryTags(photoIndex: i)
                                                            } else {
                                                                categoryTagsView(photoIndex: i)
                                                            }
                                                        }
                                                    }
                                                    .padding(.horizontal, 12)
                                                    .padding(.bottom, 12)
                                                }
                                            }
                                            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
                                            .overlay {
                                                if selectingP18Photo && photoData[i].uploadedFileName != nil {
                                                    RoundedRectangle(cornerRadius: 10)
                                                        .stroke(Color.orange, lineWidth: 2)
                                                        .background(Color.orange.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                                                        .onTapGesture {
                                                            selectedP18Index = i
                                                            showP18Confirm = true
                                                        }
                                                }
                                            }
                                    }
                                }
                            }

                            // License (hidden after upload complete)
                            if !allUploaded {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(AppSettings.shared.l.license)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Picker("Lisans", selection: $license) {
                                    ForEach(licenseOptions) { opt in
                                        Text("\(opt.label) — \(opt.desc)").tag(opt.tag)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))

                                // Selected license description
                                if let selected = licenseOptions.first(where: { $0.tag == license }) {
                                    Text(selected.desc)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            // Wikitext preview (hidden after upload complete)
                            if !photoData.isEmpty && !allUploaded {
                                VStack(alignment: .leading, spacing: 8) {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            showPreview.toggle()
                                        }
                                    } label: {
                                        HStack {
                                            Label(AppSettings.shared.l.commonsPreview, systemImage: "doc.text.magnifyingglass")
                                                .font(.subheadline.weight(.medium))
                                            Spacer()
                                            Image(systemName: showPreview ? "chevron.up" : "chevron.down")
                                                .font(.caption.weight(.semibold))
                                        }
                                        .foregroundStyle(.secondary)
                                    }

                                    if showPreview {
                                        ForEach(photoData) { p in
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("File:\(p.fileName)")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(.primary)
                                                Text(wikitextPreview(for: p))
                                                    .font(.system(size: 11, design: .monospaced))
                                                    .foregroundStyle(.secondary)
                                                    .padding(8)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6))
                                            }
                                        }
                                    }
                                }
                                .padding(12)
                                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
                            }

                            // Upload buttons (hidden after upload complete)
                            if !allUploaded {
                                if WikimediaAuth.shared.isLoggedIn {
                                    // Logged in — real upload
                                    VStack(spacing: 10) {
                                        Button {
                                            uploadPhotos()
                                        } label: {
                                            HStack {
                                                if isUploading {
                                                    ProgressView()
                                                        .tint(.white)
                                                        .padding(.trailing, 4)
                                                }
                                                Text(isUploading
                                                     ? (AppSettings.shared.l.isTR ? "Yükleniyor…" : "Uploading…")
                                                     : (AppSettings.shared.l.isTR ? "Wikimedia Commons'a Yükle" : "Upload to Wikimedia Commons"))
                                                    .font(.subheadline.weight(.semibold))
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(photoData.isEmpty || isUploading ? Color.gray : Color.blue)
                                            .foregroundStyle(.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                        }
                                        .disabled(photoData.isEmpty || isUploading)
                                    }
                                } else {
                                    // Not logged in
                                    HStack(spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.yellow)
                                        Text(AppSettings.shared.l.loginRequired)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(12)
                                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

                                    VStack(spacing: 10) {
                                        Button {
                                            showLoginAlert = true
                                        } label: {
                                            Text(AppSettings.shared.l.uploadLoginRequired)
                                                .font(.subheadline.weight(.semibold))
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 12)
                                                .background(photoData.isEmpty ? Color.gray : Color.red)
                                                .foregroundStyle(.white)
                                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                        }
                                        .disabled(photoData.isEmpty)

                                        Button {
                                            if let url = URL(string: "https://commons.wikimedia.org/wiki/Special:UploadWizard") {
                                                UIApplication.shared.open(url)
                                            }
                                        } label: {
                                            Text(AppSettings.shared.l.uploadOnCommons)
                                                .font(.subheadline)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 12)
                                                .background(Color(.tertiarySystemFill))
                                                .foregroundStyle(.primary)
                                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                        }
                                    }
                                }
                            }

                            } // end if !allUploaded (license, preview, buttons)

                            // Upload complete message
                            if allUploaded {
                                VStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 36))
                                        .foregroundStyle(.green)
                                    Text(AppSettings.shared.l.isTR
                                         ? "\(photoData.count) fotoğraf başarıyla yüklendi!"
                                         : "\(photoData.count) photo(s) uploaded successfully!")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(AppSettings.shared.l.isTR
                                         ? "Fotoğraflarınız Wikimedia Commons'a yüklendi. Her satırdaki Commons linkinden görüntüleyebilirsiniz."
                                         : "Your photos have been uploaded to Wikimedia Commons. Use the Commons link on each row to view them.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))

                                // P18 suggestion — shown if monument has no image
                                if !monumentHasP18 || p18ResultMessage != nil {
                                    if let resultMsg = p18ResultMessage {
                                        // Success/error message
                                        VStack(spacing: 8) {
                                            Image(systemName: p18Success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                                .font(.system(size: 36))
                                                .foregroundStyle(p18Success ? .green : .orange)
                                            Text(resultMsg)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                                .multilineTextAlignment(.center)
                                        }
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
                                    } else if selectingP18Photo {
                                        // Selection mode active
                                        VStack(spacing: 8) {
                                            Image(systemName: "hand.tap.fill")
                                                .font(.system(size: 24))
                                                .foregroundStyle(.blue)
                                            Text(AppSettings.shared.l.isTR
                                                 ? "Yukarıdan anıt fotoğrafı olarak ayarlamak istediğiniz fotoğrafı seçin."
                                                 : "Select a photo above to set as the monument image.")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .multilineTextAlignment(.center)
                                            Button {
                                                withAnimation(.easeInOut(duration: 0.3)) {
                                                    selectingP18Photo = false
                                                    selectedP18Index = nil
                                                }
                                            } label: {
                                                Text(AppSettings.shared.l.isTR ? "İptal" : "Cancel")
                                                    .font(.caption)
                                                    .foregroundStyle(.red)
                                            }
                                        }
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
                                    } else if isSettingP18 {
                                        // Setting P18 in progress
                                        VStack(spacing: 8) {
                                            ProgressView()
                                            Text(AppSettings.shared.l.isTR
                                                 ? "Wikidata'ya kaydediliyor..."
                                                 : "Saving to Wikidata...")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
                                    } else {
                                        // Suggest setting P18
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                selectingP18Photo = true
                                            }
                                        } label: {
                                            VStack(spacing: 8) {
                                                Image(systemName: "photo.badge.plus")
                                                    .font(.system(size: 24))
                                                    .foregroundStyle(.orange)
                                                Text(AppSettings.shared.l.isTR
                                                     ? "Bu kültür varlığı için ilk kez fotoğraf yüklendi! Yüklediğiniz fotoğraflardan birini anıt fotoğrafı olarak seçebilirsiniz."
                                                     : "This is the first photo uploaded for this monument! You can select one of your uploaded photos as the monument image.")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .multilineTextAlignment(.center)
                                            }
                                            .padding()
                                            .frame(maxWidth: .infinity)
                                            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
                .background(Color(.systemGroupedBackground))

                // Fullscreen zoomable image preview (per-photo)
                if let previewId = previewImageId,
                   let photo = photoData.first(where: { $0.id == previewId }) {
                    ZoomableImageView(image: photo.image) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            previewImageId = nil
                        }
                    }
                    .transition(.opacity)
                }

                // Fullscreen zoomable image preview (monument header photo)
                if showMonumentPreview, let img = monumentPreviewImage {
                    ZStack(alignment: .bottom) {
                        ZoomableImageView(image: img) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showMonumentPreview = false
                            }
                        }

                        // Attribution bar
                        if monumentPhotoAttribution != nil || monumentPhotoLicense != nil {
                            VStack(spacing: 2) {
                                if let artist = monumentPhotoAttribution {
                                    Text("© \(artist)")
                                        .font(.caption2)
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                }
                                if let lic = monumentPhotoLicense {
                                    Text(lic)
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(.black.opacity(0.6))
                        }
                    }
                    .transition(.opacity)
                }

            }
            .navigationTitle(AppSettings.shared.l.uploadPhoto)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                    .accessibilityLabel(AppSettings.shared.l.isTR ? "Kapat" : "Close")
                }
            }
            .alert(AppSettings.shared.l.isTR ? "Giriş Gerekli" : "Login Required", isPresented: $showLoginAlert) {
                Button(AppSettings.shared.l.ok, role: .cancel) { }
            } message: {
                Text(AppSettings.shared.l.oauthNotReady)
            }
            .onAppear {
                fetchP373(qid: monument.wikidataId)
                fetchMonumentPhotoAttribution()
            }
            .sheet(isPresented: $showCategoryBrowser) {
                if let cat = commonsCategory {
                    CategoryBrowserView(categoryName: cat)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $showWikipediaPreview) {
                if let title = trwikiTitle {
                    WikipediaPreviewView(articleTitle: title)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $showSubcategoryPicker) {
                subcategoryPickerSheet
            }
            .sheet(isPresented: $showAddCategory) {
                addCategorySheet
            }
            .confirmationDialog(
                AppSettings.shared.l.isTR ? "Anıt Fotoğrafı" : "Monument Photo",
                isPresented: $showP18Confirm,
                titleVisibility: .visible
            ) {
                Button(AppSettings.shared.l.isTR ? "Evet, bunu seç" : "Yes, select this") {
                    if let idx = selectedP18Index {
                        setP18OnWikidata(photoIndex: idx)
                    }
                }
                Button(AppSettings.shared.l.isTR ? "İptal" : "Cancel", role: .cancel) {
                    selectedP18Index = nil
                }
            } message: {
                if let idx = selectedP18Index, idx < photoData.count {
                    Text(AppSettings.shared.l.isTR
                         ? "Bu fotoğraf, anıtın tanıtım görseli olarak ayarlanacak."
                         : "This photo will be set as the monument's main image.")
                }
            }
        }
    }

    // MARK: - Subcategory Picker Sheet
    @ViewBuilder
    private var subcategoryPickerSheet: some View {
        let isTR = AppSettings.shared.l.isTR
        NavigationStack {
            List {
                if subcategories.isEmpty {
                    Text(isTR ? "Alt kategori bulunamadı" : "No subcategories found")
                        .foregroundStyle(.secondary)
                } else {
                    Section {
                        Text(isTR
                             ? "Ana kategoriyle değiştirmek için bir alt kategori seçin. Ana kategori kaldırılıp seçtiğiniz eklenecek."
                             : "Select a subcategory to replace the parent category.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section(isTR ? "Alt Kategoriler" : "Subcategories") {
                        ForEach(subcategories, id: \.self) { subcat in
                            Button {
                                if let idx = subcategoryPhotoIndex, idx < photoData.count {
                                    withAnimation {
                                        // Replace parent with subcategory
                                        if let parentCat = commonsCategory {
                                            photoData[idx].categories.removeAll { $0 == parentCat }
                                        }
                                        if !photoData[idx].categories.contains(subcat) {
                                            photoData[idx].categories.append(subcat)
                                        }
                                        // Update filename to subcategory name + timestamp
                                        let ts: String
                                        if let d = photoData[idx].exifDate {
                                            ts = Self.tsFormatter.string(from: d)
                                        } else {
                                            ts = Self.tsFormatter.string(from: Date().addingTimeInterval(Double(idx)))
                                        }
                                        photoData[idx].fileName = "\(subcat) \(ts).jpg"
                                    }
                                    // Fetch Wikidata QID for the subcategory
                                    fetchCategoryQID(categoryName: subcat, photoIndex: idx)
                                }
                                showSubcategoryPicker = false
                            } label: {
                                Text(subcat)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(isTR ? "Alt Kategoriler" : "Subcategories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isTR ? "İptal" : "Cancel") {
                        showSubcategoryPicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Add Category Sheet
    @ViewBuilder
    private var addCategorySheet: some View {
        let isTR = AppSettings.shared.l.isTR
        NavigationStack {
            VStack(spacing: 0) {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(isTR ? "Kategori ara..." : "Search category...", text: $newCategoryText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { }
                    if !newCategoryText.isEmpty {
                        Button {
                            newCategoryText = ""
                            categorySuggestions = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.top, 8)
                .onChange(of: newCategoryText) { _, newValue in
                    searchCategories(query: newValue)
                }

                // Results
                if isSearchingCategories && categorySuggestions.isEmpty {
                    VStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if newCategoryText.count >= 2 && categorySuggestions.isEmpty && !isSearchingCategories {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                            .foregroundStyle(.quaternary)
                        Text(isTR ? "Kategori bulunamadı" : "No categories found")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else if newCategoryText.count < 2 {
                    VStack(spacing: 8) {
                        Spacer()
                        Text(isTR ? "En az 2 karakter yazın" : "Type at least 2 characters")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(categorySuggestions, id: \.self) { cat in
                            Button {
                                if let idx = addCategoryPhotoIndex, idx < photoData.count {
                                    if !photoData[idx].categories.contains(cat) {
                                        withAnimation { photoData[idx].categories.append(cat) }
                                    }
                                }
                                showAddCategory = false
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "folder")
                                        .foregroundStyle(.blue)
                                        .font(.caption)
                                    Text(cat)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(isTR ? "Kategori Ekle" : "Add Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isTR ? "İptal" : "Cancel") {
                        showAddCategory = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onDisappear {
            newCategoryText = ""
            categorySuggestions = []
        }
    }

    // MARK: - Search Commons categories
    private func searchCategories(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            categorySuggestions = []
            isSearchingCategories = false
            return
        }

        isSearchingCategories = true

        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "opensearch"),
            URLQueryItem(name: "namespace", value: "14"), // Category namespace
            URLQueryItem(name: "search", value: trimmed),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "format", value: "json"),
        ]

        guard let url = components.url else {
            isSearchingCategories = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("VASturkiye/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                isSearchingCategories = false
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
                      json.count >= 2,
                      let titles = json[1] as? [String] else {
                    categorySuggestions = []
                    return
                }
                // Remove "Category:" prefix
                categorySuggestions = titles.map { title in
                    title.hasPrefix("Category:") ? String(title.dropFirst(9)) : title
                }
            }
        }.resume()
    }

    // MARK: - Fetch monument photo attribution from Commons
    private func fetchMonumentPhotoAttribution() {
        guard !monument.imageUrl.isEmpty else { return }
        let filename: String
        if let fn = monument.imageFilename, !fn.isEmpty {
            filename = fn
        } else if let last = monument.imageUrl.components(separatedBy: "/").last?
            .components(separatedBy: "?").first {
            filename = last
        } else { return }

        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "titles", value: "File:\(filename)"),
            URLQueryItem(name: "prop", value: "imageinfo"),
            URLQueryItem(name: "iiprop", value: "extmetadata"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
        ]
        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.setValue("WLMTurkey/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let query = json["query"] as? [String: Any],
                      let pages = query["pages"] as? [[String: Any]],
                      let page = pages.first,
                      let imageinfo = page["imageinfo"] as? [[String: Any]],
                      let info = imageinfo.first,
                      let ext = info["extmetadata"] as? [String: Any] else { return }

                if let artist = ext["Artist"] as? [String: Any],
                   let artistVal = artist["value"] as? String {
                    let clean = artistVal.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    self.monumentPhotoAttribution = clean.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if let lic = ext["LicenseShortName"] as? [String: Any],
                   let licVal = lic["value"] as? String {
                    self.monumentPhotoLicense = licVal
                }
            }
        }.resume()
    }

    // MARK: - Fetch P373 (Commons category) & trwiki sitelink
    // MARK: - Set P18 on Wikidata
    private func setP18OnWikidata(photoIndex: Int) {
        guard photoIndex < photoData.count,
              let uploadedName = photoData[photoIndex].uploadedFileName else { return }

        isSettingP18 = true
        selectingP18Photo = false
        let isTR = AppSettings.shared.l.isTR

        WikimediaAuth.shared.setWikidataClaim(
            entityId: monument.wikidataId,
            property: "P18",
            value: uploadedName
        ) { result in
            isSettingP18 = false
            switch result {
            case .success:
                monumentHasP18 = true
                p18Success = true
                p18ResultMessage = isTR
                    ? "Fotoğraf anıtın tanıtım görseli olarak ayarlandı!"
                    : "Photo has been set as the monument's main image!"
                // Update header image immediately
                let encoded = uploadedName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? uploadedName
                resolvedImageUrl = "https://commons.wikimedia.org/wiki/Special:FilePath/\(encoded)?width=120"
                // Notify map to update marker color & popup image
                NotificationCenter.default.post(
                    name: .monumentPhotoUpdated,
                    object: nil,
                    userInfo: ["qid": monument.wikidataId, "filename": uploadedName]
                )
            case .failure(let error):
                p18Success = false
                p18ResultMessage = isTR
                    ? "Fotoğraf ayarlanamadı: \(error.localizedDescription)"
                    : "Could not set the photo: \(error.localizedDescription)"
            }
        }
    }

    private func fetchP373(qid: String) {
        isLoadingCategory = true

        var components = URLComponents(string: "https://www.wikidata.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "wbgetentities"),
            URLQueryItem(name: "ids", value: qid),
            URLQueryItem(name: "props", value: "claims|sitelinks|labels"),
            URLQueryItem(name: "languages", value: "en|tr"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
        ]

        guard let url = components.url else {
            isLoadingCategory = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("WLMTurkey/1.0", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                isLoadingCategory = false
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let entities = json["entities"] as? [String: Any],
                      let entity = entities[qid] as? [String: Any] else { return }

                if let claims = entity["claims"] as? [String: Any] {
                    // Check P18 (image)
                    if let p18 = claims["P18"] as? [[String: Any]],
                       let first = p18.first,
                       let mainsnak = first["mainsnak"] as? [String: Any],
                       let datavalue = mainsnak["datavalue"] as? [String: Any],
                       let filename = datavalue["value"] as? String,
                       !filename.isEmpty {
                        monumentHasP18 = true
                        // If header has no image, show the P18 image
                        if monument.imageUrl.isEmpty && resolvedImageUrl == nil {
                            let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename
                            resolvedImageUrl = "https://commons.wikimedia.org/wiki/Special:FilePath/\(encoded)?width=120"
                        }
                    } else {
                        monumentHasP18 = false
                    }

                    // Check P373 (Commons category)
                    if let p373 = claims["P373"] as? [[String: Any]],
                       let first = p373.first,
                       let mainsnak = first["mainsnak"] as? [String: Any],
                       let datavalue = mainsnak["datavalue"] as? [String: Any],
                       let value = datavalue["value"] as? String {
                        commonsCategory = value
                        // Add P373 category to all existing photos
                        for i in photoData.indices {
                            if !photoData[i].categories.contains(value) {
                                photoData[i].categories.append(value)
                            }
                        }
                        // Fetch subcategories
                        fetchSubcategories(of: value)
                    }
                }

                // Labels (EN + TR)
                if let labels = entity["labels"] as? [String: Any] {
                    if let enLabel = labels["en"] as? [String: Any],
                       let enValue = enLabel["value"] as? String {
                        labelEn = enValue
                    }
                    if let trLabel = labels["tr"] as? [String: Any],
                       let trValue = trLabel["value"] as? String {
                        labelTr = trValue
                    }
                }

                let wikiKey = AppSettings.shared.language == "tr" ? "trwiki" : "enwiki"
                if let sitelinks = entity["sitelinks"] as? [String: Any],
                   let wiki = sitelinks[wikiKey] as? [String: Any],
                   let title = wiki["title"] as? String {
                    trwikiTitle = title
                }
            }
        }.resume()
    }
}
