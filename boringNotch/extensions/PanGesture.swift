//
//  PanGesture.swift
//  boringNotch
//
//  Created by Richard Kunkli on 21/08/2024.
//

import AppKit
import SwiftUI
import Defaults

/// One tab per physical gesture. Momentum never starts a new navigation.
struct TabSwipeAccumulator {
    private(set) var x: CGFloat = 0
    private(set) var y: CGFloat = 0
    private(set) var claimed = false
    private var vertical = false

    mutating func reset() { self = Self() }

    mutating func update(dx: CGFloat, dy: CGFloat, threshold: CGFloat) -> Int? {
        guard !claimed, !vertical else { return nil }
        x += dx
        y += dy
        if abs(y) > 12 && abs(y) > abs(x) * 1.5 {
            vertical = true
            return nil
        }
        guard abs(x) >= threshold, abs(x) > abs(y) * 1.8 else { return nil }
        claimed = true
        return x < 0 ? 1 : -1
    }
}

/// Local to its notch window; no global event tap or Accessibility permission.
struct TabSwipeMonitor: NSViewRepresentable {
    var canNavigate: () -> Bool
    var navigate: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(view)
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.canNavigate = canNavigate
        context.coordinator.navigate = navigate
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.dispose() }

    @MainActor final class Coordinator {
        var canNavigate: () -> Bool = { false }
        var navigate: (Int) -> Void = { _ in }
        private var monitor: Any?
        private var swipe = TabSwipeAccumulator()
        private var lastEvent: TimeInterval = 0

        func install(_ view: NSView) {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self, weak view] event in
                guard let self, let view, let window = view.window, event.window === window else { return event }
                guard canNavigate(), event.hasPreciseScrollingDeltas,
                      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                      !(window.firstResponder is NSTextView),
                      view.bounds.contains(view.convert(event.locationInWindow, from: nil)) else {
                    swipe.reset()
                    return event
                }
                if !swipe.claimed, let content = window.contentView {
                    var target = content.hitTest(content.convert(event.locationInWindow, from: nil))
                    while let hit = target {
                        // Leave horizontal shelves, text selection and native controls alone.
                        if hit is NSTextView || hit is NSSlider ||
                            ((hit as? NSScrollView).map { $0.hasHorizontalScroller ||
                                ($0.documentView?.frame.width ?? 0) > $0.contentSize.width + 1 } ?? false) {
                            swipe.reset()
                            return event
                        }
                        target = hit.superview
                    }
                }
                if !event.momentumPhase.isEmpty {
                    let consume = swipe.claimed
                    if event.momentumPhase.contains(.ended) { swipe.reset() }
                    return consume ? nil : event
                }
                if event.phase.contains(.began) || event.timestamp - lastEvent > 0.5 { swipe.reset() }
                lastEvent = event.timestamp
                if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                    return swipe.claimed ? nil : event
                }
                // Ignore mouse wheels and unphased synthetic scrolling.
                guard !event.phase.isEmpty else { return event }
                let physicalX = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
                let physicalY = event.isDirectionInvertedFromDevice ? event.scrollingDeltaY : -event.scrollingDeltaY
                let threshold = max(45, Defaults[.gestureSensitivity] * 0.35)
                if let step = swipe.update(dx: physicalX, dy: physicalY, threshold: threshold) { navigate(step) }
                return swipe.claimed ? nil : event
            }
        }
        func dispose() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            swipe.reset()
        }
    }
}

enum PanDirection {
    case left, right, up, down

    var isHorizontal: Bool { self == .left || self == .right }
    var sign: CGFloat { (self == .right || self == .down) ? 1 : -1 }

    func signed(from translation: CGSize) -> CGFloat { (isHorizontal ? translation.width : translation.height) * sign }
    func signed(deltaX: CGFloat, deltaY: CGFloat) -> CGFloat { (isHorizontal ? deltaX : deltaY) * sign }
}

extension View {
    func panGesture(direction: PanDirection, threshold: CGFloat = 4, capturesMouseDrag: Bool = true, action: @escaping (CGFloat, NSEvent.Phase) -> Void) -> some View {
        self
            .conditionalModifier(capturesMouseDrag) { view in
                view.gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let s = direction.signed(from: value.translation)
                            guard s > 0, s.magnitude >= threshold else { return }
                            action(s.magnitude, .changed)
                        }
                        .onEnded { _ in action(0, .ended) }
                )
            }
            .background(ScrollMonitor(direction: direction, threshold: threshold, action: action))
    }
}

private struct ScrollMonitor: NSViewRepresentable {
    let direction: PanDirection
    let threshold: CGFloat
    let action: (CGFloat, NSEvent.Phase) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitor(on: view)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.removeMonitor() }

    func makeCoordinator() -> Coordinator { 
        Coordinator(direction: direction, threshold: threshold, action: action) 
    }

    @MainActor final class Coordinator: NSObject {
        private let direction: PanDirection
        private let threshold: CGFloat
        private let action: (CGFloat, NSEvent.Phase) -> Void
        private var monitor: Any?
        private var accumulated: CGFloat = 0
        private var active = false
            private var endTask: Task<Void, Never>?
        private let noiseThreshold: CGFloat = 0.2

        init(direction: PanDirection, threshold: CGFloat, action: @escaping (CGFloat, NSEvent.Phase) -> Void) {
            self.direction = direction
            self.threshold = threshold
            self.action = action
        }

        private func scheduleEndTimeout() {
            // Cancel any existing scheduled end and schedule a new one.
            endTask?.cancel()
            endTask = Task { @MainActor in
                // If no new scroll event arrives within this window, consider the gesture ended.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                if active {
                    action(accumulated.magnitude, .ended)
                } else {
                    action(0, .ended)
                }
                active = false
                accumulated = 0
            }
        }

        func installMonitor(on view: NSView) {
            removeMonitor()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self, weak view] event in
                guard let self = self, event.window === view?.window else { return event }
                self.handleScroll(event)
                return event
            }
        }

        func removeMonitor() {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            accumulated = 0
            active = false
            endTask?.cancel()
            endTask = nil
        }

        private func handleScroll(_ event: NSEvent) {
            if event.phase == .ended || event.momentumPhase == .ended {
                if active {
                    action(accumulated.magnitude, .ended)
                } else {
                    action(0, .ended)
                }
                active = false
                accumulated = 0
                return
            }

            // Only consider scroll events that are primarily along the configured axis.
            let absDX = abs(event.scrollingDeltaX)
            let absDY = abs(event.scrollingDeltaY)
            // Require the movement along the gesture axis to be at least 1.5x the orthogonal axis.
            let axisDominanceFactor: CGFloat = 1.5
            let isAxisDominant: Bool = direction.isHorizontal ? (absDX >= axisDominanceFactor * absDY) : (absDY >= axisDominanceFactor * absDX)
            guard isAxisDominant else { return }

            // Scale non-precise (mouse wheel) scrolling deltas so they feel similar to
            // trackpad gestures.
            let raw = direction.signed(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY)
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 8
            let s = raw * scale
            guard s.magnitude > noiseThreshold else { return }
            accumulated = s > 0 ? accumulated + s : 0

            if !active && accumulated >= threshold {
                active = true
                action(accumulated.magnitude, .began)
            } else if active {
                action(accumulated.magnitude, .changed)
            }
            // Schedule a timeout to end the gesture if no further scroll events arrive.
            scheduleEndTimeout()
        }
    }
}
