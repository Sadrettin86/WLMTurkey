import SwiftUI

// MARK: - Logo Helpers
@ViewBuilder
func wikipediaLogo(size: CGFloat) -> some View {
    Text("W")
        .font(.system(size: size * 0.7, weight: .bold, design: .serif))
        .foregroundStyle(.primary)
        .frame(width: size, height: size)
        .background(
            RoundedRectangle(cornerRadius: size * 0.2)
                .fill(Color(.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.2)
                        .strokeBorder(Color(.systemGray3), lineWidth: 0.5)
                )
        )
}

@ViewBuilder
func commonsLogo(size: CGFloat) -> some View {
    ZStack {
        Circle()
            .fill(Color(.systemGray6))
            .overlay(
                Circle()
                    .strokeBorder(Color(.systemGray3), lineWidth: 0.5)
            )
        Image(systemName: "infinity")
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(.blue)
    }
    .frame(width: size, height: size)
}
