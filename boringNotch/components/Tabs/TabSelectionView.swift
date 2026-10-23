//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

let tabs = [
    TabModel(label: "Media", icon: "music.note", view: .home),
    TabModel(label: "Focus", icon: "timer", view: .focus),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf),
    TabModel(label: "Tools", icon: "square.grid.2x2", view: .everyday),
    TabModel(label: "Prompter", icon: "text.viewfinder", view: .prompter),
    TabModel(label: "Tasks", icon: "terminal", view: .tasks)
].filter { $0.view != .tasks || MorisTaskFeature.isEnabled }

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Namespace var animation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ViewThatFits(in: .horizontal) {
            navigation(showsLabel: true)
            navigation(showsLabel: false)
        }
    }

    private func navigation(showsLabel: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view, showsLabel: showsLabel) {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: 28)
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .white.opacity(0.55))
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(Color.white.opacity(0.11))
                                .matchedGeometryEffect(id: showsLabel ? "labeledSelection" : "iconSelection", in: animation)
                        }
                    }
            }
        }
        .clipShape(Capsule())
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
