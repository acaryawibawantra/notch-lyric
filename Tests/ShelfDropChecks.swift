@MainActor
func runShelfDropChecks() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("notch-drop-checks-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("Cat notes ü.txt")
    let original = Data("Original stays unchanged".utf8)
    try original.write(to: source)
    let folder = root.appendingPathComponent("Project folder")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    func provider(_ value: String) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { completion in
            completion(Data(value.utf8), nil)
            return nil
        }
        return provider
    }
    let items = await ShelfDropService.items(from: [provider(source.absoluteString), provider(folder.absoluteString), provider(source.path)])
    precondition(items.count == 3)
    for (item, expected) in zip(items, [source, folder, source]) {
        guard case let .file(data) = item.kind else { preconditionFailure("Expected file reference") }
        precondition(Bookmark(data: data).resolveURL()?.path == expected.path)
        precondition(!item.isTemporary)
    }
    let retained = try Data(contentsOf: source)
    precondition(retained == original && FileManager.default.fileExists(atPath: folder.path))
    let web = "https://example.com/path?q=cat#hello"
    precondition(ShelfDropService.webURL(from: " \(web)\n")?.absoluteString == web)
    for invalid in ["not a link", "https://", "javascript:alert(1)", "file:///tmp/test", "https://example.com has spaces"] {
        precondition(ShelfDropService.webURL(from: invalid) == nil)
    }
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let copiedFile = NSPasteboardItem()
    copiedFile.setString(source.absoluteString, forType: .fileURL)
    copiedFile.setString(source.path, forType: .string)
    let copiedLink = NSPasteboardItem()
    copiedLink.setString(web, forType: .string)
    let copiedNote = NSPasteboardItem()
    copiedNote.setString("Some useful notes", forType: .string)
    board.writeObjects([copiedFile, copiedLink, copiedNote])
    let pasted = await ShelfDropService.items(from: ShelfDropService.providers(from: board))
    precondition(pasted.count == 3)
    guard case .file = pasted[0].kind, case .link(let pastedURL) = pasted[1].kind,
          case .text(let pastedNote) = pasted[2].kind else { preconditionFailure("Paste must preserve kinds") }
    precondition(pastedURL.absoluteString == web && pastedNote == "Some useful notes")
    board.clearContents()
    board.writeObjects([source as NSURL])
    let nativeFileProviders = ShelfDropService.providers(from: board)
    precondition(nativeFileProviders.count == 1)
    let nativeFileURL = await nativeFileProviders[0].extractFileURL()
    precondition(nativeFileURL?.path == source.path, "Native URL drag writers must preserve Unicode file paths")
    board.clearContents()
    precondition(ShelfDropService.providers(from: board).isEmpty)
    let context = CGContext(data: nil, width: 3, height: 2, bitsPerComponent: 8, bytesPerRow: 12,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(red: 1, green: 0.2, blue: 0.3, alpha: 0.5)
    context.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
    let pixels = NSBitmapImageRep(cgImage: context.makeImage()!)
    for format: NSPasteboard.PasteboardType in [.png, .tiff] {
        let imageData = format == .png ? pixels.representation(using: .png, properties: [:])! : pixels.tiffRepresentation!
        let imageItem = NSPasteboardItem()
        imageItem.setData(imageData, forType: format)
        imageItem.setString("https://example.com/image-source", forType: .URL)
        board.clearContents()
        board.writeObjects([imageItem])
        let imageProviders = ShelfDropService.providers(from: board)
        precondition(imageProviders.count == 1 && imageProviders[0].suggestedName == "Pasted image.png")
        let images = await ShelfDropService.items(from: imageProviders)
        precondition(images.count == 1 && images[0].isTemporary)
        guard case .file(let bookmark) = images[0].kind,
              let imageURL = Bookmark(data: bookmark).resolveURL() else { fatalError("Image must become a real file") }
        let restored = NSBitmapImageRep(data: try Data(contentsOf: imageURL))!
        precondition(imageURL.pathExtension == "png" && restored.pixelsWide == 3 && restored.pixelsHigh == 2)
        precondition(abs(restored.colorAt(x: 0, y: 0)!.alphaComponent - 0.5) < 0.02, "Keep image transparency")
        TemporaryFileStorageService.shared.removeTemporaryFileIfNeeded(at: imageURL)
        precondition(!FileManager.default.fileExists(atPath: imageURL.path))
    }
    let invalidImage = NSPasteboardItem()
    invalidImage.setData(Data([1, 2, 3]), forType: .png)
    board.clearContents()
    board.writeObjects([invalidImage])
    precondition(ShelfDropService.providers(from: board).isEmpty)
    let originalWithPreview = NSPasteboardItem()
    originalWithPreview.setString(source.absoluteString, forType: .fileURL)
    originalWithPreview.setData(pixels.representation(using: .png, properties: [:])!, forType: .png)
    board.clearContents()
    board.writeObjects([originalWithPreview])
    let originalItems = await ShelfDropService.items(from: ShelfDropService.providers(from: board))
    precondition(originalItems.count == 1 && !originalItems[0].isTemporary, "File URLs win over a Finder preview bitmap")
    let silentProvider = NSItemProvider()
    silentProvider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { _ in nil }
    let timeoutStart = ContinuousClock.now
    let timedOut = await silentProvider.boundedItem(typeIdentifier: UTType.fileURL.identifier, timeout: 0.05)
    precondition(timedOut == nil && timeoutStart.duration(to: .now) < .seconds(3))
    let lateProvider = NSItemProvider()
    lateProvider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { completion in
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { completion(Data("file:///tmp/late".utf8), nil) }
        return nil
    }
    let late = await lateProvider.boundedItem(typeIdentifier: UTType.fileURL.identifier, timeout: 0.03)
    precondition(late == nil)
    try? await Task.sleep(for: .milliseconds(250)) // A late callback must not resume twice.
    print("PASS: Finder-style file URLs, multi-file/folder drops, Unicode and raw paths, original files untouched")
    print("PASS: explicit paste uses isolated clipboard, file precedence, web links vs notes, URL validation and empty clipboard")
    print("PASS: nonresponding provider deadline and harmless late completion; no indefinite continuation")
    print("PASS: private clipboard PNG/TIFF paste creates shareable PNG, preserves dimensions/alpha, prioritizes bitmap over web URL and original file over preview, rejects invalid data and cleans fixture copies")
}
Task { @MainActor in
    do { try await runShelfDropChecks(); exit(0) }
    catch { print("FAIL: \(error)"); exit(1) }
}
RunLoop.main.run()
