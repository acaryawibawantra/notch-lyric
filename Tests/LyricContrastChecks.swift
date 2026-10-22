// Generated color fixtures only. No capture APIs or permission requests are used.
Task { @MainActor in
    precondition(LyricContrastRules.prefersDark(1, previouslyDark: false))
    precondition(!LyricContrastRules.prefersDark(0, previouslyDark: true))
    precondition(LyricContrastRules.prefersDark(0.18, previouslyDark: true))
    precondition(!LyricContrastRules.prefersDark(0.18, previouslyDark: false))
    precondition(!LyricContrastRules.prefersDark(.nan, previouslyDark: true))
    let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let area = CGRect(x: 500, y: 800, width: 300, height: 40)
    precondition(LyricContrastRules.localRect(area, screen: main) == CGRect(x: 500, y: 60, width: 300, height: 40))
    let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    precondition(LyricContrastRules.localRect(CGRect(x: -1700, y: 950, width: 300, height: 40), screen: left)
                 == CGRect(x: 220, y: 90, width: 300, height: 40))
    let above = CGRect(x: 0, y: 900, width: 1440, height: 900)
    precondition(LyricContrastRules.localRect(CGRect(x: 500, y: 1700, width: 300, height: 40), screen: above)
                 == CGRect(x: 500, y: 60, width: 300, height: 40))
    precondition(LyricContrastRules.localRect(CGRect(x: -10, y: 800, width: 40, height: 40), screen: main)
                 == CGRect(x: 0, y: 60, width: 30, height: 40))
    precondition(LyricContrastRules.localRect(CGRect(x: 2000, y: 0, width: 40, height: 40), screen: main) == .zero)
    @MainActor func brightness(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> Double {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(colorSpace: space, components: [red, green, blue, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return LyricContrastSampler.luminance(ctx.makeImage()!)!
    }
    precondition(brightness(0, 0, 0) < 0.01)
    precondition(brightness(1, 1, 1) > 0.99)
    precondition(abs(brightness(1, 0, 0) - 0.2126) < 0.01)
    precondition(abs(brightness(0, 1, 0) - 0.7152) < 0.01)
    let sampler = LyricContrastSampler()
    sampler.stop()
    sampler.stop()
    precondition(!sampler.usesDarkText)
    print("PASS: adaptive foreground, hysteresis, sRGB luminance, cropped display coordinates, multi-monitor and safe fallback; no screen captured")
    exit(0)
}
RunLoop.main.run()
