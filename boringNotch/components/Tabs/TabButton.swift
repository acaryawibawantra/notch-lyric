//
//  TabButton.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-24.
//

import SwiftUI

struct TabButton: View {
    let label: String
    let icon: String
    let selected: Bool
    var showsLabel = false
    let onClick: () -> Void
    @State private var hovering = false
    
    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12, weight: .medium))
                if selected && showsLabel {
                    Text(label).font(.system(size: 11, weight: .medium)).fixedSize()
                }
            }
            .padding(.horizontal, selected && showsLabel ? 9 : 8)
            .frame(minWidth: 30, minHeight: 28)
            .background(hovering && !selected ? Color.white.opacity(0.05) : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onHover { hovering = $0 }
    }
}

#Preview {
    TabButton(label: "Home", icon: "tray.fill", selected: true) {
        print("Tapped")
    }
}
