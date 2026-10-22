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
    print("PASS: Finder-style file URLs, multi-file/folder drops, Unicode and raw paths, original files untouched")
}
Task { @MainActor in
    do { try await runShelfDropChecks(); exit(0) }
    catch { print("FAIL: \(error)"); exit(1) }
}
RunLoop.main.run()
