import SwiftUI
import CoreLocation

// MARK: - Map Tab View
struct MapTabView: View {
    @Binding var focusCoordinate: (lat: Double, lon: Double)?
    @State private var locationManager = LocationManager()
    @State private var vm = MapViewModel()
    @State private var filter: FilterOption = .all
    @State private var mapAction: MapAction = .none
    @State private var uploadMonument: UploadMonumentInfo?
    @AppStorage("welcomeCardShownCount") private var welcomeCardShownCount = 0
    @State private var showWelcomeCard = false
    @State private var isMapReady = false
    @State private var showSplash = true
    @State private var splashOpacity: Double = 1.0
    @State private var isFollowingUser = false

    enum FilterOption: CaseIterable {
        case all
        case withoutPhoto
        case withPhoto

        func label(_ l: Strings) -> String {
            switch self {
            case .all: return l.filterAll
            case .withoutPhoto: return l.filterWithoutPhoto
            case .withPhoto: return l.filterWithPhoto
            }
        }
    }

    var filtered: [Monument] {
        switch filter {
        case .all: return vm.monuments
        case .withoutPhoto: return vm.monuments.filter { !$0.hasPhoto }
        case .withPhoto: return vm.monuments.filter { $0.hasPhoto }
        }
    }

    var userLat: Double { locationManager.location?.coordinate.latitude ?? 41.0082 }
    var userLon: Double { locationManager.location?.coordinate.longitude ?? 28.9784 }
    var userHeading: Double { locationManager.heading?.trueHeading ?? 0 }

