Task { @MainActor in
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
    exit(0)
}
RunLoop.main.run()
