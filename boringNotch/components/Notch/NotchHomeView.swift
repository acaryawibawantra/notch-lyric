//
//  NotchHomeView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-18.
//  Modified by Harsh Vardhan Goswami & Richard Kunkli & Mustafa Ramadan
//

import Combine
import Defaults
import SwiftUI

// MARK: - Music Player Components

struct MusicPlayerView: View {
    @EnvironmentObject var vm: BoringViewModel
    let albumArtNamespace: Namespace.ID

    var body: some View {
        HStack(alignment: .top) {
            AlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace)
                .frame(maxWidth: 120, maxHeight: 120)
                .padding(.all, 5)
            MusicControlsView()
        }
    }
}

struct AlbumArtView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var vm: BoringViewModel
    let albumArtNamespace: Namespace.ID

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if Defaults[.lightingEffect] {
                albumArtBackground
            }
            albumArtButton
        }
    }

    private var albumArtBackground: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Defaults[.cornerRadiusScaling]
                        ? MusicPlayerImageSizes.cornerRadiusInset.opened
                        : MusicPlayerImageSizes.cornerRadiusInset.closed)
            )
            .aspectRatio(1, contentMode: .fit)
            .scaleEffect(x: 1.3, y: 1.4)
            .rotationEffect(.degrees(92))
            .blur(radius: 40)
            .opacity(musicManager.isPlaying ? 0.5 : 0)
    }

    private var albumArtButton: some View {
        ZStack {
            Button {
                musicManager.openMusicApp()
            } label: {
                ZStack(alignment:.bottomTrailing) {
                    albumArtImage
                    appIconOverlay
                }
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(musicManager.isPlaying ? 1 : 0.85)
            
            albumArtDarkOverlay
        }
    }

    private var albumArtDarkOverlay: some View {
        Rectangle()
            .aspectRatio(1, contentMode: .fit)
            .foregroundColor(Color.black)
            .opacity(musicManager.isPlaying ? 0 : 0.8)
            .blur(radius: 50)
    }
                

    private var albumArtImage: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Defaults[.cornerRadiusScaling]
                        ? MusicPlayerImageSizes.cornerRadiusInset.opened
                        : MusicPlayerImageSizes.cornerRadiusInset.closed)
            )
    }

    @ViewBuilder
    private var appIconOverlay: some View {
        if vm.notchState == .open && !musicManager.usingAppIconForArtwork {
            AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 30, height: 30)
                .offset(x: 10, y: 10)
                .transition(.scale.combined(with: .opacity))
                .zIndex(2)
        }
    }
}

