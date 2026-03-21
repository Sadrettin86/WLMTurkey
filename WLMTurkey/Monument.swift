import Foundation

// MARK: - Notifications
extension Notification.Name {
    static let monumentPhotoUpdated = Notification.Name("monumentPhotoUpdated")
}

// MARK: - Monument Model
struct Monument: Identifiable {
    let id: String
    let nameTr: String
    let nameEn: String
    let latitude: Double
    let longitude: Double
    var hasPhoto: Bool
    var imageFilename: String?
    let wikidataId: String
    let osmRelationId: String?
    let osmWayId: String?
    // Detail properties
    let instanceOfTr: String?
    let instanceOfEn: String?
    let adminEntityTr: String?
    let adminEntityEn: String?
    let heritageDesigTr: String?
    let heritageDesigEn: String?
    let architectTr: String?
    let architectEn: String?
    let archStyleTr: String?
    let archStyleEn: String?

    var name: String {
        AppSettings.shared.language == "tr" ? nameTr : nameEn
    }

    var imageUrl: String? {
        guard let fn = imageFilename, !fn.isEmpty else { return nil }
        return "https://commons.wikimedia.org/wiki/Special:FilePath/\(fn)?width=120"
    }

    var instanceOf: String? {
        let v = AppSettings.shared.language == "tr" ? instanceOfTr : instanceOfEn
        return v?.isEmpty == true ? nil : v
    }
    var adminEntity: String? {
        let v = AppSettings.shared.language == "tr" ? adminEntityTr : adminEntityEn
        return v?.isEmpty == true ? nil : v
    }
    var heritageDesig: String? {
        let v = AppSettings.shared.language == "tr" ? heritageDesigTr : heritageDesigEn
        return v?.isEmpty == true ? nil : v
    }
    var architect: String? {
        let v = AppSettings.shared.language == "tr" ? architectTr : architectEn
        return v?.isEmpty == true ? nil : v
    }
    var archStyle: String? {
        let v = AppSettings.shared.language == "tr" ? archStyleTr : archStyleEn
        return v?.isEmpty == true ? nil : v
    }
}

// MARK: - Upload Monument Info
struct UploadMonumentInfo: Identifiable {
    var id: String { wikidataId }
    let name: String
    let wikidataId: String
    var imageUrl: String
    var imageFilename: String?
    // Detail properties
    var instanceOf: String?
    var adminEntity: String?
    var heritageDesig: String?
    var architect: String?
    var archStyle: String?
}

// MARK: - Map State
enum MapAction: Equatable {
    case none
    case centerOnUser
    case zoomIn
    case zoomOut
    case focusOn(lat: Double, lon: Double)
}

struct SavedMapPosition {
    static let latKey = "map_last_lat"
    static let lonKey = "map_last_lon"
    static let zoomKey = "map_last_zoom"

    static func save(lat: Double, lon: Double, zoom: Int) {
        UserDefaults.standard.set(lat, forKey: latKey)
        UserDefaults.standard.set(lon, forKey: lonKey)
        UserDefaults.standard.set(zoom, forKey: zoomKey)
    }

    static func load() -> (lat: Double, lon: Double, zoom: Int)? {
        let ud = UserDefaults.standard
        guard ud.object(forKey: latKey) != nil else { return nil }
        return (ud.double(forKey: latKey), ud.double(forKey: lonKey), max(ud.integer(forKey: zoomKey), 2))
    }
}

// MARK: - OSM Boundary Cache
struct OSMBoundaryCache {
    private static let cacheFileName = "osm_boundaries_cache.json"

    static var cacheFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(cacheFileName)
    }

    static func save(jsonString: String) {
        try? jsonString.data(using: .utf8)?.write(to: cacheFileURL)
    }

    static func loadJSONString() -> String? {
        guard let data = try? Data(contentsOf: cacheFileURL),
              let str = String(data: data, encoding: .utf8),
              !str.isEmpty else { return nil }
        return str
    }
}

// MARK: - WLM Year Helper
struct WLMYear {
    /// Current WLM year — uses the current calendar year
    static var current: Int {
        Calendar.current.component(.year, from: Date())
    }

    /// Category name for Commons uploads
    static var categoryName: String {
        "Images from Wiki Loves Monuments \(current) in Turkey"
    }
}
