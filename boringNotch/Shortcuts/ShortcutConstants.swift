//
//  Constants.swift
//  boringNotch
//
//  Created by Richard Kunkli on 16/08/2024.
//

import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let togglePersistentLyrics = Self("togglePersistentLyrics", default: .init(.l, modifiers: [.control, .option, .command]))
    static let openFocusSession = Self("openFocusSession", default: .init(.f, modifiers: [.control, .option, .command]))
    static let toggleFocusSession = Self("toggleFocusSession", default: .init(.space, modifiers: [.control, .option, .command]))
    static let clipboardHistoryPanel = Self("clipboardHistoryPanel", default: .init(.v, modifiers: [.shift, .command]))
    static let toggleMicrophone = Self("toggleMicrophone", default: .init(.f5, modifiers: [.function]))
    static let decreaseBacklight = Self("decreaseBacklight", default: .init(.f1, modifiers: [.command]))
    static let increaseBacklight = Self("increaseBacklight", default: .init(.f2, modifiers: [.command]))
    static let toggleSneakPeek = Self("toggleSneakPeek", default: .init(.h, modifiers: [.command, .shift]))
    static let toggleNotchOpen = Self("toggleNotchOpen", default: .init(.i, modifiers: [.command, .shift]))
}