struct MusicControlsView: View {
    var hidesInlineLyrics = false
    @ObservedObject var musicManager = MusicManager.shared
        @EnvironmentObject var vm: BoringViewModel
        @ObservedObject var webcamManager = WebcamManager.shared
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    @Default(.musicControlSlots) private var slotConfig
    @Default(.musicControlSlotLimit) private var slotLimit
    @Default(.lyricAlignment) private var lyricAlignment
    @Default(.lyricTextSize) private var lyricTextSize
    @Default(.animateLyricTransitions) private var animateLyricTransitions
    @Default(.lyricDisplayMode) private var lyricDisplayMode
    @Default(.expandedMediaLyrics) private var expandedMediaLyrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 10) {
                songInfo(width: geo.size.width)
                if !hidesInlineLyrics { Spacer(minLength: 0) }
                musicSlider
                slotToolbar.frame(height: 36)
            }
        }
        // Insets belong outside GeometryReader: padding inside its VStack added
        // height beyond the proposed bounds and pushed transport into the chin.
        .padding(.top, 8)
        .padding(.leading, 5)
        .padding(.bottom, 12)
        .buttonStyle(PlainButtonStyle())
    }

    private func songInfo(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                MarqueeText(
                    $musicManager.songTitle, font: .headline, nsFont: .headline, textColor: .white,
                    frameWidth: max(0, width - (Defaults[.enableLyrics] ? (hidesInlineLyrics ? 30 : 60) : 0)))
                if Defaults[.enableLyrics] {
                    Button {
                        let closing = MediaCompanion.current == .lyrics
                        Defaults[.mediaCompanion] = closing ? .none : .lyrics
                        expandedMediaLyrics = !closing
                    } label: {
                        Image(systemName: MediaCompanion.current == .lyrics ? "rectangle.compress.vertical" : "list.bullet")
                            .font(.system(size: 12))
                            .frame(width: 24, height: 24)
                    }
                    .help(MediaCompanion.current == .lyrics ? "Return to compact player" : "Show full lyrics alongside player")
                    .accessibilityLabel(MediaCompanion.current == .lyrics ? "Close full lyrics" : "Show full lyrics")
                    if !hidesInlineLyrics {
                    Button {
                        lyricDisplayMode = lyricDisplayMode == .karaoke ? .compact : .karaoke
                    } label: {
                        Image(systemName: lyricDisplayMode == .karaoke ? "text.bubble.fill" : "text.bubble")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 20)
                    }
                    .help(lyricDisplayMode == .karaoke ? "Switch to compact lyrics" : "Show detailed lyrics")
                    .accessibilityLabel("Toggle detailed lyrics")
                    }
                }
            }
            MarqueeText(
                $musicManager.artistName,
                font: .headline,
                nsFont: .headline,
                textColor: Defaults[.playerColorTinting]
                    ? Color(nsColor: musicManager.avgColor)
                        .ensureMinimumBrightness(factor: 0.6) : .gray,
                frameWidth: width
            )
            .fontWeight(.medium)
            if Defaults[.enableLyrics] && !hidesInlineLyrics {
                lyricsView(width: width)
            }
        }
    }

    @ViewBuilder
    private func lyricsView(width: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 0.25)) { timeline in
            let currentElapsed: Double = {
                guard musicManager.isPlaying else { return musicManager.elapsedTime }
                let delta = timeline.date.timeIntervalSince(musicManager.timestampDate)
                let progressed = musicManager.elapsedTime + (delta * musicManager.playbackRate)
                return min(max(progressed, 0), musicManager.songDuration)
            }()

            if lyricDisplayMode == .karaoke,
               !musicManager.isFetchingLyrics,
               !musicManager.syncedLyrics.isEmpty {
                let context = musicManager.lyricContext(at: currentElapsed)
                VStack(alignment: lyricAlignment == .leading ? .leading : .center, spacing: 2) {
                    Text(context.previous ?? " ")
                        .font(lyricTextSize.surroundingFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(context.current)
                        .font(lyricTextSize.activeFont)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                    Text(context.next ?? " ")
                        .font(lyricTextSize.surroundingFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .multilineTextAlignment(lyricAlignment.textAlignment)
                .frame(maxWidth: width, alignment: lyricAlignment.frameAlignment)
                .opacity(musicManager.isPlaying ? 1 : 0.65)
                .animation(
                    animateLyricTransitions && !reduceMotion ? .easeInOut(duration: 0.2) : nil,
                    value: context.current
                )
            } else {
                let line: String = {
                    if musicManager.isFetchingLyrics { return "Loading lyrics…" }
                    if !musicManager.syncedLyrics.isEmpty {
                        return musicManager.lyricLine(at: currentElapsed)
                    }
                    let trimmed = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? "No lyrics found" : trimmed.replacingOccurrences(of: "\n", with: " ")
                }()
                let isPersian = line.unicodeScalars.contains { scalar in
                    let value = scalar.value
                    return value >= 0x0600 && value <= 0x06FF
                }
                MarqueeText(
                    .constant(line),
                    font: .subheadline,
                    nsFont: .subheadline,
                    textColor: musicManager.isFetchingLyrics ? .gray.opacity(0.7) : .gray,
                    frameWidth: width
                )
                .font(isPersian ? .custom("Vazirmatn-Regular", size: NSFont.preferredFont(forTextStyle: .subheadline).pointSize) : .subheadline)
                .lineLimit(1)
                .opacity(musicManager.isPlaying ? 1 : 0)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var musicSlider: some View {
        TimelineView(.animation(minimumInterval: musicManager.playbackRate > 0 ? 0.1 : nil)) { timeline in
            MusicSliderView(
                sliderValue: $sliderValue,
                duration: $musicManager.songDuration,
                lastDragged: $lastDragged,
                color: musicManager.avgColor,
                dragging: $dragging,
                currentDate: timeline.date,
                timestampDate: musicManager.timestampDate,
                elapsedTime: musicManager.elapsedTime,
                playbackRate: musicManager.playbackRate,
                isPlaying: musicManager.isPlaying
            ) { newValue in
                MusicManager.shared.seek(to: newValue)
            }
            .padding(.top, 5)
            .frame(height: 36)
        }
    }

    private var slotToolbar: some View {
        let slots = activeSlots
        return HStack(spacing: 6) {
            ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                slotView(for: slot)
                    .frame(alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var activeSlots: [MusicControlButton] {
        let sanitizedLimit = min(
            max(slotLimit, MusicControlButton.minSlotCount),
            MusicControlButton.maxSlotCount
        )
        let padded = slotConfig.padded(to: sanitizedLimit, filler: .none)
        // Companion and camera never occupy a third column, so keep configured actions.
        return Array(padded.prefix(sanitizedLimit))
    }

    @ViewBuilder
    private func slotView(for slot: MusicControlButton) -> some View {
        switch slot {
        case .shuffle:
            HoverButton(icon: "shuffle", iconColor: musicManager.isShuffled ? .red : .primary, scale: .medium) {
                MusicManager.shared.toggleShuffle()
            }
        case .previous:
            HoverButton(icon: "backward.fill", scale: .medium) {
                MusicManager.shared.previousTrack()
            }
        case .playPause:
            HoverButton(icon: musicManager.isPlaying ? "pause.fill" : "play.fill", scale: .large) {
                MusicManager.shared.togglePlay()
            }
        case .next:
            HoverButton(icon: "forward.fill", scale: .medium) {
                MusicManager.shared.nextTrack()
            }
        case .repeatMode:
            HoverButton(icon: repeatIcon, iconColor: repeatIconColor, scale: .medium) {
                MusicManager.shared.toggleRepeat()
            }
        case .volume:
            VolumeControlView()
        case .favorite:
            FavoriteControlButton()
        case .goBackward:
            HoverButton(icon: "gobackward.15", scale: .medium) {
                MusicManager.shared.skip(seconds: -15)
            }
        case .goForward:
            HoverButton(icon: "goforward.15", scale: .medium) {
                MusicManager.shared.skip(seconds: 15)
            }
        case .none:
            Color.clear.frame(height: 1)
        }
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off:
            return "repeat"
        case .all:
            return "repeat"
        case .one:
            return "repeat.1"
        }
    }

    private var repeatIconColor: Color {
        switch musicManager.repeatMode {
        case .off:
            return .primary
        case .all, .one:
            return .red
        }
    }
}

struct FavoriteControlButton: View {
    @ObservedObject var musicManager = MusicManager.shared

    var body: some View {
        HoverButton(icon: iconName, iconColor: iconColor, scale: .medium) {
            MusicManager.shared.toggleFavoriteTrack()
        }
        .disabled(!musicManager.canFavoriteTrack)
        .opacity(musicManager.canFavoriteTrack ? 1 : 0.35)
    }

    private var iconName: String {
        musicManager.isFavoriteTrack ? "heart.fill" : "heart"
    }

    private var iconColor: Color {
        musicManager.isFavoriteTrack ? .red : .primary
    }
}

private extension Array where Element == MusicControlButton {
    func padded(to length: Int, filler: MusicControlButton) -> [MusicControlButton] {
        if count >= length { return self }
        return self + Array(repeating: filler, count: length - count)
    }
}

// MARK: - Volume Control View

struct VolumeControlView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @State private var volumeSliderValue: Double = 0.5
    @State private var dragging: Bool = false
    @State private var showVolumeSlider: Bool = false
    @State private var lastVolumeUpdateTime: Date = Date.distantPast
    private let volumeUpdateThrottle: TimeInterval = 0.1
    
    var body: some View {
        HStack(spacing: 4) {
            Button(action: {
                if musicManager.volumeControlSupported {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        showVolumeSlider.toggle()
                    }
                }
            }) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(musicManager.volumeControlSupported ? .white : .gray)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!musicManager.volumeControlSupported)
            .frame(width: 24)

            if showVolumeSlider && musicManager.volumeControlSupported {
                CustomSlider(
                    value: $volumeSliderValue,
                    range: 0.0...1.0,
                    color: .white,
                    dragging: $dragging,
                    lastDragged: .constant(Date.distantPast),
                    onValueChange: { newValue in
                        MusicManager.shared.setVolume(to: newValue)
                    },
                    onDragChange: { newValue in
                        let now = Date()
                        if now.timeIntervalSince(lastVolumeUpdateTime) > volumeUpdateThrottle {
                            MusicManager.shared.setVolume(to: newValue)
                            lastVolumeUpdateTime = now
                        }
                    }
                )
                .frame(width: 48, height: 8)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .clipped()
        .onReceive(musicManager.$volume) { volume in
            if !dragging {
                volumeSliderValue = volume
            }
        }
        .onReceive(musicManager.$volumeControlSupported) { supported in
            if !supported {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showVolumeSlider = false
                }
            }
        }
        .onChange(of: showVolumeSlider) { _, isShowing in
            if isShowing {
                // Sync volume from app when slider appears
                Task {
                    await MusicManager.shared.syncVolumeFromActiveApp()
                }
            }
        }
        .onDisappear {
            // volumeUpdateTask?.cancel() // No longer needed
        }
    }
    
    
    private var volumeIcon: String {
        if !musicManager.volumeControlSupported {
            return "speaker.slash"
        } else if volumeSliderValue == 0 {
            return "speaker.slash.fill"
        } else if volumeSliderValue < 0.33 {
            return "speaker.1.fill"
        } else if volumeSliderValue < 0.66 {
            return "speaker.2.fill"
        } else {
            return "speaker.3.fill"
        }
    }
}

// MARK: - Main View

/// Legacy settings remain untouched until the user explicitly chooses a companion.
enum MediaCompanion: String, CaseIterable, Defaults.Serializable {
    case legacy, none, calendar, reminders, timer, focus, lyrics

    static var current: Self {
        let saved = Defaults[.mediaCompanion]
        guard saved == .legacy else { return saved }
        if Defaults[.expandedMediaLyrics] && Defaults[.enableLyrics] { return .lyrics }
        return Defaults[.showCalendar] ? .calendar : .none
    }

    var title: String {
        switch self {
        case .legacy, .none: "Close split"
        case .calendar: "Calendar"
        case .reminders: "To-do"
        case .timer: "Timer"
        case .focus: "Focus"
        case .lyrics: "Lyrics"
        }
    }

    var symbol: String {
        switch self {
        case .legacy, .none: "xmark"
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .timer: "timer"
        case .focus: "scope"
        case .lyrics: "text.alignleft"
        }
    }
}

struct NotchHomeView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var webcamManager = WebcamManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject private var calendar = CalendarManager.shared
    let albumArtNamespace: Namespace.ID
    @Default(.expandedMediaLyrics) private var expandedMediaLyrics
    @Default(.enableLyrics) private var enableLyrics
    @Default(.lyricDisplayMode) private var lyricDisplayMode
    @Default(.mediaCompanion) private var companion
    @Default(.showCalendar) private var showCalendar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectedCompanion: MediaCompanion { MediaCompanion.current }

    var body: some View {
        Group {
            if !coordinator.firstLaunch {
                mainContent
            }
        }
        // simplified: use a straightforward opacity transition
        .transition(.opacity)
        .onChange(of: expandedMediaLyrics) { updateMediaSize() }
        .onChange(of: enableLyrics) { updateMediaSize() }
        .onChange(of: lyricDisplayMode) { updateMediaSize() }
        .onChange(of: companion) { updateMediaSize() }
        .onChange(of: showCalendar) { updateMediaSize() }
    }

    private func updateMediaSize() {
        guard vm.notchState == .open, coordinator.currentView == .home else { return }
        vm.notchSize = expandedPanelSize(for: .home)
    }

    private var shouldShowCamera: Bool {
        Defaults[.showMirror] && webcamManager.cameraAvailable && vm.isCameraExpanded
    }

    private var mainContent: some View {
        VStack(spacing: 8) {
            companionShortcuts
        if selectedCompanion == .lyrics {
            HStack(spacing: 24) {
                VStack(spacing: 8) {
                    AlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace)
                        .frame(width: 56, height: 56)
                    MusicControlsView(hidesInlineLyrics: true)
                        .frame(height: 148)
                }
                .frame(width: 285)
                FullMediaLyricsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
        HStack(alignment: .top, spacing: 20) {
            MusicPlayerView(albumArtNamespace: albumArtNamespace)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if selectedCompanion != .none {
                companionContent
                    .frame(width: 235, alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
            }

            if shouldShowCamera && selectedCompanion == .none {
                CameraPreviewView(webcamManager: webcamManager)
                    .scaledToFit()
                    .opacity(vm.notchState == .closed ? 0 : 1)
                    .blur(radius: vm.notchState == .closed ? 20 : 0)
                    .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.76, blendDuration: 0), value: shouldShowCamera)
            }
        }
        }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selectedCompanion)
        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
        .blur(radius: vm.notchState == .closed ? 30 : 0)
    }

    private var companionShortcuts: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            ForEach([MediaCompanion.calendar, .reminders, .timer, .focus, .lyrics], id: \.self) { panel in
                Button {
                    companion = panel
                    expandedMediaLyrics = panel == .lyrics
                    if panel == .lyrics { enableLyrics = true }
                } label: {
                    Image(systemName: panel.symbol)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 27, height: 25)
                        .foregroundStyle(selectedCompanion == panel ? .primary : .secondary)
                        .background(selectedCompanion == panel ? Color.white.opacity(0.12) : .clear,
                                    in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help("Show \(panel.title) beside Media")
                .accessibilityLabel("Show \(panel.title) beside Media")
                .accessibilityAddTraits(selectedCompanion == panel ? [.isSelected] : [])
            }
            if selectedCompanion != .none {
                Divider().frame(height: 12).padding(.horizontal, 3)
                Button {
                    companion = .none
                    expandedMediaLyrics = false
                } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
                        .frame(width: 25, height: 25)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close split · music and timers keep running")
                .accessibilityLabel("Close split")
            }
        }
        .frame(height: 25)
    }

    @ViewBuilder private var companionContent: some View {
        switch selectedCompanion {
        case .calendar:
            Group {
                if calendar.calendarAuthorizationStatus == .fullAccess {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Calendar", systemImage: "calendar").font(.headline)
                        CalendarView()
                            .onHover { vm.isHoveringCalendar = $0 }
                    }
                } else {
                    TodayActivityView()
                }
            }
            .onDisappear { vm.isHoveringCalendar = false }
            .task { await calendar.reloadCalendarAndReminderLists() }
        case .reminders: FocusTaskList()
        case .timer: MediaTimerCompanion()
        case .focus: MediaFocusCompanion()
        case .lyrics: FullMediaLyricsView()
        case .none, .legacy: EmptyView()
        }
    }
}

