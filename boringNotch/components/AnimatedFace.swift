//
//  AnimatedFace.swift
//
// Created by Harsh Vardhan  Goswami  on  04/08/24.
//

import SwiftUI
import Defaults

enum CatEyePalette: String, CaseIterable, Identifiable, Defaults.Serializable {
    case pearl = "Pearl"
    case sky = "Sky"
    case mint = "Mint"
    case lavender = "Lavender"
    case sunrise = "Sunrise"
    case rose = "Rose"
    var id: String { rawValue }

    var colors: [Color] {
        switch self {
        case .pearl: [Color(red: 1, green: 0.98, blue: 0.91), Color(red: 0.83, green: 0.92, blue: 0.94)]
        case .sky: [Color(red: 0.83, green: 0.95, blue: 1), Color(red: 0.43, green: 0.68, blue: 1)]
        case .mint: [Color(red: 0.85, green: 1, blue: 0.87), Color(red: 0.35, green: 0.85, blue: 0.77)]
        case .lavender: [Color(red: 0.94, green: 0.87, blue: 1), Color(red: 0.65, green: 0.65, blue: 1)]
        case .sunrise: [Color(red: 1, green: 0.91, blue: 0.64), Color(red: 1, green: 0.62, blue: 0.51)]
        case .rose: [Color(red: 1, green: 0.86, blue: 0.91), Color(red: 0.89, green: 0.57, blue: 0.83)]
        }
    }
}

struct CatEyeAppearanceSettings: View {
    @Default(.showNotHumanFace) private var enabled
    @Default(.catEyePalette) private var palette

    var body: some View {
        Toggle("Show resting cat eyes while inactive", isOn: $enabled)
        Picker("Eye gradient", selection: $palette) {
            ForEach(CatEyePalette.allCases) { color in
                Text(color.rawValue).tag(color)
            }
        }
        .disabled(!enabled)
        HStack {
            Text("Preview").foregroundStyle(.secondary)
            Spacer()
            RestingCatEyes(cameraGap: 0, height: 44, isActive: false)
                .padding(.horizontal, 12)
                .background(.black, in: RoundedRectangle(cornerRadius: 12))
        }
        Text("Soft glowing gradients with dark pupils, natural glances and random blinks. Reduce Motion keeps the eyes still.")
            .font(.caption).foregroundStyle(.secondary)
    }
}

/// The empty center is real camera hardware, not a drawable part of the screen.
struct RestingCatEyes: View {
    let cameraGap: CGFloat
    let height: CGFloat
    var isActive = true
    @Default(.catEyePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var gaze: CGFloat = 0
    @State private var blinking = false

    private var eyeSize: CGFloat { min(22, max(10, height - 12)) }

    var body: some View {
        HStack(spacing: 0) {
            eye.frame(width: eyeSize + 12)
            Color.clear.frame(width: cameraGap > 0 ? cameraGap : 8)
            eye.frame(width: eyeSize + 12)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Resting cat")
        .allowsHitTesting(false)
        .task(id: isActive && !reduceMotion) {
            gaze = 0
            blinking = false
            guard isActive && !reduceMotion else { return }
            // Independent randomized blink and gaze loops, both cancelled with the view.
            do {
                async let glances: Void = animateGaze()
                async let blinks: Void = animateBlinks()
                _ = try await (glances, blinks)
            } catch { /* SwiftUI cancels the task when this view disappears. */ }
        }
    }

    private var eye: some View {
        CatEyeShape()
            .fill(LinearGradient(colors: palette.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Capsule()
                    .fill(.black)
                    .frame(width: max(3, eyeSize * 0.19), height: eyeSize * 0.73)
                    .offset(x: gaze * eyeSize * 0.22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(CatEyeShape())
            }
            .frame(width: eyeSize, height: eyeSize * 0.68)
            .scaleEffect(y: blinking ? 0.08 : 1)
            .shadow(color: palette.colors[0].opacity(blinking ? 0.08 : 0.45), radius: 3)
            .shadow(color: palette.colors[1].opacity(blinking ? 0.04 : 0.3), radius: 7)
    }

    @MainActor private func animateGaze() async throws {
        while !Task.isCancelled {
            try await Task.sleep(for: .seconds(Double.random(in: 2.2...5.5)))
            withAnimation(.easeInOut(duration: Double.random(in: 0.4...0.8))) {
                gaze = [CGFloat(-1), 0, 1].randomElement() ?? 0
            }
        }
    }

    @MainActor private func animateBlinks() async throws {
        while !Task.isCancelled {
            try await Task.sleep(for: .seconds(Double.random(in: 2.5...6.5)))
            try await blink()
            if Int.random(in: 0..<5) == 0 {
                try await Task.sleep(for: .seconds(0.22))
                try await blink()
            }
        }
    }

    @MainActor private func blink() async throws {
        withAnimation(.easeIn(duration: 0.1)) { blinking = true }
        try await Task.sleep(for: .seconds(0.13))
        withAnimation(.easeOut(duration: 0.18)) { blinking = false }
    }
}

private struct CatEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addCurve(to: CGPoint(x: rect.maxX, y: rect.midY),
                          control1: CGPoint(x: rect.width * 0.2, y: rect.minY - rect.height * 0.12),
                          control2: CGPoint(x: rect.width * 0.8, y: rect.minY - rect.height * 0.12))
            path.addCurve(to: CGPoint(x: rect.minX, y: rect.midY),
                          control1: CGPoint(x: rect.width * 0.8, y: rect.maxY + rect.height * 0.12),
                          control2: CGPoint(x: rect.width * 0.2, y: rect.maxY + rect.height * 0.12))
            path.closeSubpath()
        }
    }
}

struct MinimalFaceFeatures: View {
    @State private var isBlinking = false
    @State var height:CGFloat = 20;
    @State var width:CGFloat = 30;
    
    var body: some View {
        VStack(spacing: 4) { // Adjusted spacing to fit within 30x30
            // Eyes
            HStack(spacing: 4) { // Adjusted spacing to fit within 30x30
                Eye(isBlinking: $isBlinking)
                Eye(isBlinking: $isBlinking)
            }
            
            // Nose and mouth combined
            VStack(spacing: 2) { // Adjusted spacing to fit within 30x30
                // Nose
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: 3, height: 4)
                
                // Mouth (happy)
                GeometryReader { geometry in
                    Path { path in
                        let width = geometry.size.width
                        let height = geometry.size.height
                        path.move(to: CGPoint(x: 0, y: height / 2))
                        path.addQuadCurve(to: CGPoint(x: width, y: height / 2), control: CGPoint(x: width / 2, y: height))
                    }
                    .stroke(Color.white, lineWidth: 2)
                }
                .frame(width: 14, height: 10)
            }
        }
        .frame(width: self.width, height: self.height) // Maximum size of face
        .onAppear {
            startBlinking()
        }
    }
    
    func startBlinking() {
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            withAnimation(.spring(duration: 0.2)) {
                isBlinking = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(duration: 0.2)) {
                    isBlinking = false
                }
            }
        }
    }
}

struct Eye: View {
    @Binding var isBlinking: Bool
    
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white)
            .frame(width: 4, height: isBlinking ? 1 : 4)
            .frame(maxWidth: 15, maxHeight: 15) // Adjusted max size
            .animation(.easeInOut(duration: 0.1), value: isBlinking)
    }
}

struct MinimalFaceFeatures_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            MinimalFaceFeatures()
        }
        .previewLayout(.fixed(width: 60, height: 60)) // Adjusted preview size for better visibility
    }
}
