import SwiftUI
import CoreLocation

// MARK: - Location Manager
@Observable
class LocationManager: NSObject, CLLocationManagerDelegate {
    var location: CLLocation?
    var heading: CLHeading?
    var status: CLAuthorizationStatus = .notDetermined
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                manager.startUpdatingHeading()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        if newHeading.headingAccuracy >= 0 {
            heading = newHeading
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error)")
    }
}

// MARK: - Map ViewModel
@Observable
class MapViewModel {
    var monuments: [Monument] = [] // visible in current viewport
    var isLoading = false
    var errorMessage: String?

    private var allMonuments: [Monument] = []

    /// Spatial index: grid cells mapping to monument indices for O(1) viewport queries
    private var spatialGrid: [String: [Int]] = [:]
    private let gridSize: Double = 0.5 // degrees per grid cell

    /// Load all monuments from bundled/cached JSON
    func loadMonuments() {
        guard allMonuments.isEmpty else { return }
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = MonumentStore.load()
            DispatchQueue.main.async {
                self.allMonuments = loaded
                self.buildSpatialIndex()
                self.monuments = loaded // show all initially, viewport will filter
                self.isLoading = false
                // Check for remote update in background
                MonumentStore.checkForUpdate { updated in
                    if !updated.isEmpty {
                        self.allMonuments = updated
                        self.buildSpatialIndex()
                        self.monuments = updated
                    }
                }
            }
        }
    }

    /// Build spatial index for fast viewport filtering
    private func buildSpatialIndex() {
        spatialGrid.removeAll()
        for (index, m) in allMonuments.enumerated() {
            let key = gridKey(lat: m.latitude, lon: m.longitude)
            spatialGrid[key, default: []].append(index)
        }
    }

    private func gridKey(lat: Double, lon: Double) -> String {
        let latCell = Int(floor(lat / gridSize))
        let lonCell = Int(floor(lon / gridSize))
        return "\(latCell),\(lonCell)"
    }

    /// Filter monuments to viewport bounds using spatial index
    func filterToViewport(south: Double, north: Double, west: Double, east: Double) {
        // Determine which grid cells overlap the viewport
        let minLatCell = Int(floor(south / gridSize))
        let maxLatCell = Int(floor(north / gridSize))
        let minLonCell = Int(floor(west / gridSize))
        let maxLonCell = Int(floor(east / gridSize))

        var visible: [Monument] = []
        for latCell in minLatCell...maxLatCell {
            for lonCell in minLonCell...maxLonCell {
                let key = "\(latCell),\(lonCell)"
                if let indices = spatialGrid[key] {
                    for idx in indices {
                        let m = allMonuments[idx]
                        if m.latitude >= south && m.latitude <= north &&
                           m.longitude >= west && m.longitude <= east {
                            visible.append(m)
                        }
                    }
                }
            }
        }
        monuments = visible
    }

    /// Reload monuments (e.g. after language change — names are computed, just trigger refresh)
    func refreshForLanguageChange() {
        let current = monuments
        monuments = current
    }

    /// Update a monument's photo status after P18 is set on Wikidata
    func markMonumentAsPhotographed(wikidataId: String, imageFilename: String) {
        // Update in allMonuments
        if let idx = allMonuments.firstIndex(where: { $0.wikidataId == wikidataId }) {
            allMonuments[idx].hasPhoto = true
            allMonuments[idx].imageFilename = imageFilename
        }
        // Update in visible monuments
        if let idx = monuments.firstIndex(where: { $0.wikidataId == wikidataId }) {
            monuments[idx].hasPhoto = true
            monuments[idx].imageFilename = imageFilename
        }
    }
}
