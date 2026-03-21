import Foundation

// MARK: - Monument Store (Bundled + Remote Update)
struct MonumentStore {
    private static let remoteFileName = "monuments_remote.json"
    private static let lastCheckKey = "monuments_last_remote_check"
    private static let remoteVersionKey = "monuments_remote_version"
    private static let checkInterval: TimeInterval = 7 * 24 * 3600 // 7 days

    static var remoteFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(remoteFileName)
    }

    /// Load monuments: prefer remote cache, fallback to bundled
    static func load() -> [Monument] {
        // Try remote (downloaded) file first
        if let data = try? Data(contentsOf: remoteFileURL),
           let monuments = parse(data: data), !monuments.isEmpty {
            return monuments
        }
        // Fallback to bundled
        guard let url = Bundle.main.url(forResource: "monuments", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let monuments = parse(data: data) else {
            return []
        }
        return monuments
    }

    /// Read the version (date) from the active monuments JSON
    static func dataVersion() -> String? {
        let data: Data?
        if let remoteData = try? Data(contentsOf: remoteFileURL) {
            data = remoteData
        } else if let url = Bundle.main.url(forResource: "monuments", withExtension: "json") {
            data = try? Data(contentsOf: url)
        } else {
            data = nil
        }
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["version"] as? String
    }

    /// Parse the compact JSON format
    private static func parse(data: Data) -> [Monument]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["monuments"] as? [[String: Any]] else { return nil }
        return items.compactMap { d in
            guard let qid = d["q"] as? String,
                  let nameTr = d["n"] as? String,
                  let nameEn = d["ne"] as? String,
                  let lat = d["la"] as? Double,
                  let lon = d["lo"] as? Double,
                  let hasPhoto = d["p"] as? Bool else { return nil }
            return Monument(
                id: qid, nameTr: nameTr, nameEn: nameEn,
                latitude: lat, longitude: lon, hasPhoto: hasPhoto,
                imageFilename: (d["i"] as? String)?.isEmpty == true ? nil : d["i"] as? String, wikidataId: qid,
                osmRelationId: d["r"] as? String, osmWayId: d["w"] as? String,
                instanceOfTr: d["t"] as? String, instanceOfEn: d["te"] as? String,
                adminEntityTr: d["a"] as? String, adminEntityEn: d["ae"] as? String,
                heritageDesigTr: d["h"] as? String, heritageDesigEn: d["he"] as? String,
                architectTr: d["ar"] as? String, architectEn: d["are"] as? String,
                archStyleTr: d["s"] as? String, archStyleEn: d["se"] as? String
            )
        }
    }

    /// Check for remote update if enough time has passed
    static func checkForUpdate(completion: (([Monument]) -> Void)? = nil) {
        let lastCheck = UserDefaults.standard.double(forKey: lastCheckKey)
        let elapsed = Date().timeIntervalSince1970 - lastCheck
        guard elapsed > checkInterval || lastCheck == 0 else {
            completion?([]); return
        }

        guard let url = URL(string: "https://raw.githubusercontent.com/Sadrettin86/WLMTurkey/main/monuments.json") else {
            completion?([]); return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("WLMTurkey/1.0", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
            guard let data = data, error == nil,
                  let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200,
                  let monuments = parse(data: data), !monuments.isEmpty else {
                DispatchQueue.main.async { completion?([]) }
                return
            }
            // Save to local cache
            try? data.write(to: remoteFileURL)
            DispatchQueue.main.async { completion?(monuments) }
        }.resume()
    }

    // MARK: - QID lookup cache
    private static var qidLabelCache: [String: (tr: String, en: String)]?

    /// Look up monument label by QID from bundled/cached data
    static func labelForQID(_ qid: String) -> String? {
        if qidLabelCache == nil {
            buildLabelCache()
        }
        guard let entry = qidLabelCache?[qid] else { return nil }
        return AppSettings.shared.language == "tr" ? entry.tr : entry.en
    }

    /// Clear the in-memory QID cache to free memory
    static func clearLabelCache() {
        qidLabelCache = nil
    }

    private static func buildLabelCache() {
        var cache = [String: (tr: String, en: String)]()
        let data: Data?
        if let remoteData = try? Data(contentsOf: remoteFileURL) {
            data = remoteData
        } else if let url = Bundle.main.url(forResource: "monuments", withExtension: "json") {
            data = try? Data(contentsOf: url)
        } else {
            data = nil
        }
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["monuments"] as? [[String: Any]] else {
            qidLabelCache = cache
            return
        }
        for d in items {
            guard let qid = d["q"] as? String,
                  let nameTr = d["n"] as? String,
                  let nameEn = d["ne"] as? String else { continue }
            cache[qid] = (tr: nameTr, en: nameEn)
        }
        qidLabelCache = cache
    }
}