    var body: some View {
        let l = AppSettings.shared.l
        let network = NetworkMonitor.shared

        ZStack(alignment: .top) {
            LeafletMapView(
                monuments: filtered,
                userLat: userLat,
                userLon: userLon,
                userHeading: userHeading,
                mapAction: mapAction,
                onUploadTap: { info in
                    uploadMonument = info
                },
                onViewportChanged: { south, north, west, east, zoom in
                    vm.filterToViewport(south: south, north: north, west: west, east: east)
                },
                onMapReady: {
                    isMapReady = true
                },
                onFollowModeChanged: { following in
                    isFollowingUser = following
                }
            )
            .ignoresSafeArea()
            .onChange(of: mapAction) { _, val in
                if val != .none {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        mapAction = .none
                    }
                }
            }

            GeometryReader { geo in
                VStack(spacing: 0) {
                    Picker("Filtre", selection: $filter) {
                        ForEach(FilterOption.allCases, id: \.self) { opt in
                            Text(opt.label(l)).tag(opt)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, geo.safeAreaInsets.top + 4)
                    .padding(.bottom, 8)
                    .background(.ultraThinMaterial)
                    Spacer()
                }
                .ignoresSafeArea(edges: .top)
            }

            // Map controls
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 0) {
                        Button { mapAction = .zoomIn } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.blue)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(l.isTR ? "Yakınlaştır" : "Zoom in")
                        Divider().frame(width: 30)
                        Button { mapAction = .zoomOut } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.blue)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(l.isTR ? "Uzaklaştır" : "Zoom out")
                    }
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    .padding(.trailing, 16)
                    .padding(.bottom, 12)
                }
                HStack {
                    Spacer()
                    Button { mapAction = .centerOnUser } label: {
                        Image(systemName: isFollowingUser ? "location.fill" : "location")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(isFollowingUser ? .white : .blue)
                            .frame(width: 44, height: 44)
                            .background(
                                isFollowingUser
                                    ? AnyShapeStyle(.blue)
                                    : AnyShapeStyle(.ultraThinMaterial),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    }
                    .accessibilityLabel(l.isTR ? "Konumuma git" : "Go to my location")
                    .padding(.trailing, 16)
                    .padding(.bottom, 100)
                }
            }

            // Offline banner
            if !network.isConnected {
                VStack {
                    OfflineBanner(message: l.isTR ? "İnternet bağlantısı yok" : "No internet connection")
                        .padding(.top, 100)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: network.isConnected)
            }

            if vm.isLoading {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vm.monuments.isEmpty ? l.monumentsLoading : l.monumentsUpdating)
                                .font(.caption.weight(.medium))
                            if !vm.monuments.isEmpty {
                                Text(l.cachedMonuments(vm.monuments.count))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    .padding(.bottom, 90)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: vm.isLoading)
            }

            if let err = vm.errorMessage {
                VStack {
                    Spacer()
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .padding(.bottom, 90)
                }
            }

            // Welcome card
            if showWelcomeCard && !vm.monuments.isEmpty {
                let noPhotoCount = vm.monuments.filter { !$0.hasPhoto }.count
                VStack {
                    Spacer()
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "building.columns.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)
                                .frame(width: 44, height: 44)
                                .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(.init(l.welcomeTitle(vm.monuments.count)))
                                    .font(.subheadline.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(l.welcomeSubtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(spacing: 16) {
                            statPill(
                                icon: "camera.fill",
                                color: .red,
                                value: "\(noPhotoCount)",
                                label: l.welcomeNoPhoto
                            )
                            statPill(
                                icon: "checkmark.circle.fill",
                                color: .green,
                                value: "\(vm.monuments.count - noPhotoCount)",
                                label: l.filterWithPhoto
                            )
                        }

                        Button {
                            withAnimation(.easeOut(duration: 0.3)) {
                                showWelcomeCard = false
                            }
                        } label: {
                            Text(l.welcomeDismiss)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 96)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Splash overlay
            if showSplash {
                SplashOverlayView(opacity: splashOpacity)
            }
        }
        .onChange(of: isMapReady) { _, ready in
            if ready && !vm.monuments.isEmpty {
                dismissSplash()
            }
        }
        .onChange(of: vm.monuments.isEmpty) { _, empty in
            if !empty && isMapReady {
                dismissSplash()
            }
        }
        .onAppear {
            vm.loadMonuments()
            if welcomeCardShownCount < 3 {
                welcomeCardShownCount += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        showWelcomeCard = true
                    }
                }
            }
        }
        .onChange(of: AppSettings.shared.language) { _, _ in
            vm.refreshForLanguageChange()
        }
        .onChange(of: focusCoordinate?.lat) { _, _ in
            if let coord = focusCoordinate {
                mapAction = .focusOn(lat: coord.lat, lon: coord.lon)
                focusCoordinate = nil
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
        .onReceive(NotificationCenter.default.publisher(for: .monumentPhotoUpdated)) { notification in
            guard let info = notification.userInfo,
                  let qid = info["qid"] as? String,
                  let filename = info["filename"] as? String else { return }
            vm.markMonumentAsPhotographed(wikidataId: qid, imageFilename: filename)
        }
    }

    private func dismissSplash() {
        // Wait extra time for markers to actually render in WebView
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 0.5)) {
                splashOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                showSplash = false
            }
        }
    }

    private func statPill(icon: String, color: Color, value: String, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.bold))
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Splash Overlay
struct SplashOverlayView: View {
    let opacity: Double
    var body: some View {
        ZStack {
            Color(.systemBackground)

            VStack(spacing: 0) {
                Spacer()

                // WLM Logo — always visible, no animation
                Image("WLMLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 280)

                Spacer().frame(height: 80)

                // Loading indicator — always present, fixed height
                VStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { i in
                        ShimmerBar(width: [280, 220, 250][i])
                    }

                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.secondary)
                        Text(AppSettings.shared.l.isTR ? "Harita hazırlanıyor…" : "Preparing map…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }

                Spacer()
            }
        }
        .ignoresSafeArea()
        .opacity(opacity)
    }
}

// MARK: - Shimmer Bar
struct ShimmerBar: View {
    let width: CGFloat
    @State private var shimmerOffset: CGFloat = -200

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(.systemGray5))
            .frame(width: width, height: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [.clear, Color(.systemGray4).opacity(0.6), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: shimmerOffset)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    shimmerOffset = 300
                }
            }
    }
}
