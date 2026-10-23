// Test production sizing and render every style without touching saved preferences.
for style in CatEyeStyle.allCases {
    precondition(CatEyeStyle(rawValue: style.rawValue) == style)
    for height: CGFloat in [0, 8, 20, 30, 32, 44, 100] {
        let size = style.diameter(for: height)
        precondition(size >= 0 && size <= height && size <= 30)
        precondition(size * style.aspectRatio <= height)
    }
}
precondition(CatEyeStyle.round.diameter(for: 32) > CatEyeStyle.classic.diameter(for: 32))
precondition(CatEyeStyle.round.aspectRatio > CatEyeStyle.dreamy.aspectRatio)

Task { @MainActor in
    for style in CatEyeStyle.allCases {
        let renderer = ImageRenderer(content:
            RestingCatEyes(cameraGap: 100, height: 32, isActive: false, styleOverride: style)
                .padding(16).background(.black))
        renderer.scale = 2
        precondition(renderer.cgImage != nil, "Every style must render at notch height")
    }
    if CommandLine.arguments.count > 1 {
        let renderer = ImageRenderer(content:
            HStack(spacing: 28) {
                ForEach(CatEyeStyle.allCases) { style in
                    VStack(spacing: 12) {
                        RestingCatEyes(cameraGap: 8, height: 48, isActive: false, styleOverride: style)
                        Text(style.rawValue).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                    }
                }
            }.padding(28).background(.black))
        renderer.scale = 3
        let bitmap = NSBitmapImageRep(cgImage: renderer.cgImage!)
        do {
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        } catch {
            fatalError("Could not save test preview: \(error)")
        }
    }
    print("PASS: three eye styles, stable identifiers, bounded notch sizing and offscreen rendering; no preferences changed")
    exit(0)
}
RunLoop.main.run()
