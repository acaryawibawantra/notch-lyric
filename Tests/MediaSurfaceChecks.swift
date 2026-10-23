Task { @MainActor in
    for width: CGFloat in [640, 720] {
        for tint: Color in [.orange, .blue, .pink, .mint] {
            let renderer = ImageRenderer(content:
                MediaNotchGradient(tint: tint).frame(width: width, height: 276)
                    .background(.black))
            guard let image = renderer.cgImage else { fatalError("Media gradient did not render") }
            let bitmap = NSBitmapImageRep(cgImage: image)
            func brightness(_ x: Int, _ y: Int) -> CGFloat {
                let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                return max(color.redComponent, color.greenComponent, color.blueComponent)
            }
            let w = bitmap.pixelsWide, h = bitmap.pixelsHigh
            precondition(brightness(w / 5, h / 2) > 0.08, "Album tint must be visible")
            precondition(brightness(w / 5, h / 2) < 0.45, "Gradient must not overpower white media controls")
            precondition(brightness(w / 2, 0) < 0.02 && brightness(w / 2, h - 1) < 0.02,
                         "Top and bottom must blend into black")
            precondition(brightness(0, h / 2) < 0.02 && brightness(w - 1, h / 2) < 0.02,
                         "Side edges must blend into the notch shell")
        }
    }
    let accessible = ImageRenderer(content:
        MediaNotchGradient(tint: .orange, opaque: true).frame(width: 640, height: 236)
            .background(.black))
    let bitmap = NSBitmapImageRep(cgImage: accessible.cgImage!)
    let color = bitmap.colorAt(x: bitmap.pixelsWide / 5, y: bitmap.pixelsHigh / 2)!.usingColorSpace(.deviceRGB)!
    precondition(color.redComponent < 0.01 && color.greenComponent < 0.01 && color.blueComponent < 0.01)
    print("PASS: media gradient renders at full/split sizes, stays subtle, feathers into black on every edge and supports the opaque accessibility fallback")
    exit(0)
}
RunLoop.main.run()
