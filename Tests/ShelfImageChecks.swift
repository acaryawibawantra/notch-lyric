import CoreImage.CIFilterBuiltins

enum TempFileType { case data(Data, suggestedName: String?) }

final class TemporaryFileStorageService {
    static let shared = TemporaryFileStorageService()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("notch-image-checks-\(UUID().uuidString)")
    func createTempFile(for type: TempFileType) async -> URL? {
        guard case let .data(data, name) = type else { return nil }
        let url = root.appendingPathComponent(UUID().uuidString + "-" + (name ?? "output"))
        do { try data.write(to: url); return url } catch { return nil }
    }
}

@MainActor
func runShelfImageChecks() async throws {
    let root = TemporaryFileStorageService.shared.root
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 6,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    memset(bitmap.bitmapData!, 180, bitmap.bytesPerRow * bitmap.pixelsHigh)
    let original = bitmap.representation(using: .png, properties: [:])!
    let source = root.appendingPathComponent("source.png")
    try original.write(to: source)
    let service = ImageProcessingService.shared
    for format: ImageConversionOptions.ImageFormat in [.png, .jpeg] {
        let output = try await service.convertImage(from: source, options: ImageConversionOptions(
            format: format, compressionQuality: 0.9, maxDimension: nil, removeMetadata: true))
        precondition(output != nil && output != source)
        let result = NSBitmapImageRep(data: try Data(contentsOf: output!))!
        precondition(result.pixelsWide == 4 && result.pixelsHigh == 6)
    }
    let pdf = try await service.createPDF(from: [source, source])
    precondition(pdf != nil && PDFDocument(url: pdf!)?.pageCount == 2)
    let invalid = root.appendingPathComponent("invalid.png")
    try Data("not an image".utf8).write(to: invalid)
    do {
        _ = try await service.createPDF(from: [source, invalid])
        preconditionFailure("A batch with an invalid image must fail, not silently omit it")
    } catch ImageProcessingError.invalidImage { }
    let preserved = try Data(contentsOf: source)
    precondition(preserved == original)
    print("PASS: offline PNG/JPEG conversion, dimensions, two-page PDF, invalid batch rejection, unchanged source")
}

Task { @MainActor in
    do { try await runShelfImageChecks(); exit(0) }
    catch { print("FAIL: \(error)"); exit(1) }
}
RunLoop.main.run()
