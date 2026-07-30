import SwiftUI

struct ModelLogoView: View {
    let family: ModelInfo.ModelFamily
    var size: CGFloat = 40

    var body: some View {
        Group {
            switch family {
            case .custom:
                Circle()
                    .fill(Color.secondary.opacity(0.12))
                    .overlay {
                        Image(systemName: "externaldrive.fill")
                            .font(.system(size: size * 0.42, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
            case .mistral3:
                Image(family.logoName)
                    .resizable()
                    .scaledToFit()
            case .lfm2, .lfm25:
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.05, green: 0.08, blue: 0.18),
                                Color(red: 0.16, green: 0.22, blue: 0.42)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Image(systemName: "drop.fill")
                            .font(.system(size: size * 0.42, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            case .bonsai:
                Image(family.logoName)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .padding(size * 0.18)
                    .foregroundStyle(.primary)
            default:
                Image(family.logoName)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 1))
    }
}