private struct MediaTimerCompanion: View {
    @ObservedObject private var clock = UtilityClockModel.shared
    @Default(.toolsAccent) private var accent

    private var progress: Double {
        clock.timerDone ? 1 : clock.timerVisible ? 1 - Double(clock.remaining) / Double(max(1, clock.selectedSeconds)) : 0
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Timer", systemImage: "timer").font(.headline)
                Spacer()
                Text(clock.timerDone ? "Completed" : clock.timerRunning ? "Running" : clock.timerVisible ? "Paused" : "Ready")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text(clock.timerDone ? "Done" : UtilityClockModel.formatted(clock.timerVisible ? clock.remaining : clock.selectedSeconds))
                .font(.system(size: 38, weight: .medium, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
            ProgressView(value: min(1, max(0, progress))).tint(accent.color)
                .accessibilityLabel("Timer progress")
            if !clock.timerVisible || clock.timerDone {
                HStack(spacing: 6) {
                    ForEach([5, 15, 25], id: \.self) { minutes in
                        Button("\(minutes)m") { clock.minutes = minutes }
                            .frame(maxWidth: .infinity)
                            .toolButton(compact: true)
                    }
                }
                Stepper("\(clock.minutes) min", value: $clock.minutes, in: 1...120).font(.caption)
            }
            HStack {
                Button(clock.timerRunning ? "Pause" : clock.timerVisible && !clock.timerDone ? "Resume" : "Start",
                       systemImage: clock.timerRunning ? "pause.fill" : "play.fill") { clock.toggleTimer() }
                    .toolButton(prominent: true, compact: true)
                Button("Reset") { clock.resetTimer() }.toolButton(compact: true)
                    .disabled(!clock.timerVisible)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Label("Stopwatch", systemImage: "stopwatch").font(.caption2)
                Spacer(minLength: 0)
                Text(UtilityClockModel.formatted(clock.stopwatchSeconds)).font(.caption.monospacedDigit())
                Button {
                    clock.toggleStopwatch()
                } label: {
                    Image(systemName: clock.stopwatchRunning ? "pause.fill" : "play.fill")
                        .frame(width: 24, height: 24)
                }.buttonStyle(.plain)
                    .help(clock.stopwatchRunning ? "Pause stopwatch" : "Start or resume stopwatch")
                    .accessibilityLabel(clock.stopwatchRunning ? "Pause stopwatch" : "Start or resume stopwatch")
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct MediaFocusCompanion: View {
    @ObservedObject private var focus = FocusTimerModel.shared
    @Default(.toolsAccent) private var accent
    @Default(.mediaCompanion) private var companion

    private var progress: Double {
        focus.isFinished ? 1 : focus.isVisible ? 1 - Double(focus.remainingSeconds) / Double(max(1, focus.sessionMinutes * 60)) : 0
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Focus", systemImage: "scope").font(.headline)
                Spacer()
                Text(focus.isFinished ? "Completed" : focus.isRunning ? "Running" : focus.isVisible ? "Paused" : "Ready")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text(focus.goal.isEmpty ? "Choose a task in To-do, or start a focus session." : focus.goal)
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .center)
            Text(focus.isFinished ? "Done" : UtilityClockModel.formatted(focus.isVisible ? focus.remainingSeconds : focus.durationMinutes * 60))
                .font(.system(size: 38, weight: .medium, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
            ProgressView(value: min(1, max(0, progress))).tint(accent.color)
                .accessibilityLabel("Focus session progress")
            if !focus.isVisible || focus.isFinished {
                Stepper("\(focus.durationMinutes) min", value: $focus.durationMinutes, in: 1...120).font(.caption)
            }
            HStack {
                Button(focus.isRunning ? "Pause" : focus.isFinished ? "Start again" : "Start",
                       systemImage: focus.isRunning ? "pause.fill" : "play.fill") {
                    if focus.isRunning { focus.pause() } else { focus.start() }
                }.toolButton(prominent: true, compact: true)
                Button("Reset") { focus.reset() }.toolButton(compact: true)
                    .disabled(!focus.isVisible)
            }
            Spacer(minLength: 0)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today").font(.caption2).foregroundStyle(.secondary)
                    Text("\(focus.completedSessions) sessions · \(focus.focusedMinutesToday) min")
                        .font(.caption2.weight(.medium)).lineLimit(1)
                }
                Spacer(minLength: 4)
                Button { companion = .reminders } label: {
                    Image(systemName: "checklist").frame(width: 26, height: 26)
                }.buttonStyle(.plain).help("Choose a task from Apple Reminders")
                    .accessibilityLabel("Choose a task from Apple Reminders")
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Full lyrics are opt-in: compact player and floating notch lyrics stay unchanged.
private struct FullMediaLyricsView: View {
    @ObservedObject private var music = MusicManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Default(.animateLyricTransitions) private var animateLyricTransitions
    @State private var followsPlayback = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Lyrics", systemImage: "text.alignleft")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !music.syncedLyrics.isEmpty && !music.isFetchingLyrics {
                    Button {
                        followsPlayback.toggle()
                    } label: {
                        Label(followsPlayback ? "Following" : "Follow", systemImage: followsPlayback ? "location.fill" : "location")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(followsPlayback ? .white : .gray)
                    .help("Turn off Follow to browse lyrics freely")
                    .accessibilityAddTraits(followsPlayback ? [.isSelected] : [])
                }
            }
            if music.isFetchingLyrics {
                placeholder("Loading lyrics…", symbol: "ellipsis")
            } else if !music.syncedLyrics.isEmpty {
                syncedLyrics
                    .id(music.songTitle + "\n" + music.artistName)
            } else if !music.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView {
                    Text(music.currentLyrics)
                        .font(.system(size: 16, weight: .medium))
                        .lineSpacing(7)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 16)
                }
                .scrollIndicators(.hidden)
            } else {
                placeholder("Lyrics aren’t available for this song", symbol: "text.bubble")
            }
        }
        .onChange(of: music.songTitle) { followsPlayback = true }
    }

    private var syncedLyrics: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !music.isPlaying)) { timeline in
            let elapsed = music.estimatedPlaybackPosition(at: timeline.date)
            // Use timestamp indices, not lyric text: repeated chorus lines remain distinct.
            let active = music.syncedLyrics.lastIndex(where: { $0.time <= elapsed }) ?? -1
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(music.syncedLyrics.indices, id: \.self) { index in
                            let line = music.syncedLyrics[index]
                            Button {
                                music.seek(to: line.time)
                            } label: {
                                Text(line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "♪" : line.text)
                                    .font(.system(size: 17, weight: index == active ? .semibold : .medium))
                                    .foregroundStyle(index == active ? .white : .white.opacity(0.4))
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(index)
                            .help("Play from this line")
                            .accessibilityLabel(line.text.isEmpty ? "Instrumental" : line.text)
                            .accessibilityHint("Play from this lyric")
                            .accessibilityAddTraits(index == active ? [.isSelected] : [])
                        }
                    }
                    .padding(.vertical, 50)
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
                .mask {
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.12),
                        .init(color: .black, location: 0.88),
                        .init(color: .clear, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                }
                .onAppear { proxy.scrollTo(max(0, active), anchor: .center) }
                .onChange(of: active) {
                    guard followsPlayback else { return }
                    withAnimation(!reduceMotion && animateLyricTransitions ? .easeInOut(duration: 0.3) : nil) {
                        proxy.scrollTo(max(0, active), anchor: .center)
                    }
                }
                .onChange(of: followsPlayback) {
                    if followsPlayback { proxy.scrollTo(max(0, active), anchor: .center) }
                }
            }
        }
    }

    private func placeholder(_ title: String, symbol: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 24, weight: .light))
            Text(title).font(.system(size: 12)).multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MusicSliderView: View {
    @Binding var sliderValue: Double
    @Binding var duration: Double
    @Binding var lastDragged: Date
    var color: NSColor
    @Binding var dragging: Bool
    let currentDate: Date
    let timestampDate: Date
    let elapsedTime: Double
    let playbackRate: Double
    let isPlaying: Bool
    var onValueChange: (Double) -> Void


    var body: some View {
        VStack {
            CustomSlider(
                value: $sliderValue,
                range: 0...duration,
                color: Defaults[.sliderColor] == SliderColorEnum.albumArt
                    ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.8)
                    : Defaults[.sliderColor] == SliderColorEnum.accent ? .effectiveAccent : .white,
                dragging: $dragging,
                lastDragged: $lastDragged,
                onValueChange: onValueChange
            )
            .frame(height: 10, alignment: .center)

            HStack {
                Text(timeString(from: sliderValue))
                Spacer()
                Text(timeString(from: duration))
            }
            .fontWeight(.medium)
            .foregroundColor(
                Defaults[.playerColorTinting]
                    ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.6) : .gray
            )
            .font(.caption)
        }
        .onChange(of: currentDate) {
           guard !dragging, timestampDate.timeIntervalSince(lastDragged) > -1 else { return }
            sliderValue = MusicManager.shared.estimatedPlaybackPosition(at: currentDate)
        }
    }

    func timeString(from seconds: Double) -> String {
        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }
}

struct CustomSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color = .white
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    var onValueChange: ((Double) -> Void)?
    var onDragChange: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = CGFloat(dragging ? 9 : 5)
            let rangeSpan = range.upperBound - range.lowerBound

            let progress = rangeSpan == .zero ? 0 : (value - range.lowerBound) / rangeSpan
            let filledTrackWidth = min(max(progress, 0), 1) * width

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.gray.opacity(0.3))
                    .frame(height: height)

                Rectangle()
                    .fill(color)
                    .frame(width: filledTrackWidth, height: height)
            }
            .cornerRadius(height / 2)
            .frame(height: 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        withAnimation {
                            dragging = true
                        }
                        let newValue = range.lowerBound + Double(gesture.location.x / width) * rangeSpan
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                        onDragChange?(value)
                    }
                    .onEnded { _ in
                        onValueChange?(value)
                        dragging = false
                        lastDragged = Date()
                    }
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: dragging)
        }
    }
}
