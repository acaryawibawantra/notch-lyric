Task { @MainActor in
    let first = CompactSpectrumMotion.heights(at: 0, playing: true, reduceMotion: false)
    let later = CompactSpectrumMotion.heights(at: 0.3, playing: true, reduceMotion: false)
    precondition(first != later)
    for time in [0.0, 0.3, 59.99, 1_000_000, Double.nan, Double.infinity] {
        let heights = CompactSpectrumMotion.heights(at: time, playing: true, reduceMotion: false)
        precondition(heights.count == 4 && heights.allSatisfy { $0.isFinite && $0 >= 0.28 && $0 <= 1 })
    }
    precondition(CompactSpectrumMotion.heights(at: 0, playing: false, reduceMotion: false) ==
                 CompactSpectrumMotion.heights(at: 5, playing: false, reduceMotion: false))
    precondition(CompactSpectrumMotion.heights(at: 0, playing: true, reduceMotion: true) ==
                 CompactSpectrumMotion.heights(at: 5, playing: true, reduceMotion: true))
    // Native NSView layers are not reliable inside this composition. Verify the
    // production SwiftUI indicator really contributes visible pixels on black.
    let renderer = ImageRenderer(content:
        CompactMusicSpectrum(isPlaying: .constant(true), tint: .white)
            .padding(10).background(.black)
            .compositingGroup().clipShape(RoundedRectangle(cornerRadius: 6)))
    renderer.scale = 2
    guard let image = renderer.cgImage else { preconditionFailure("Spectrum must render") }
    let bitmap = NSBitmapImageRep(cgImage: image)
    var visiblePixels = 0
    for x in 0..<bitmap.pixelsWide {
        for y in 0..<bitmap.pixelsHigh {
            if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
               color.redComponent > 0.8 && color.greenComponent > 0.8 && color.blueComponent > 0.8 {
                visiblePixels += 1
            }
        }
    }
    precondition(visiblePixels > 40, "Black background must not hide the rhythm bars")
    let spectrum = AudioSpectrum(frame: .zero)
    spectrum.setColor(.white)
    let bars = spectrum.layer!.sublayers!
    precondition(bars.count == 4 && bars.allSatisfy { $0.bounds.width > 0 && $0.bounds.height > 0 })
    for bar in bars {
        let shape = bar as! CAShapeLayer
        precondition(shape.fillColor == NSColor.white.cgColor)
    }
    spectrum.setPlaying(true)
    try? await Task.sleep(for: .milliseconds(450))
    precondition(bars.allSatisfy { $0.animation(forKey: "scaleY") != nil })
    spectrum.setPlaying(false)
    precondition(bars.allSatisfy { $0.animationKeys()?.isEmpty != false })
    print("PASS: direct native spectrum has four visible white bars, animates while playing and stops when paused")
    print("PASS: SwiftUI compact spectrum remains nonzero, changes over time, handles invalid time and stays still when paused or Reduce Motion is enabled")
    exit(0)
}
RunLoop.main.run()
