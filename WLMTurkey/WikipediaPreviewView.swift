import SwiftUI

// MARK: - Wikipedia Preview View
struct WikipediaPreviewView: View {
    let articleTitle: String
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var summary: WikiSummary?
    @State private var errorMessage: String?

    struct WikiSummary {
        let title: String
        let extract: String
        let thumbnailUrl: String?
        let description: String?
        let articleUrl: String
    }

    var body: some View {
        let l = AppSettings.shared.l
        NavigationStack {
            Group {
                if isLoading {
                    VStack {
                        Spacer()
                        ProgressView(l.wikiLoading)
                            .font(.subheadline)
                        Spacer()
                    }
                } else if let error = errorMessage {
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
                } else if let s = summary {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if let thumbUrl = s.thumbnailUrl, let url = URL(string: thumbUrl) {
                                AsyncImage(url: url) { phase in
                                    if let image = phase.image {
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 220)
                                            .clipped()
                                            .accessibilityLabel(s.title)
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text(s.title)
                                    .font(.title2.weight(.bold))

                                if let desc = s.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .italic()
                                }

                                Divider()

                                Text(s.extract)
                                    .font(.body)
                                    .lineSpacing(4)

                                Divider()

                                Link(destination: URL(string: s.articleUrl)!) {
                                    HStack(spacing: 6) {
                                        wikipediaLogo(size: 18)
                                        Text(l.openInWiki)
                                            .font(.subheadline.weight(.medium))
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                            .font(.caption)
                                    }
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 14)
                                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 24)
                        }
                    }
                }
            }
            .navigationTitle(l.wikiTitle)
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
                fetchSummary()
            }
        }
    }

    private func fetchSummary() {
        isLoading = true
        let lang = AppSettings.shared.language
        let encoded = articleTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? articleTitle
        let urlStr = "https://\(lang).wikipedia.org/api/rest_v1/page/summary/\(encoded)"

        guard let url = URL(string: urlStr) else {
            isLoading = false
            errorMessage = AppSettings.shared.l.isTR ? "Geçersiz sayfa adı" : "Invalid page title"
            return
        }

        var request = URLRequest(url: url)
        request.setValue("WLMTurkey/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false

                if let error = error {
                    errorMessage = "\(AppSettings.shared.l.errorPrefix): \(error.localizedDescription)"
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    errorMessage = AppSettings.shared.l.dataUnavailable
                    return
                }

                let title = json["title"] as? String ?? articleTitle
                let extract = json["extract"] as? String ?? ""
                let description = json["description"] as? String
                let contentUrls = json["content_urls"] as? [String: Any]
                let mobile = contentUrls?["mobile"] as? [String: Any]
                let articleUrl = (mobile?["page"] as? String) ?? "https://\(lang).m.wikipedia.org/wiki/\(encoded)"

                var thumbnailUrl: String?
                if let thumb = json["thumbnail"] as? [String: Any] {
                    thumbnailUrl = thumb["source"] as? String
                }
                if let orig = json["originalimage"] as? [String: Any],
                   let origSrc = orig["source"] as? String {
                    thumbnailUrl = origSrc
                }

                if extract.isEmpty {
                    errorMessage = AppSettings.shared.l.isTR ? "Bu sayfa için içerik bulunamadı" : "No content found for this page"
                    return
                }

                summary = WikiSummary(
                    title: title,
                    extract: extract,
                    thumbnailUrl: thumbnailUrl,
                    description: description,
                    articleUrl: articleUrl
                )
            }
        }.resume()
    }
}
