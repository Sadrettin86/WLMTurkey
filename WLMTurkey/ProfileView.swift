import SwiftUI
import AuthenticationServices

struct ProfileView: View {
    @Environment(AppSettings.self) private var settings
    @State private var showAbout = false
    @State private var showTips = false
    @State private var showOnboarding = false
    @State private var totalMonuments = 0
    @State private var withPhoto = 0
    @State private var withoutPhoto = 0
    @State private var showLogoutConfirm = false

    var body: some View {
        let l = settings.l

        NavigationStack {
            List {
                // Dashboard
                Section(l.dashboardTitle) {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            dashboardCard(
                                icon: "building.columns.fill",
                                color: .blue,
                                value: formatNumber(totalMonuments),
                                label: l.totalMonuments
                            )
                            dashboardCard(
                                icon: "checkmark.circle.fill",
                                color: .green,
                                value: formatNumber(withPhoto),
                                label: l.withPhotoCount
                            )
                        }
                        HStack(spacing: 12) {
                            dashboardCard(
                                icon: "camera.fill",
                                color: .red,
                                value: formatNumber(withoutPhoto),
                                label: l.withoutPhotoCount
                            )
                            dashboardCard(
                                icon: "chart.pie.fill",
                                color: .purple,
                                value: totalMonuments > 0 ? "\(Int(Double(withPhoto) / Double(totalMonuments) * 100))%" : "–",
                                label: l.coverageRate
                            )
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                // Account section
                Section {
                    if WikimediaAuth.shared.isLoggedIn {
                        HStack(spacing: 14) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(WikimediaAuth.shared.username ?? "Wikimedia")
                                    .font(.headline)
                                Text(l.isTR ? "Wikimedia hesabı bağlı" : "Wikimedia account connected")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)

                        Button(role: .destructive) {
                            showLogoutConfirm = true
                        } label: {
                            HStack {
                                Image(systemName: "arrow.left.circle.fill")
                                    .foregroundStyle(.red)
                                Text(l.isTR ? "Çıkış yap" : "Log out")
                                    .foregroundStyle(.red)
                            }
                        }
                        .confirmationDialog(
                            l.isTR ? "Çıkış yapılsın mı?" : "Log out?",
                            isPresented: $showLogoutConfirm,
                            titleVisibility: .visible
                        ) {
                            Button(l.isTR ? "Çıkış yap" : "Log out", role: .destructive) {
                                WikimediaAuth.shared.logout()
                            }
                        }
                    } else {
                        HStack(spacing: 14) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(.gray.opacity(0.5))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(l.notLoggedIn)
                                    .font(.headline)
                                Text(l.loginHint)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)

                        OAuthLoginButton()
                    }
                }

                // Settings
                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label(l.settings, systemImage: "gearshape")
                    }
                }

                // About WLM
                Section(l.about) {
                    Button {
                        withAnimation { showAbout.toggle() }
                    } label: {
                        HStack {
                            Label(l.whatIsWLM, systemImage: "building.columns")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: showAbout ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if showAbout {
                        VStack(alignment: .leading, spacing: 12) {
                            aboutItem(
                                icon: "globe.europe.africa",
                                color: .blue,
                                title: l.internationalContest,
                                text: l.internationalContestDesc
                            )
                            aboutItem(
                                icon: "flag.fill",
                                color: .red,
                                title: l.wlmInTurkey,
                                text: l.wlmInTurkeyDesc
                            )
                            aboutItem(
                                icon: "w.circle.fill",
                                color: .black,
                                title: l.valueForWikipedia,
                                text: l.valueForWikipediaDesc
                            )
                            aboutItem(
                                icon: "trophy.fill",
                                color: .orange,
                                title: l.awards,
                                text: l.awardsDesc
                            )

                            Link(destination: URL(string: "https://www.wikilovesmonuments.org")!) {
                                HStack {
                                    Text(l.moreInfo)
                                        .font(.subheadline)
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.caption)
                                }
                                .foregroundStyle(.blue)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Photo tips
                Section(l.photoTipsTitle) {
                    Button {
                        withAnimation { showTips.toggle() }
                    } label: {
                        HStack {
                            Label(l.tipsAndSuggestions, systemImage: "lightbulb.fill")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: showTips ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if showTips {
                        VStack(alignment: .leading, spacing: 14) {
                            tipItem(number: "1", title: l.tipRightLight, text: l.tipRightLightDesc)
                            tipItem(number: "2", title: l.tipFullFrame, text: l.tipFullFrameDesc)
                            tipItem(number: "3", title: l.tipCleanFrame, text: l.tipCleanFrameDesc)
                            tipItem(number: "4", title: l.tipDetails, text: l.tipDetailsDesc)
                            tipItem(number: "5", title: l.tipLandscape, text: l.tipLandscapeDesc)
                            tipItem(number: "6", title: l.tipLocation, text: l.tipLocationDesc)
                            tipItem(number: "7", title: l.tipResolution, text: l.tipResolutionDesc)
                            tipItem(number: "8", title: l.tipStraight, text: l.tipStraightDesc)
                            tipItem(number: "9", title: l.tipAspectRatio, text: l.tipAspectRatioDesc)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Show onboarding again
                Section {
                    Button {
                        showOnboarding = true
                    } label: {
                        Label(l.showOnboardingAgain, systemImage: "arrow.counterclockwise")
                            .foregroundStyle(.primary)
                    }
                }

                // Links
                Section(l.links) {
                    Link(destination: URL(string: "https://commons.wikimedia.org")!) {
                        Label("Wikimedia Commons", systemImage: "globe")
                            .foregroundStyle(.primary)
                    }
                    Link(destination: URL(string: "https://www.wikidata.org")!) {
                        Label(settings.l.wikidataLabel, systemImage: "server.rack")
                            .foregroundStyle(.primary)
                    }
                    Link(destination: URL(string: "https://www.wikilovesmonuments.org")!) {
                        Label(settings.l.wlmTurkey.components(separatedBy: " – ").first ?? "Wiki Loves Monuments", systemImage: "building.columns")
                            .foregroundStyle(.primary)
                    }
                }

                // App info
                Section {
                    HStack {
                        Text(l.version)
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(l.profileTitle)
            .onAppear {
                let all = MonumentStore.load()
                totalMonuments = all.count
                withPhoto = all.filter(\.hasPhoto).count
                withoutPhoto = totalMonuments - withPhoto
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView(hasSeenOnboarding: Binding(
                    get: { !showOnboarding },
                    set: { if $0 { showOnboarding = false } }
                ))
            }
        }
    }

    private func aboutItem(icon: String, color: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
                .frame(width: 26, alignment: .center)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tipItem(number: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.orange, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func dashboardCard(icon: String, color: Color, value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// MARK: - OAuth Login Button
struct OAuthLoginButton: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Button {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootVC = window.rootViewController {
                let anchor = AuthAnchor(window: window)
                WikimediaAuth.shared.login(from: anchor)
            }
        } label: {
            HStack {
                if WikimediaAuth.shared.isLoggingIn {
                    ProgressView()
                        .controlSize(.small)
                    Text(settings.l.isTR ? "Giriş yapılıyor..." : "Logging in...")
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(.blue)
                    Text(settings.l.loginWithWikimedia)
                        .foregroundStyle(.primary)
                }
            }
        }
        .disabled(WikimediaAuth.shared.isLoggingIn)
    }
}

// MARK: - ASWebAuthenticationSession Anchor
class AuthAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    let window: UIWindow

    init(window: UIWindow) {
        self.window = window
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        window
    }
}
