import SwiftUI

enum QuotaPalette {
    static let backdrop = Color(red: 0.20, green: 0.29, blue: 0.47)
    static let card = Color(red: 0.30, green: 0.39, blue: 0.58)
    static let track = Color(red: 0.50, green: 0.58, blue: 0.73)
    static let remainingGreen = Color(red: 35.0 / 255, green: 210.0 / 255, blue: 82.0 / 255)
    static let ocean = Color(red: 0.20, green: 0.57, blue: 0.74)
    static let peach = Color(red: 1, green: 0.82, blue: 0.68)
    static let red = Color(red: 1, green: 0.40, blue: 0.43)

}

struct ProviderMonogram: View {
    let symbol: String
    var size: CGFloat = 14
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if symbol.hasSuffix("₂") {
                Text(String(symbol.dropLast())).font(.system(size: size, weight: .bold, design: .rounded))
                Text("2").font(.system(size: size * 0.55, weight: .bold)).baselineOffset(-size * 0.18)
            } else {
                Text(symbol).font(.system(size: size, weight: .bold, design: .rounded))
            }
        }
    }
}

struct RingView: View {
    let fraction: Double?
    let accent: Color
    let failed: Bool
    var diameter: CGFloat = 90
    var reveal: Double = 1
    var symbol: String? = nil

    var body: some View {
        ZStack {
            Circle().stroke(QuotaPalette.track.opacity(0.54), lineWidth: diameter * 0.095)
            if failed {
                Circle().stroke(QuotaPalette.red, lineWidth: diameter * 0.095)
            } else if let fraction {
                Circle().trim(from: 0, to: min(1, max(0, fraction)) * reveal)
                    .stroke(accent, style: StrokeStyle(lineWidth: diameter * 0.095, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            if let symbol {
                ProviderMonogram(symbol: symbol, size: diameter * 0.48)
            } else if failed {
                Text("∞").font(.system(size: diameter * 0.38, weight: .bold, design: .rounded))
            } else if let fraction {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(QuotaPercentage.whole(fraction) ?? 0)")
                        .font(.system(size: diameter * 0.38, weight: .bold, design: .rounded))
                    if QuotaPercentage.whole(fraction) != 100 {
                        Text("%").font(.system(size: diameter * 0.21, weight: .bold, design: .rounded))
                    }
                }
            } else {
                Text("—").font(.system(size: diameter * 0.38, weight: .bold))
            }
        }
        .foregroundStyle(.white)
        .frame(width: diameter, height: diameter)
    }
}

private struct WaterWave: Shape {
    var level: Double
    var phase: Double
    var amplitude: Double
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(level, phase) }
        set { level = newValue.first; phase = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        guard level > 0 else { return Path() }
        var path = Path()
        let baseline = rect.height * (1 - level)
        path.move(to: CGPoint(x: 0, y: rect.height))
        for step in 0...60 {
            let x = rect.width * Double(step) / 60
            let y = baseline + sin(Double(step) / 60 * .pi * 2 + phase) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()
        return path
    }
}

struct WaterTankView: View {
    let amount: Double?
    let symbol: String
    var diameter: CGFloat = 90
    var reveal: Double = 1
    var pulse: Date? = nil
    @State private var phase = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var empty: Bool { amount.map { $0 <= 0 } ?? false }
    private var level: Double { amount.map(QuotaFormat.waterLevel) ?? 0 }
    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(0.025))
            WaterWave(level: level * reveal, phase: phase + 1.6, amplitude: diameter * 0.018)
                .fill(QuotaPalette.ocean.opacity(0.48))
            WaterWave(level: level * reveal, phase: phase, amplitude: diameter * 0.024)
                .fill(QuotaPalette.ocean.opacity(0.9))
            ProviderMonogram(symbol: symbol, size: diameter * 0.47)
                .foregroundStyle(empty ? QuotaPalette.red : .white)
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(QuotaPalette.track.opacity(0.72), lineWidth: diameter < 50 ? 2 : 3))
        .frame(width: diameter, height: diameter)
        .onChange(of: pulse) { _, value in
            guard value != nil, !empty, !reduceMotion else { return }
            withAnimation(.linear(duration: 1.1)) { phase += .pi * 4 }
        }
    }
}
