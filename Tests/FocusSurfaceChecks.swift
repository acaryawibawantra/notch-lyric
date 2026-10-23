Task { @MainActor in
    for compact in [false, true] {
        for phase in [FocusPhase.focus, .rest] {
            for completed in [false, true] {
                FocusTimerModel.shared.phase = phase
                FocusTimerModel.shared.isFinished = completed
                FocusTimerModel.shared.isVisible = completed
                let width: CGFloat = compact ? 235 : 420
                let renderer = ImageRenderer(content:
                    MediaFocusCompanion(compact: compact)
                        .frame(width: width)
                        .padding(12).background(.black)
                        .environment(\.colorScheme, .dark))
                guard let image = renderer.cgImage else { fatalError("Focus panel did not render") }
                precondition(image.height <= 255, "Focus panel must fit below its mode picker: \(image.height)")
                if !compact && phase == .focus && !completed,
                   let path = ProcessInfo.processInfo.environment["MORIS_FOCUS_PREVIEW"] {
                    let bitmap = NSBitmapImageRep(cgImage: image)
                    try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
                }
            }
        }
    }
    print("PASS: production Focus panels render at full/split widths, including break/completed states, within their height budget")
    exit(0)
}
RunLoop.main.run()
