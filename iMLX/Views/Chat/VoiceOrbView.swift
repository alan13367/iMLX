import SwiftUI

enum VoiceOrbState: Equatable {
    case idle
    case listening
    case generating
    case speaking
}

struct VoiceOrbView: View {
    let state: VoiceOrbState
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringScale: CGFloat = 1.0
    @State private var ringOpacity: Double = 0

    private var breathingSpeed: Double {
        switch state {
        case .idle: 3.0
        case .listening: 1.4
        case .generating: 1.8
        case .speaking: 1.2
        }
    }

    private var glowIntensity: Double {
        switch state {
        case .idle: 0.35
        case .listening: 0.6
        case .generating: 0.45
        case .speaking: 0.7
        }
    }

    private var showRings: Bool {
        state == .listening || state == .speaking
    }

    var body: some View {
        ZStack {
            if showRings && !reduceMotion {
                ringLayer
            }
            orbBody
        }
        .frame(width: size, height: size)
        .onAppear {
            startRingAnimations()
        }
        .onChange(of: state) { _, _ in
            startRingAnimations()
        }
    }

    // MARK: - Orb

    private var orbBody: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let breathCycle = reduceMotion ? 0.0 : sin(now * .pi * 2.0 / breathingSpeed)
            let drift = reduceMotion ? 0.0 : now.truncatingRemainder(dividingBy: 12.0) / 12.0

            let orbSize = size * 0.68
            let scale = 1.0 + CGFloat(breathCycle) * 0.06

            ZStack {
                orbGlow(orbSize: orbSize, drift: drift)
                orbCore(orbSize: orbSize, drift: drift)
                orbHighlight(orbSize: orbSize, drift: drift)
            }
            .scaleEffect(scale)
        }
    }

    private func orbGlow(orbSize: CGFloat, drift: Double) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        BrandPalette.cyan.opacity(0.5),
                        BrandPalette.accent.opacity(0.3),
                        BrandPalette.magenta.opacity(0.15),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: orbSize * 0.1,
                    endRadius: orbSize * 0.9
                )
            )
            .frame(width: orbSize * 1.8, height: orbSize * 1.8)
            .blur(radius: orbSize * 0.25)
            .opacity(glowIntensity)
    }

    private func orbCore(orbSize: CGFloat, drift: Double) -> some View {
        let driftX = CGFloat(sin(drift * .pi * 2)) * 0.15
        let driftY = CGFloat(cos(drift * .pi * 2)) * 0.1

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            BrandPalette.cyan,
                            BrandPalette.accent,
                            BrandPalette.magenta.opacity(0.8)
                        ],
                        center: UnitPoint(x: 0.35 + driftX, y: 0.35 + driftY),
                        startRadius: 0,
                        endRadius: orbSize * 0.7
                    )
                )
                .frame(width: orbSize, height: orbSize)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            BrandPalette.magenta.opacity(0.6),
                            BrandPalette.accent.opacity(0.3),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.7 - driftX * 0.5, y: 0.65 - driftY * 0.5),
                        startRadius: 0,
                        endRadius: orbSize * 0.55
                    )
                )
                .frame(width: orbSize, height: orbSize)
                .blendMode(.screen)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.6, green: 0.3, blue: 1.0).opacity(0.4),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.5 + driftX * 0.3, y: 0.5),
                        startRadius: 0,
                        endRadius: orbSize * 0.4
                    )
                )
                .frame(width: orbSize, height: orbSize)
                .blendMode(.plusLighter)
        }
        .shadow(color: BrandPalette.cyan.opacity(glowIntensity * 0.5), radius: orbSize * 0.15)
        .shadow(color: BrandPalette.magenta.opacity(glowIntensity * 0.25), radius: orbSize * 0.2, y: 4)
    }

    private func orbHighlight(orbSize: CGFloat, drift: Double) -> some View {
        let highlightDriftX = CGFloat(sin(drift * .pi * 2 + 0.5)) * 0.06

        return Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.35),
                        Color.white.opacity(0.08),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.5 + highlightDriftX, y: 0.3),
                    startRadius: 0,
                    endRadius: orbSize * 0.35
                )
            )
            .frame(width: orbSize * 0.6, height: orbSize * 0.4)
            .offset(y: -orbSize * 0.12)
            .blendMode(.plusLighter)
    }

    // MARK: - Rings

    private var ringLayer: some View {
        ForEach(0..<3, id: \.self) { index in
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            BrandPalette.cyan.opacity(0.3 - Double(index) * 0.08),
                            BrandPalette.magenta.opacity(0.2 - Double(index) * 0.05),
                            BrandPalette.cyan.opacity(0.3 - Double(index) * 0.08)
                        ],
                        center: .center
                    ),
                    lineWidth: 1.2
                )
                .frame(
                    width: size * (0.72 + CGFloat(index) * 0.12),
                    height: size * (0.72 + CGFloat(index) * 0.12)
                )
                .scaleEffect(ringScale)
                .opacity(ringOpacity - Double(index) * 0.15)
        }
    }

    private func startRingAnimations() {
        guard !reduceMotion else {
            ringScale = 1.0
            ringOpacity = 0
            return
        }

        if showRings {
            withAnimation(
                .easeInOut(duration: breathingSpeed * 0.8)
                .repeatForever(autoreverses: true)
            ) {
                ringScale = 1.18
                ringOpacity = 0.5
            }
        } else {
            withAnimation(.easeOut(duration: 0.4)) {
                ringScale = 1.0
                ringOpacity = 0
            }
        }
    }
}
