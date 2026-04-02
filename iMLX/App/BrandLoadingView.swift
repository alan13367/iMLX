import SwiftUI

struct BrandLoadingView: View {
    let title: String
    let subtitle: String
    var showsProgress: Bool = true

    @State private var pulse = false
    @State private var drift = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.05, blue: 0.15),
                    Color(red: 0.05, green: 0.10, blue: 0.28),
                    Color(red: 0.17, green: 0.07, blue: 0.24)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(red: 0.31, green: 0.84, blue: 1.0).opacity(0.24))
                .frame(width: 360, height: 360)
                .blur(radius: 40)
                .offset(x: drift ? -120 : -70, y: drift ? -230 : -180)

            Circle()
                .fill(Color(red: 0.88, green: 0.43, blue: 1.0).opacity(0.20))
                .frame(width: 340, height: 340)
                .blur(radius: 36)
                .offset(x: drift ? 120 : 80, y: drift ? 220 : 170)

            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 280, height: 280)
                .blur(radius: 22)
                .offset(x: drift ? 16 : -8, y: drift ? 12 : -18)

            VStack(spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .fill(Color.white.opacity(0.07))

                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)

                    Image("BrandLogo")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(14)
                }
                .frame(width: 208, height: 208)
                .shadow(color: Color.black.opacity(0.28), radius: 28, y: 18)
                .scaleEffect(pulse ? 1.0 : 0.975)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(subtitle)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.76))
                        .multilineTextAlignment(.center)
                }

                if showsProgress {
                    HStack(spacing: 10) {
                        progressPill(width: 34, color: Color(red: 0.31, green: 0.84, blue: 1.0), delay: 0.0)
                        progressPill(width: 44, color: .white, delay: 0.12)
                        progressPill(width: 34, color: Color(red: 0.88, green: 0.43, blue: 1.0), delay: 0.24)
                    }
                }
            }
            .padding(.horizontal, 32)
        }
        .task {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private func progressPill(width: CGFloat, color: Color, delay: Double) -> some View {
        Capsule()
            .fill(color.opacity(pulse ? 1.0 : 0.55))
            .frame(width: width, height: 8)
            .shadow(color: color.opacity(0.35), radius: 10, y: 0)
            .animation(
                .easeInOut(duration: 0.85)
                    .repeatForever()
                    .delay(delay),
                value: pulse
            )
    }
}
