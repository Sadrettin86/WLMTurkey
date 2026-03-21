import SwiftUI

struct ContentView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @Environment(AppSettings.self) private var settings
    @State private var selectedTab = 0
    @State private var mapFocusCoordinate: (lat: Double, lon: Double)?
    @State private var photosTabBadge: Int = 0

    var body: some View {
        if hasSeenOnboarding {
            TabView(selection: $selectedTab) {
                MapTabView(focusCoordinate: $mapFocusCoordinate)
                    .tabItem {
                        Label(settings.l.tabMap, systemImage: "map.fill")
                    }
                    .tag(0)

                SearchView(onShowOnMap: { lat, lon in
                    mapFocusCoordinate = (lat, lon)
                    selectedTab = 0
                })
                    .tabItem {
                        Label(settings.l.tabSearch, systemImage: "magnifyingglass")
                    }
                    .tag(1)

                PhotosView(onShowOnMap: { lat, lon in
                    mapFocusCoordinate = (lat, lon)
                    selectedTab = 0
                })
                    .tabItem {
                        Label(settings.l.tabPhotos, systemImage: "photo.stack")
                    }
                    .tag(2)
                    .badge(photosTabBadge > 0 ? "\(photosTabBadge)" : nil)

                ProfileView()
                    .tabItem {
                        Label(settings.l.tabProfile, systemImage: "person.circle")
                    }
                    .tag(3)
            }
            .onChange(of: selectedTab) { _, newTab in
                if newTab == 2 {
                    photosTabBadge = 0
                    // Save current count as "seen"
                    let current = UserDefaults.standard.integer(forKey: "wlm_category_current_count")
                    if current > 0 {
                        UserDefaults.standard.set(current, forKey: "wlm_category_last_seen_count")
                    }
                }
            }
            .onAppear {
                fetchCategoryCountForBadge()
            }
        } else {
            OnboardingView(hasSeenOnboarding: $hasSeenOnboarding)
        }
    }

    private func fetchCategoryCountForBadge() {
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

                UserDefaults.standard.set(total, forKey: "wlm_category_current_count")

                let lastSeen = UserDefaults.standard.integer(forKey: "wlm_category_last_seen_count")
                if lastSeen == 0 {
                    // First time — save as baseline, no badge
                    UserDefaults.standard.set(total, forKey: "wlm_category_last_seen_count")
                } else if total > lastSeen && self.selectedTab != 2 {
                    self.photosTabBadge = total - lastSeen
                }
            }
        }.resume()
    }
}
