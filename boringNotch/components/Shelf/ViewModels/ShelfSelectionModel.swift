//
//  ShelfSelectionModel.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-26.
//

import Foundation
import Combine

private let _shelfTypeAnchor: Bool = {
    _ = String(describing: ShelfItem.self)
    return true
}()

@MainActor
final class ShelfSelectionModel: ObservableObject {
    static let shared = ShelfSelectionModel()

    @Published private(set) var selectedIDs: Set<UUID> = []
    @Published var isEditingSearch = false
    @Published var isPreviewing = false
    private var visibleIDs: Set<UUID>?
    private var visibleOrder: [UUID]?

    func setVisibleItems(_ items: [ShelfItem]?) {
        visibleIDs = items.map { Set($0.map(\.id)) }
        visibleOrder = items?.map(\.id)
        if let visibleIDs { selectedIDs.formIntersection(visibleIDs) }
        ensureValidAnchor(in: items ?? [])
    }

    func selectAll(_ items: [ShelfItem]) {
        selectedIDs = Set(items.map(\.id))
        lastAnchorID = items.first?.id
    }

    // Anchor for shift-range selection
    private var lastAnchorID: UUID? = nil

    func isSelected(_ id: UUID) -> Bool { selectedIDs.contains(id) }

    var hasSelection: Bool { !selectedIDs.isEmpty }

    var firstSelectedItem: ShelfItem? {
        guard let firstID = selectedIDs.first else { return nil }
        return ShelfStateViewModel.shared.items.first(where: { $0.id == firstID })
    }

    func selectedItems(in allItems: [ShelfItem]) -> [ShelfItem] {
        allItems.filter { selectedIDs.contains($0.id) }
    }

    func selectSingle(_ item: ShelfItem) {
        selectedIDs = [item.id]
        lastAnchorID = item.id
    }

    @discardableResult
    func moveSelection(by step: Int, in items: [ShelfItem]) -> ShelfItem? {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let ordered = visibleOrder.map { $0.compactMap { byID[$0] } } ?? items
        guard !ordered.isEmpty else { clear(); return nil }
        let current = ordered.firstIndex { $0.id == lastAnchorID && selectedIDs.contains($0.id) }
            ?? ordered.firstIndex { selectedIDs.contains($0.id) }
        let next = current.map { min(ordered.count - 1, max(0, $0 + step)) } ?? (step < 0 ? ordered.count - 1 : 0)
        selectSingle(ordered[next])
        return ordered[next]
    }

    func toggle(_ item: ShelfItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
        lastAnchorID = item.id
    }

    func shiftSelect(to item: ShelfItem, in allItems: [ShelfItem]) {
        let byID = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
        let allItems = visibleOrder.map { $0.compactMap { byID[$0] } } ?? allItems
        // Determine anchor
        let anchorID = lastAnchorID ?? selectedIDs.first ?? item.id
        guard let startIndex = allItems.firstIndex(where: { $0.id == anchorID }),
              let endIndex = allItems.firstIndex(where: { $0.id == item.id }) else {
            // Fallback to single select if indices not found
            return selectSingle(item)
        }
        let lower = min(startIndex, endIndex)
        let upper = max(startIndex, endIndex)
        let rangeIDs = allItems[lower...upper].map { $0.id }
        selectedIDs = Set(rangeIDs)
    }

    func clear() {
        selectedIDs.removeAll()
        lastAnchorID = nil
    }

    // Keep anchor sane if items array changed drastically (optional helper)
    func ensureValidAnchor(in allItems: [ShelfItem]) {
        selectedIDs.formIntersection(Set(allItems.map(\.id)))
        if let anchor = lastAnchorID, !allItems.contains(where: { $0.id == anchor }) {
            lastAnchorID = selectedIDs.first
        }
    }

    @Published private(set) var isDragging: Bool = false
    private(set) var draggedItems: [ShelfItem] = []

    func beginDrag(_ items: [ShelfItem] = []) {
        draggedItems = items
        isDragging = true
    }

    func endDrag() {
        isDragging = false
        draggedItems = []
    }
}
