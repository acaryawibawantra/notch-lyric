//
//  MusicVisualizer.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//
import AppKit
import Cocoa
import SwiftUI

/// One ambient surface behind both header and media, fading to the black shell.
struct MediaNotchGradient: View {
    var tint: Color
    var active = true
    var opaque = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            if !reduceTransparency && !opaque {
                ZStack {
                    RadialGradient(colors: [tint.opacity(active ? 0.30 : 0.06),
                                            tint.opacity(active ? 0.12 : 0.025), .clear],
                                   center: UnitPoint(x: 0.19, y: 0.58), startRadius: 0,
                                   endRadius: geometry.size.width * 0.76)
                    RadialGradient(colors: [tint.opacity(active ? 0.10 : 0.025), .clear],
                                   center: .bottomTrailing, startRadius: 0,
                                   endRadius: geometry.size.width * 0.70)
                }
                .mask {
                    LinearGradient(stops: [.init(color: .clear, location: 0),
                                           .init(color: .black, location: 0.20),
                                           .init(color: .black, location: 0.76),
                                           .init(color: .clear, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .mask {
                    LinearGradient(stops: [.init(color: .clear, location: 0),
                                           .init(color: .black, location: 0.10),
                                           .init(color: .black, location: 0.88),
                                           .init(color: .clear, location: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.65), value: tint)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: active)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

class AudioSpectrum: NSView {
    private var barLayers: [CAShapeLayer] = []
    private var barScales: [CGFloat] = []
    private var isPlaying: Bool = true
    private var animationTimer: Timer?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupBars()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupBars()
    }

    private func setupBars() {
        let barWidth: CGFloat = 2
        let barCount = 4
        let spacing: CGFloat = barWidth
        let totalWidth = CGFloat(barCount) * (barWidth + spacing)
        let totalHeight: CGFloat = 14
        frame.size = CGSize(width: totalWidth, height: totalHeight)

        for i in 0 ..< barCount {
            let xPosition = CGFloat(i) * (barWidth + spacing)
            let barLayer = CAShapeLayer()
            barLayer.frame = CGRect(x: xPosition, y: 0, width: barWidth, height: totalHeight)
            barLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            barLayer.position = CGPoint(x: xPosition + barWidth / 2, y: totalHeight / 2)
            barLayer.fillColor = NSColor.white.cgColor
            barLayer.backgroundColor = NSColor.white.cgColor
            barLayer.allowsGroupOpacity = false
            barLayer.masksToBounds = true
            let path = NSBezierPath(roundedRect: CGRect(x: 0, y: 0, width: barWidth, height: totalHeight),
                                    xRadius: barWidth / 2,
                                    yRadius: barWidth / 2)
            barLayer.path = path.cgPath
            barLayers.append(barLayer)
            barScales.append(0.35)
            layer?.addSublayer(barLayer)
        }
    }
    
    private func startAnimating() {
        guard animationTimer == nil else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.updateBars()
        }
    }
    
    private func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
        resetBars()
    }
    
    private func updateBars() {
        for (i, barLayer) in barLayers.enumerated() {
            let currentScale = barScales[i]
            let targetScale = CGFloat.random(in: 0.35 ... 1.0)
            barScales[i] = targetScale
            let animation = CABasicAnimation(keyPath: "transform.scale.y")
            animation.fromValue = currentScale
            animation.toValue = targetScale
            animation.duration = 0.3
            animation.autoreverses = true
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            if #available(macOS 13.0, *) {
                animation.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 24, preferred: 24)
            }
            barLayer.add(animation, forKey: "scaleY")
        }
    }
    
    private func resetBars() {
        for (i, barLayer) in barLayers.enumerated() {
            barLayer.removeAllAnimations()
            barLayer.transform = CATransform3DMakeScale(1, 0.35, 1)
            barScales[i] = 0.35
        }
    }
    
    func setPlaying(_ playing: Bool) {
        isPlaying = playing
        if isPlaying {
            startAnimating()
        } else {
            stopAnimating()
        }
    }

    func setColor(_ color: NSColor) {
        for bar in barLayers { bar.fillColor = color.cgColor; bar.backgroundColor = color.cgColor }
    }
}

struct AudioSpectrumView: NSViewRepresentable {
    @Binding var isPlaying: Bool
    var color: NSColor = .white
    
    func makeNSView(context: Context) -> AudioSpectrum {
        let spectrum = AudioSpectrum()
        spectrum.setPlaying(isPlaying)
        spectrum.setColor(color)
        return spectrum
    }
    
    func updateNSView(_ nsView: AudioSpectrum, context: Context) {
        nsView.setPlaying(isPlaying)
        nsView.setColor(color)
    }
}

/// Nonzero, deterministic playback-indicator heights (not microphone analysis).
enum CompactSpectrumMotion {
    static func heights(at time: TimeInterval, playing: Bool, reduceMotion: Bool) -> [CGFloat] {
        guard playing && !reduceMotion else { return [0.4, 0.7, 0.55, 0.35] }
        let safeTime = time.isFinite ? time.truncatingRemainder(dividingBy: 60) : 0
        return (0..<4).map { index in
            let phase = safeTime * (5.2 + Double(index) * 0.7) + Double(index) * 1.6
            return CGFloat(0.28 + 0.72 * (sin(phase) + 1) / 2)
        }
    }
}

/// SwiftUI bars participate in the same clipping/compositing as the black surface.
/// An embedded AppKit layer can be frozen or obscured by the lyric panel's mask.
struct CompactMusicSpectrum: View {
    @Binding var isPlaying: Bool
    var tint: Color = .white
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !isPlaying || reduceMotion)) { timeline in
            let heights = CompactSpectrumMotion.heights(at: timeline.date.timeIntervalSinceReferenceDate,
                                                        playing: isPlaying, reduceMotion: reduceMotion)
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4) { index in
                    Capsule().fill(tint).frame(width: 2, height: 14 * heights[index])
                }
            }
            .frame(width: 16, height: 14)
        }
        .frame(width: 16, height: 14)
        .allowsHitTesting(false)
        .accessibilityLabel(isPlaying ? "Music playing" : "Music paused")
    }
}

#Preview {
    AudioSpectrumView(isPlaying: .constant(true))
        .frame(width: 16, height: 20)
        .padding()
}
