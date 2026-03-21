import SwiftUI

struct OnboardingView: View {
    @Binding var hasSeenOnboarding: Bool
    @State private var currentPage = 0
    private let l = AppSettings.shared.l

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    // Page 1 — WLM Tanıtım
                    onboardingPage(
                        icon: "building.columns.fill",
                        iconColor: .red,
                        title: l.onboardingTitle1,
                        subtitle: l.onboardingSubtitle1,
                        bullets: [
                            ("globe.europe.africa", l.onboarding1Bullet1),
                            ("camera.fill", l.onboarding1Bullet2),
                            ("photo.stack", l.onboarding1Bullet3),
                            ("heart.fill", l.onboarding1Bullet4),
                        ]
                    )
                    .tag(0)

                    // Page 2 — Nasıl çalışır
                    onboardingPage(
                        icon: "map.fill",
                        iconColor: .blue,
                        title: l.onboardingTitle2,
                        subtitle: l.onboardingSubtitle2,
                        bullets: [
                            ("mappin.and.ellipse", l.onboarding2Bullet1),
                            ("magnifyingglass", l.onboarding2Bullet2),
                            ("arrow.up.circle.fill", l.onboarding2Bullet3),
                            ("checkmark.seal.fill", l.onboarding2Bullet4),
                        ]
                    )
                    .tag(1)

                    // Page 3 — Fotoğraf ipuçları
                    onboardingPage(
                        icon: "camera.viewfinder",
                        iconColor: .orange,
                        title: l.onboardingTitle3,
                        subtitle: l.onboardingSubtitle3,
                        bullets: [
                            ("sun.max.fill", l.onboarding3Bullet1),
                            ("arrow.up.left.and.arrow.down.right", l.onboarding3Bullet2),
                            ("figure.walk", l.onboarding3Bullet3),
                            ("location.fill", l.onboarding3Bullet4),
                            ("text.below.photo", l.onboarding3Bullet5),
                            ("iphone.landscape", l.onboarding3Bullet6),
                            ("aspectratio", l.onboarding3Bullet7),
                            ("moon.stars.fill", l.onboarding3Bullet8),
                        ]
                    )
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                // Bottom button
                Button {
                    if currentPage < 2 {
                        withAnimation { currentPage += 1 }
                    } else {
                        hasSeenOnboarding = true
                    }
                } label: {
                    Text(currentPage < 2 ? l.continueButton : l.startButton)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.red)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

                if currentPage < 2 {
                    Button(l.skipButton) {
                        hasSeenOnboarding = true
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 16)
                } else {
                    Spacer().frame(height: 40)
                }
            }
        }
    }

    private func onboardingPage(icon: String, iconColor: Color, title: String, subtitle: String, bullets: [(String, String)]) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer().frame(height: 40)

                Image(systemName: icon)
                    .font(.system(size: 56))
                    .foregroundStyle(iconColor)
                    .padding(.bottom, 4)

                Text(title)
                    .font(.title.weight(.bold))

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 16) {
                    ForEach(bullets.indices, id: \.self) { i in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: bullets[i].0)
                                .font(.system(size: 18))
                                .foregroundStyle(iconColor.opacity(0.8))
                                .frame(width: 28, alignment: .center)
                            Text(bullets[i].1)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 12)

                Spacer().frame(height: 60)
            }
        }
        .scrollIndicators(.hidden)
    }
}
