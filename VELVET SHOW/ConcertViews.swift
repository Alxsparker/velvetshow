//
//  ConcertViews.swift
//  VELVET SHOW
//

import SwiftUI
import UniformTypeIdentifiers

private enum PerformanceChrome {
    static let hudRadius: CGFloat = 16
    static let tileRadius: CGFloat = 10
    static let panelStroke = Color.white.opacity(0.12)
    static let panelHighlight = Color.white.opacity(0.08)
    static let activeGlow = VelvetPalette.nowPlayingYellow.opacity(0.36)
}

struct CompactConcertStrip: View {
    let appState: AppState
    let set: ShowSet
    let songs: [Song]
    @Environment(\.openWindow) private var openWindow
    @State private var isShowingCartridgesDetail = false
    @State private var isShowingAnalysis = false

    private var queue: [ConcertQueueItem] { appState.queueItems(for: set) }

    private var remainingByGenre: [(genre: ConcertGenre, count: Int)] {
        let remaining = songs.filter { !appState.isPlayed($0, in: set) }
        return ConcertGenre.allCases
            .filter { $0 != .all }
            .map { genre in
                (genre, remaining.filter { appState.concertGenre(for: $0) == genre }.count)
            }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
    }

    /// La carte Queue embarquée n'est affichée que si la fenêtre Queue
    /// flottante est masquée — sinon on aurait l'info deux fois côte à
    /// côte. Soit l'une, soit l'autre.
    private var showsEmbeddedQueue: Bool {
        !queue.isEmpty && !appState.isFloatingQueueVisible
    }

    var body: some View {
        compactBar
            .onChange(of: queue.count) { _, newCount in
                if newCount == 0 {
                    QueueFloatingWindowController.hideBecauseQueueIsEmpty()
                }
            }
            .onChange(of: appState.queueAddedFromLibraryTick) { _, _ in
                let count = appState.queueItems(for: set).count
                if count > 0 {
                    QueueFloatingWindowController.markAutoReopenHandled()
                    openWindow(id: QueueFloatingView.windowID)
                }
            }
    }

    @ViewBuilder
    private var compactBar: some View {
        // Ligne Queue supprimée — les infos sont visibles directement
        // sur les tuiles (badge À SUIVRE, icône ✕). Les .onChange sur
        // queue.count et queueAddedFromLibraryTick restent actifs ci-dessus.
    }

    /// Ligne Queue compacte :  ⚡ Queue (N) : Track1 → Track2 → ...
    /// Tous les songs dans l'ordre, tronqués en queue si la ligne est trop longue.
    private var inlineQueueLine: some View {
        HStack(spacing: 5) {
            Image(systemName: "bolt.fill")
                .font(.caption.bold())
                .foregroundStyle(QueuePalette.accent)

            let names = queue.compactMap { appState.audioFilesByID[$0.audioFileID]?.name ?? "?" }
            Text("Queue (\(queue.count)) : \(names.joined(separator: " → "))")
                .font(.caption.bold())
                .foregroundStyle(QueuePalette.accent)
                .lineLimit(1)
                .truncationMode(.tail)

            Button {
                openWindow(id: QueueFloatingView.windowID)
            } label: {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.caption2)
                    .foregroundStyle(QueuePalette.accent.opacity(0.7))
            }
            .buttonStyle(.borderless)
            .help("Open Floating Queue")
        }
    }

    // MARK: Mini Transport Bar

    @ViewBuilder
    private var queueSummary: some View {
        if queue.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.caption)
                Text("Queue (0)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 8) {
                Label("Queue (\(queue.count))", systemImage: "bolt.fill")
                    .font(.caption.bold())
                    .foregroundStyle(QueuePalette.accent)
                Button {
                    openWindow(id: QueueFloatingView.windowID)
                } label: {
                    Label("Open Floating Queue", systemImage: "macwindow.on.rectangle")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(QueuePalette.accent)
            }
        }
    }

    private func handleQueueCountChange(_ count: Int) {
        // Comportement par défaut : la queue s'affiche dans une petite
        // fenêtre flottante. Dès qu'un item arrive, on l'ouvre — quelle
        // que soit la raison (l'ancien `shouldAutoReopen` n'était mis à
        // true qu'après une fermeture auto, donc la fenêtre ne s'ouvrait
        // jamais toute seule la première fois).
        if count == 0 {
            QueueFloatingWindowController.hideBecauseQueueIsEmpty()
        } else {
            QueueFloatingWindowController.markAutoReopenHandled()
            openWindow(id: QueueFloatingView.windowID)
        }
    }

    /// Section catégories — affiche uniquement l'icône + bouton d'accès au
    /// panneau détaillé. Les compteurs par genre ont été retirés de la vue
    /// principale (bruit visuel en scène) mais restent consultables via le
    /// panneau `RemainingCartridgesPanel`. La logique `remainingByGenre` est
    /// intacte et alimente ce panneau.
    @ViewBuilder
    private var cartridgesSection: some View {
        Button {
            isShowingCartridgesDetail = true
        } label: {
            Label("Categories", systemImage: "chart.bar.fill")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help("Distribution of remaining songs by category")
        .popover(isPresented: $isShowingCartridgesDetail, arrowEdge: .bottom) {
            RemainingCartridgesPanel(appState: appState, set: set, songs: songs)
                .frame(width: 320, height: 220)
                .padding(10)
        }
    }

    private var analysisButton: some View {
        Button {
            isShowingAnalysis = true
        } label: {
            Label("Analysis", systemImage: "chart.line.uptrend.xyaxis")
                .font(.caption.bold())
                .foregroundStyle(isShowingAnalysis ? VSColor.interactive : .primary)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(VSColor.interactive)
        .help("Concert history and risk level of current song")
        .popover(isPresented: $isShowingAnalysis, arrowEdge: .bottom) {
            ConcertStatsPanel(appState: appState)
                .frame(width: 460, height: 420)
                .padding(10)
        }
    }
}

enum QueuePalette {
    static let accent = Color.cyan
    static let accentStrong = Color(red: 0.0, green: 0.72, blue: 1.0)
    static let background = Color.cyan.opacity(0.14)
    static let border = Color.cyan.opacity(0.55)
}

// MARK: - VU-mètre vertical discret

struct VUMeterView: View {
    let level: Float

    private var normalized: Double {
        Double(min(1.0, level * 2.5))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(meterGradient)
                    .opacity(0.18)
                RoundedRectangle(cornerRadius: 2)
                    .fill(meterGradient)
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: geo.size.width * normalized)
                            .animation(.linear(duration: 0.05), value: normalized)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    private var meterGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .green,  location: 0.0),
                .init(color: .green,  location: 0.70),
                .init(color: .orange, location: 0.88),
                .init(color: .red,    location: 1.0),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Transport compact (⏮ ▶/⏸ ⏹)

/// Retour-au-début + Play/Pause + Stop en ligne compacte.
/// Visible uniquement si un song est chargé.
/// Extrait en struct indépendant for pouvoir être placé dans l'en-tête
/// du show sans dupliquer la logique.
struct MiniTransportBar: View {
    let appState: AppState

    var body: some View {
        HStack(spacing: 6) {
            // Transport toujours visible — boutons désactivés (grisés) tant
            // qu'aucun song n'est chargé, for une barre stable at l'écran.
            let hasTrack = appState.currentlyLoadedTrack != nil
            let engineState = appState.audioEngine.state

            Button {
                appState.returnToBeginning()
            } label: {
                Image(systemName: "backward.end.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!hasTrack)
            .help("Return to start")

            Button {
                if engineState == .playing {
                    appState.requestPause()
                } else {
                    appState.requestResume()
                }
            } label: {
                Image(systemName: engineState == .playing ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(engineState == .playing ? VSColor.warning : .green)
            .disabled(!hasTrack || engineState == .stopping)
            .help(engineState == .playing ? "Pause" : "Resume Playback")
            .anchorPreference(key: TourAnchorsKey.self, value: .bounds) {
                [TourAnchor.playPauseButton: $0]
            }

            Button {
                print("[VELVET] TRANSPORT STOP BUTTON → requestStop()")
                appState.requestStop()
            } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(engineState == .stopped ? nil : .red)
            .disabled(!hasTrack || engineState == .stopped || engineState == .stopping)
            .help("Stop + Stop Cue")

            HStack(spacing: 4) {
                Text("AUTO")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(appState.isAutoShowEnabled
                                     ? Color(red: 0.0, green: 0.9, blue: 0.2)
                                     : .secondary)
                Toggle("", isOn: Binding(
                    get: { appState.isAutoShowEnabled },
                    set: { appState.isAutoShowEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .tint(Color(red: 0.0, green: 0.9, blue: 0.2))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                appState.isAutoShowEnabled
                ? Color.green.opacity(0.16)
                : Color.white.opacity(0.05),
                in: Capsule()
            )
            .help(appState.isAutoShowEnabled
                  ? "AUTO SHOW enabled — automatic FILTER chaining"
                  : "AUTO SHOW disabled — toggle to enable")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PerformanceChrome.panelStroke, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Contrôle volume inline

/// − label dB + − VUMeter — visible uniquement si un song est en lecture
/// ou en pause. Extrait en struct for pouvoir être placé dans l'en-tête.
struct LiveVolumeControl: View {
    let appState: AppState
    /// false = variante compacte sans VU mètre, choisie par ViewThatFits
    /// quand l'en-tête du show manque de largeur.
    var showsVUMeter: Bool = true

    var body: some View {
        let track = appState.currentlyLoadedTrack
        HStack(spacing: 6) {
            Button {
                guard let track else { return }
                let current = appState.volumeOffsetDB(for: track)
                appState.setVolumeOffsetDB(max(VelvetTrackVolume.minimumDB, current - 1), for: track)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(track == nil)
            .help("Lower volume by 1 dB")

            Text(track.map { volumeLabel(for: $0) } ?? "– dB")
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .frame(width: 44, alignment: .center)
                .foregroundStyle(track.map { volumeColor(for: $0) } ?? .secondary)

            Button {
                guard let track else { return }
                let current = appState.volumeOffsetDB(for: track)
                appState.setVolumeOffsetDB(min(VelvetTrackVolume.maximumDB, current + 1), for: track)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(track == nil)
            .help("Raise volume by 1 dB")

            if showsVUMeter {
                VUMeterView(level: appState.audioEngine.meterLevel)
                    .frame(width: 86, height: 13)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PerformanceChrome.panelStroke, lineWidth: 1)
        }
    }

    private func volumeLabel(for track: AudioFile) -> String {
        let db = appState.volumeOffsetDB(for: track)
        if abs(db) < 0.05 { return "0 dB" }
        return String(format: "%+.0f dB", db)
    }

    private func volumeColor(for track: AudioFile) -> Color {
        let db = appState.volumeOffsetDB(for: track)
        if db > 0.05 { return .green }
        if db < -0.05 { return .orange }
        return .secondary
    }
}

// MARK: - Blink bordure "à suivre auto"

struct AutoBlinkBorder: View {
    let cornerRadius: CGFloat
    @State private var on = true

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(VelvetPalette.gold.opacity(on ? 0.95 : 0.15), lineWidth: 3)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                    on = false
                }
            }
    }
}

/// Pulse blanc très discret sur la tuile du song en cours.
/// Rappel visuel que la lecture est active — animation lente (1,4 s)
/// for ne pas distraire en plein concert.
struct NowPlayingPulseBorder: View {
    let cornerRadius: CGFloat
    @State private var glowing = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(Color.white.opacity(glowing ? 0.35 : 0.0), lineWidth: 3)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    glowing = true
                }
            }
    }
}

/// Halo pulsant Live Stage : indique le prochain song naturel dès que la lecture démarre.
/// Trois couches (bordure nette + halo flou + lueur diffuse) for une lisibilité at distance.
/// Actif tout au long du song en cours, effacé sur stop explicite.
struct NextNaturalBorder: View {
    let cornerRadius: CGFloat
    @State private var phase: Double = 0

    var body: some View {
        ZStack {
            // Lueur extérieure diffuse
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(VelvetPalette.velvetBlue.opacity(phase * 0.7), lineWidth: 14)
                .blur(radius: 10)
            // Halo intermédiaire
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(VelvetPalette.velvetBlue.opacity(phase * 0.9), lineWidth: 6)
                .blur(radius: 3)
            // Bordure nette
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(VelvetPalette.velvetBlue.opacity(0.4 + phase * 0.6), lineWidth: 3)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                phase = 1.0
            }
        }
    }
}

/// Bordure jaune animée sur les tuiles correspondant at la recherche en cours.
/// S'affiche en surbrillance tant que le champ de recherche est non vide.
struct SearchMatchBorder: View {
    let cornerRadius: CGFloat
    @State private var pulsing = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(VelvetPalette.nowPlayingYellow, lineWidth: 3)
            .opacity(pulsing ? 1.0 : 0.45)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}

// MARK: - Timeline compacte en Show Library

// MARK: - Bandeau "current song" (Show Library uniquement)

struct NowPlayingBanner: View {
    let appState: AppState

    private var track: AudioFile? { appState.currentlyLoadedTrack }
    private var engine: AudioEngine { appState.audioEngine }

    private static func timecode(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let m = Int(clamped) / 60
        let s = Int(clamped) % 60
        return String(format: "%02d:%02d", m, s)
    }

    var body: some View {
        guard let track else { return AnyView(EmptyView()) }
        return AnyView(content(track: track))
    }

    @ViewBuilder
    private func content(track: AudioFile) -> some View {
        VStack(spacing: 7) {
            // Ligne 1 : titre + temps écoulé + contrôles + temps restant
            HStack(spacing: 12) {
                // Indicateur d'état
                Image(systemName: engine.state == .playing
                      ? "waveform"
                      : (engine.state == .paused ? "pause.fill" : "stop.fill"))
                    .foregroundStyle(engine.state == .playing ? .green : .secondary)
                    .font(.system(size: 16, weight: .black))
                    .frame(width: 20)
                    .shadow(color: engine.state == .playing ? .green.opacity(0.45) : .clear, radius: 6, x: 0, y: 0)

                // Title
                Text(track.name ?? "—")
                    .font(.system(size: 15, weight: .black))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Spacer(minLength: 4)

                // Temps écoulé
                Text(Self.timecode(engine.effectivePosition))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.secondary)

                // Play / Pause
                Button {
                    switch engine.state {
                    case .playing:  appState.requestPause()
                    case .paused:   appState.requestResume()
                    case .stopped, .stopping:
                        appState.load(track: track)
                        appState.requestResume()
                    }
                } label: {
                    Image(systemName: engine.state == .playing ? "pause.fill" : "play.fill")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderless)
                .frame(width: 22, height: 22)

                // Stop
                Button {
                    appState.requestStop()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderless)
                .frame(width: 22, height: 22)
                .disabled(engine.state == .stopped)

                // Temps restant
                Text("−\(Self.timecode(engine.effectiveRemaining))")
                    .font(.system(size: 13, weight: .black).monospacedDigit())
                    .foregroundStyle(engine.state == .playing ? VelvetPalette.nowPlayingYellow : .secondary)
            }

            // Ligne 2 : timeline interactive
            ShowTimelineStrip(appState: appState, track: track)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(engine.state == .playing ? PerformanceChrome.activeGlow : Color.white.opacity(0.12), lineWidth: engine.state == .playing ? 1.4 : 0.7)
        }
        .shadow(color: engine.state == .playing ? PerformanceChrome.activeGlow : .black.opacity(0.22), radius: engine.state == .playing ? 14 : 8, x: 0, y: 5)
    }
}

struct ShowTimelineStrip: View {
    let appState: AppState
    let track: AudioFile

    /// Position visuelle pendant le drag (nil = position audio réelle).
    @State private var dragPosition: TimeInterval?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                WaveformTimelineView(
                    audioURL: appState.resolvedAudioURL(for: track),
                    duration: appState.audioEngine.effectiveDuration,
                    currentPosition: dragPosition ?? appState.audioEngine.effectivePosition,
                    memos: [],
                    displayMode: .waveformOnly,
                    showsModePicker: false,
                    palette: .standard
                )

                // Overlay transparent : drag déplace le curseur visuellement,
                // le seek musical est déclenché au relâchement seulement.
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        // minimumDistance: 0 → un simple clic positionne le curseur.
                        // L'edge-case isSeeking (fin naturelle pendant le seek) est
                        // géré dans AudioEngine.seekWithFade, donc c'est sûr.
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                // Mise at jour visuelle uniquement — pas d'audio
                                let duration = appState.audioEngine.effectiveDuration
                                guard geo.size.width > 0, duration > 0 else { return }
                                let fraction = max(0, min(1, value.location.x / geo.size.width))
                                dragPosition = fraction * duration
                            }
                            .onEnded { value in
                                defer { dragPosition = nil }
                                // Vérification de cohérence : le track visible doit
                                // toujours être le track chargé. Si l'utilisateur a
                                // lancé un autre song pendant le drag, on annule.
                                guard appState.currentlyLoadedTrack?.audioFileID
                                        == track.audioFileID else { return }
                                let duration = appState.audioEngine.effectiveDuration
                                guard geo.size.width > 0, duration > 0 else { return }
                                let fraction = max(0, min(1, value.location.x / geo.size.width)
                                )
                                appState.seek(track: track, to: fraction * duration)
                            }
                    )
            }
        }
        .frame(height: 44)
        .clipShape(RoundedRectangle(cornerRadius: PerformanceChrome.hudRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PerformanceChrome.hudRadius, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}

// MARK: - Luminosité globale MaestroDMX (CC14, Channel 16)

struct MaestroBrightnessPopover: View {
    let appState: AppState

    var body: some View {
        VStack(spacing: 14) {
            Text("MASTER BRIGHTNESS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            Text("\(appState.maestroBrightnessValue)")
                .font(.system(size: 32, weight: .medium).monospacedDigit())
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.1), value: appState.maestroBrightnessValue)

            Text("/ 127")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .offset(y: -8)

            BrightnessKnobView(value: appState.maestroBrightnessValue) { newValue in
                appState.sendMaestroBrightness(newValue)
            }
            .frame(width: 90, height: 90)

            HStack(spacing: 12) {
                Button {
                    appState.sendMaestroBrightness(appState.maestroBrightnessValue - 1)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("−1")

                Slider(
                    value: Binding(
                        get: { Double(appState.maestroBrightnessValue) },
                        set: { appState.sendMaestroBrightness(Int($0)) }
                    ),
                    in: 0...127, step: 1
                )
                .frame(width: 100)

                Button {
                    appState.sendMaestroBrightness(appState.maestroBrightnessValue + 1)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("+1")
            }

            HStack(spacing: 8) {
                ForEach([0, 32, 64, 96, 127], id: \.self) { preset in
                    Button {
                        appState.sendMaestroBrightness(preset)
                    } label: {
                        Text(preset == 0 ? "OFF" : preset == 127 ? "MAX" : "\(preset)")
                            .font(.system(size: 10, weight: .medium))
                            .frame(minWidth: 28)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(preset == appState.maestroBrightnessValue ? VelvetPalette.nowPlayingYellow : nil)
                }
            }

            if appState.maestroDestination == nil {
                Label("No MIDI Destination", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
    }
}

struct BrightnessKnobView: View {
    let value: Int
    let onValueChange: (Int) -> Void

    @State private var dragStart: (y: CGFloat, value: Int)?

    // En Y-down (SwiftUI Canvas) : 0°=3h, 90°=6h, 180°=9h, 270°=12h.
    // clockwise: false = sens horaire at l'écran (angles croissants).
    // minAngle=120° = 7h (bas-gauche), maxAngle=60° = 5h (bas-droite).
    // L'arc traverse le haut (9h→12h→3h), comme un vrai potentiomètre audio.
    private static let minAngle: Double = 120   // 7h — position min
    private static let maxAngle: Double = 60    // 5h — position max (via le haut, 300°)
    private static let travelDeg: Double = 300  // amplitude de l'arc

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let cy = size.height / 2
            let r = min(cx, cy) * 0.72
            let trackWidth: CGFloat = 6

            // Angle de l'indicateur : croît horaire de 120° (7h) at 420° (=5h, 300° plus loin)
            let indicatorDeg = Self.minAngle + Double(value) / 127.0 * Self.travelDeg
            let indicatorAngle = Angle.degrees(indicatorDeg)
            let minA = Angle.degrees(Self.minAngle)
            let maxA = Angle.degrees(Self.maxAngle)   // = 60°, l'arc clockwise:false va le long chemin

            // Piste grise complète : 7h → 5h sens horaire via le haut
            var trackPath = Path()
            trackPath.addArc(center: CGPoint(x: cx, y: cy),
                             radius: r, startAngle: minA, endAngle: maxA,
                             clockwise: false)
            ctx.stroke(trackPath, with: .color(.primary.opacity(0.12)),
                       style: StrokeStyle(lineWidth: trackWidth, lineCap: .round))

            // Remplissage jaune : de 7h jusqu'à l'indicateur (croît horaire)
            if value > 0 {
                var fillPath = Path()
                fillPath.addArc(center: CGPoint(x: cx, y: cy),
                                radius: r, startAngle: minA, endAngle: indicatorAngle,
                                clockwise: false)
                ctx.stroke(fillPath, with: .color(VelvetPalette.nowPlayingYellow),
                           style: StrokeStyle(lineWidth: trackWidth, lineCap: .round))
            }

            let innerR = r * 0.58
            let dotX = cx + innerR * cos(indicatorAngle.radians)
            let dotY = cy + innerR * sin(indicatorAngle.radians)
            ctx.fill(Path(ellipseIn: CGRect(x: dotX - 3, y: dotY - 3, width: 6, height: 6)),
                     with: .color(.primary.opacity(0.65)))
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    if dragStart == nil { dragStart = (drag.startLocation.y, value) }
                    if let start = dragStart {
                        let delta = Int((start.y - drag.location.y) * 0.7)
                        onValueChange(max(0, min(127, start.value + delta)))
                    }
                }
                .onEnded { _ in dragStart = nil }
        )
        .help("Drag up/down to adjust brightness")
    }
}

// MARK: - Panneau MIDI manuel MaestroDMX

struct MaestroManualPopover: View {
    let appState: AppState
    @State private var selectedEventID: MidiEvent.ID?

    private var events: [MidiEvent] { appState.maestroMidiEvents() }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "light.cylindrical.ceiling.fill")
                    .foregroundStyle(VelvetPalette.gold)
                Text("MIDI Manuel · MaestroDMX")
                    .font(.callout.bold())
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)
                    Text("LIVE")
                        .font(.caption2.bold())
                        .foregroundStyle(.red)
                }
            }
            Divider()
            if events.isEmpty {
                Text("No MaestroDMX events found in the database.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(events) { event in
                            MaestroEventRow(
                                event: event,
                                messages: appState.midiMessages(for: event),
                                isActive: appState.lastDispatchedMaestroEventID == event.midiEventID,
                                isSelected: selectedEventID == event.midiEventID
                            ) {
                                selectedEventID = event.midiEventID
                                appState.dispatch(event: event)
                            }
                        }
                    }
                }
            }
            if let dest = appState.maestroDestination {
                Text("→ \(dest.displayName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("⚠ No MIDI destination selected")
                    .font(.caption2)
                    .foregroundStyle(VSColor.warning)
            }
        }
    }
}

struct MaestroEventRow: View {
    let event: MidiEvent
    let messages: [MidiMessage]
    /// Dernière scène réellement envoyée (mémo auto, stop cue ou manuel).
    var isActive: Bool = false
    /// Clic dans la session courante du popover — highlight éphémère.
    let isSelected: Bool
    let onTap: () -> Void

    private var accentColor: Color { VelvetPalette.nowPlayingYellow }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.name ?? "Event \(event.midiEventID)")
                        .font(.caption.bold())
                        .lineLimit(1)
                        .foregroundStyle(isActive ? accentColor : .primary)
                    if let cat = event.category {
                        Text(cat)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isActive {
                    Text("Current")
                        .font(.caption2.bold())
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(accentColor.opacity(0.15), in: Capsule())
                } else {
                    Text("\(messages.count) msg")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(accentColor.opacity(0.6), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var rowBackground: Color {
        if isActive  { return accentColor.opacity(0.08) }
        if isSelected { return VelvetPalette.gold.opacity(0.22) }
        return Color.primary.opacity(0.04)
    }
}

// MARK: - Color individuelle d'un song

struct TrackColorSheet: View {
    let track: AudioFile
    let appState: AppState
    /// Contexte show optionnel. Si présent, la couleur est locale au show.
    var showSet: ShowSet? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var color: Color

    init(track: AudioFile, appState: AppState, showSet: ShowSet? = nil) {
        self.track = track
        self.appState = appState
        self.showSet = showSet
        // Priorité : couleur locale au show → couleur globale
        if let set = showSet, let c = appState.showSongColor(forAudioFileID: track.audioFileID, in: set) {
            _color = State(initialValue: c)
        } else {
            _color = State(initialValue: appState.color(for: track))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Song Color", systemImage: "paintpalette")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name ?? "Untitled")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if showSet != nil {
                    Text("Color applies to this show only")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 8)

            // Aperçu de la couleur sélectionnée
            RoundedRectangle(cornerRadius: VSRadius.medium)
                .fill(color)
                .frame(height: 52)
                .overlay {
                    RoundedRectangle(cornerRadius: VSRadius.medium)
                        .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
                }
                .padding(.top, 20)

            // Palette 9 couleurs — 2 rangées
            TilePalettePicker(selection: $color)
                .padding(.top, 20)

            HStack {
                Button("Reset") {
                    if let set = showSet {
                        appState.resetShowSongColor(forAudioFileID: track.audioFileID, in: set)
                    } else {
                        appState.resetTrackColor(for: track)
                    }
                    dismiss()
                }
                .foregroundStyle(VSColor.warning)
                .disabled(!hasCustomColor)

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Save") {
                    if let set = showSet {
                        appState.setShowSongColor(color, forAudioFileID: track.audioFileID, in: set)
                    } else {
                        appState.setTrackColor(color, for: track)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 24)
        }
        .padding(28)
        .frame(minWidth: 440)
    }

    private var hasCustomColor: Bool {
        if let set = showSet {
            return appState.hasShowSongColor(forAudioFileID: track.audioFileID, in: set)
        }
        return appState.hasCustomTrackColor(for: track)
    }
}

// MARK: - Transition Pads

/// Panneau DJ de sélection d'effet de transition. Présenté en `.sheet`.
/// 3 pads : FADE, FILTER, SLOW FADE.
/// Navigation clavier : ←/→ cyclent les pads, ↩ confirme, ⎋ annule.
struct TransitionPadPanel: View {
    @Bindable var appState: AppState
    let incomingTitle: String
    let currentTitle: String
    let onConfirm: (TransitionEffect) -> Void
    let onCancel: () -> Void

    @State private var selected: TransitionEffect = .fade
    @Environment(\.dismiss) private var dismiss

    private let available: [TransitionEffect] = TransitionEffect.allCases.filter { $0.isAvailable }

    var body: some View {
        VStack(spacing: 0) {
            // ── Contexte ─────────────────────────────────────────────────────
            VStack(spacing: 3) {
                Text("Current: \"\(currentTitle)\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Next: \"\(incomingTitle)\"")
                    .font(.subheadline.bold())
            }
            .multilineTextAlignment(.center)
            .padding(.top, 24)
            .padding(.bottom, 20)

            // ── Pads ─────────────────────────────────────────────────────────
            HStack(spacing: 10) {
                ForEach(TransitionEffect.allCases.filter { $0.isAvailable }, id: \.self) { effect in
                    TransitionPad(effect: effect, isSelected: selected == effect) {
                        selected = effect
                    }
                }
            }
            .padding(.horizontal, 20)

            // ── Boutons bas ──────────────────────────────────────────────────
            HStack {
                Button("Cancel") { onCancel(); dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button("Start") {
                    appState.lastTransitionEffect = selected
                    onConfirm(selected)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 22)
        }
        .frame(width: 460)
        .onAppear { selected = appState.lastTransitionEffect.isAvailable ? appState.lastTransitionEffect : .fade }
        .onKeyPress(.leftArrow)  { cycleEffect(by: -1); return .handled }
        .onKeyPress(.rightArrow) { cycleEffect(by:  1); return .handled }
    }

    private func cycleEffect(by delta: Int) {
        guard !available.isEmpty else { return }
        let idx = available.firstIndex(of: selected) ?? 0
        selected = available[(idx + delta + available.count) % available.count]
    }
}

/// Un pad individuel du panneau Transition Pads.
struct TransitionPad: View {
    let effect: TransitionEffect
    let isSelected: Bool
    let onTap: () -> Void

    private var accentColor: Color { VelvetPalette.nowPlayingYellow }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 7) {
                Image(systemName: effect.icon)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                Text(effect.rawValue)
                    .font(.caption.bold())
                    .tracking(0.8)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(width: 76, height: 76)
            .background(padFill, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(padStroke, lineWidth: isSelected ? 2 : 1)
            }
            .foregroundStyle(padForeground)
        }
        .buttonStyle(.plain)
    }

    private var padFill: Color {
        isSelected ? accentColor.opacity(0.15) : Color.white.opacity(0.05)
    }

    private var padStroke: Color {
        isSelected ? accentColor : Color.white.opacity(0.18)
    }

    private var padForeground: Color {
        isSelected ? accentColor : .primary
    }
}

struct PendingQueuePlaybackRequest: Identifiable {
    let id = UUID()
    let item: ConcertQueueItem
    let track: AudioFile
    let element: SetElement?
    let currentTitle: String
}

struct QueueStagePanel: View {
    @Bindable var appState: AppState
    let set: ShowSet
    let maxVisibleRows: Int?
    var showsCurrentTrack: Bool = true
    @State private var pendingReplacement: PendingQueuePlaybackRequest?
    @State private var isManuallyExpanded = false
    @State private var isManuallyCollapsed = false

    private var queue: [ConcertQueueItem] { appState.queueItems(for: set) }
    private var visibleQueue: [ConcertQueueItem] {
        if let maxVisibleRows { return Array(queue.prefix(maxVisibleRows)) }
        return queue
    }

    private var isEmbeddedPanel: Bool { maxVisibleRows != nil }

    private var isExpanded: Bool {
        guard isEmbeddedPanel else { return true }
        if isManuallyExpanded { return true }
        if isManuallyCollapsed { return false }
        return queue.count >= 3
    }

    private var compactVisibleQueue: [ConcertQueueItem] {
        Array(queue.prefix(2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if showsCurrentTrack { currentTrackLine }
            if !queue.isEmpty {
                if isExpanded {
                    queueRows
                        .frame(minHeight: minListHeight, idealHeight: idealListHeight, maxHeight: maxListHeight)
                    if let maxVisibleRows, queue.count > maxVisibleRows {
                        Text("+ \(queue.count - maxVisibleRows) more in floating window")
                            .font(.caption.bold())
                            .foregroundStyle(QueuePalette.accentStrong)
                    }
                } else {
                    compactQueueRows
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: PerformanceChrome.hudRadius, style: .continuous))
        .background(
            LinearGradient(
                colors: [QueuePalette.accent.opacity(0.19), Color.white.opacity(0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: PerformanceChrome.hudRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: PerformanceChrome.hudRadius, style: .continuous)
                .stroke(QueuePalette.border, lineWidth: queue.isEmpty ? 1 : 1.4)
        }
        .shadow(color: QueuePalette.accent.opacity(queue.isEmpty ? 0.08 : 0.20), radius: 16, x: 0, y: 8)
        .animation(.snappy(duration: 0.22), value: queue.count)
        .animation(.snappy(duration: 0.22), value: isExpanded)
        .onChange(of: queue.count) { _, newCount in
            if newCount == 0 {
                isManuallyExpanded = false
                isManuallyCollapsed = false
            }
        }
        .sheet(item: $pendingReplacement) { pending in
            TransitionPadPanel(
                appState: appState,
                incomingTitle: pending.track.name ?? "Untitled",
                currentTitle: pending.currentTitle
            ) { effect in
                appState.removeQueueItem(pending.item, from: set)
                appState.startReplacement(track: pending.track, set: set, element: pending.element, effect: effect)
                pendingReplacement = nil
            } onCancel: {
                pendingReplacement = nil
            }
        }
    }

    private var compactQueueRows: some View {
        VStack(spacing: 5) {
            ForEach(Array(compactVisibleQueue.enumerated()), id: \.element.id) { index, item in
                compactQueueRow(item, rank: index + 1)
            }
            if queue.count > compactVisibleQueue.count {
                Text("+ \(queue.count - compactVisibleQueue.count) more")
                    .font(.caption.bold())
                    .foregroundStyle(QueuePalette.accentStrong)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 1)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func compactQueueRow(_ item: ConcertQueueItem, rank: Int) -> some View {
        let track = appState.audioFilesByID[item.audioFileID]
        return Button {
            requestPlay(item)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: appState.isCurrentTrack(track) ? "stop.fill" : "play.fill")
                    .font(.caption.bold())
                    .foregroundStyle(QueuePalette.accentStrong)
                    .frame(width: 16)
                Text(track?.name ?? "Song not found")
                    .font(.callout.bold())
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                Text(queueModeStatus(for: item, rank: rank))
                    .font(.caption2.bold())
                    .foregroundStyle(item.playbackMode == .automatic ? VSColor.playActive : VSColor.warning)
                    .lineLimit(1)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(QueuePalette.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(QueuePalette.accent.opacity(0.24), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var queueRows: some View {
        if maxVisibleRows == nil {
            List {
                ForEach(Array(visibleQueue.enumerated()), id: \.element.id) { index, item in
                    queueRow(item, rank: index + 1)
                }
                .onMove { source, destination in
                    appState.moveQueueItem(in: set, from: source, to: destination)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        } else {
            VStack(spacing: 7) {
                ForEach(Array(visibleQueue.enumerated()), id: \.element.id) { index, item in
                    queueRow(item, rank: index + 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func queueRow(_ item: ConcertQueueItem, rank: Int) -> some View {
        QueueStageRow(
            appState: appState,
            set: set,
            item: item,
            rank: rank,
            statusText: queueModeStatus(for: item, rank: rank),
            requestPlay: { requestPlay(item) }
        )
    }

    private func queueModeStatus(for item: ConcertQueueItem, rank: Int) -> String {
        if rank == 1 {
            return item.playbackMode == .automatic
                ? "AUTO · starts at the end"
                : "STOP · press Play"
        }
        return item.playbackMode == .automatic ? "AUTO" : "STOP"
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("Queue (\(queue.count))", systemImage: "bolt.fill")
                .font(queue.isEmpty ? .caption.bold() : .headline.bold())
                .foregroundStyle(queue.isEmpty ? .secondary : QueuePalette.accentStrong)
            Spacer()
            if !queue.isEmpty {
                Text(isExpanded ? (appState.isSafePlayEnabled ? "Double-click row" : "Click row") : "Compact")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                if isEmbeddedPanel {
                    Button {
                        toggleExpandedState()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.borderless)
                    .help(isExpanded ? "Collapse Queue" : "Expand Queue")
                }
            }
        }
    }

    private var currentTrackLine: some View {
        HStack(spacing: 6) {
            Text("Now Playing")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(appState.currentlyLoadedTrack?.name ?? "No song")
                .font(.callout.bold())
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var minListHeight: CGFloat { queue.isEmpty ? 28 : 70 }
    private var idealListHeight: CGFloat { CGFloat(max(1, visibleQueue.count)) * 56 + 8 }
    private var maxListHeight: CGFloat { maxVisibleRows == nil ? 520 : 190 }

    private func toggleExpandedState() {
        if isExpanded {
            isManuallyCollapsed = true
            isManuallyExpanded = false
        } else {
            isManuallyExpanded = true
            isManuallyCollapsed = false
        }
    }

    private func requestPlay(_ item: ConcertQueueItem) {
        guard let context = appState.queuePlaybackContext(for: item, in: set) else { return }
        if appState.isCurrentTrack(context.track) {
            appState.removeQueueItem(item, from: set)
            appState.togglePlayback(track: context.track, set: set, element: context.element)
            return
        }
        if appState.shouldConfirmReplacement(for: context.track) {
            let currentTitle = appState.currentlyLoadedTrack?.name ?? "current song"
            pendingReplacement = PendingQueuePlaybackRequest(
                item: item,
                track: context.track,
                element: context.element,
                currentTitle: currentTitle
            )
            return
        }
        appState.playQueueItem(item, in: set)
    }
}

struct QueueStageRow: View {
    let appState: AppState
    let set: ShowSet
    let item: ConcertQueueItem
    let rank: Int
    let statusText: String
    let requestPlay: () -> Void

    private var track: AudioFile? { appState.audioFilesByID[item.audioFileID] }
    private var title: String { track?.name ?? "Song not found" }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(QueuePalette.accentStrong)
                .frame(width: 28, alignment: .trailing)
            Button(action: requestPlay) {
                Image(systemName: appState.isCurrentTrack(track) ? "stop.fill" : "play.fill")
                    .font(.title3.bold())
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(QueuePalette.accentStrong)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let track {
                        Circle()
                            .fill(appState.color(for: track))
                            .frame(width: 9, height: 9)
                    }
                    Text(title)
                        .font(.headline.bold())
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(statusText)
                    .font(.caption.bold())
                    .foregroundStyle(item.playbackMode == .automatic ? VSColor.playActive : VSColor.warning)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(2)
            Picker("Mode", selection: playbackModeBinding) {
                Text("Auto").tag(QueuePlaybackMode.automatic)
                Text("Stop").tag(QueuePlaybackMode.manual)
            }
            .pickerStyle(.segmented)
            .frame(width: 126)
            .fixedSize(horizontal: true, vertical: false)
            Button(role: .destructive) {
                appState.removeQueueItem(item, from: set)
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .font(.title3)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(QueuePalette.accent.opacity(0.16), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if appState.isSafePlayEnabled { requestPlay() }
        }
        .onTapGesture {
            if !appState.isSafePlayEnabled { requestPlay() }
        }
    }

    private var playbackModeBinding: Binding<QueuePlaybackMode> {
        Binding(
            get: { item.playbackMode },
            set: { appState.setQueuePlaybackMode($0, for: item, in: set) }
        )
    }
}

struct QueueFloatingView: View {
    static let windowID = "queue-floating"
    @Environment(AppState.self) private var appState

    private var selectedSet: ShowSet? {
        guard let setID = appState.selectedSetID else { return nil }
        return appState.sets.first { $0.setID == setID }
    }

    private var selectedQueueCount: Int {
        guard let set = selectedSet else { return 0 }
        return appState.queueItems(for: set).count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Mini header drag zone + titre
            HStack {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(selectedSet.map { "Queue — \($0.name ?? "Show")" } ?? "Floating Queue")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)

            Divider().opacity(0.4)

            if let set = selectedSet {
                QueueStagePanel(appState: appState, set: set, maxVisibleRows: nil)
                    .padding(10)
            } else {
                ContentUnavailableView(
                    "No show selected",
                    systemImage: "arrow.up.circle.fill",
                    description: Text("Select a show in the main window.")
                )
                .padding()
            }
        }
        .frame(minWidth: 260, minHeight: 200)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
        .background {
            QueueWindowAccessor { window in
                QueueFloatingWindowController.configure(window)
            }
        }
        .onAppear {
            appState.isFloatingQueueVisible = true
            if selectedQueueCount == 0 {
                QueueFloatingWindowController.hideBecauseQueueIsEmpty()
            }
        }
        .onDisappear {
            appState.isFloatingQueueVisible = false
        }
        .onChange(of: selectedQueueCount) { _, newCount in
            if newCount == 0 {
                QueueFloatingWindowController.hideBecauseQueueIsEmpty()
            }
        }
    }
}

struct RemainingCartridgesPanel: View {
    let appState: AppState
    let set: ShowSet
    let songs: [Song]

    private var counts: [(genre: ConcertGenre, count: Int)] {
        let remaining = songs.filter { !appState.isPlayed($0, in: set) }
        return ConcertGenre.allCases
            .filter { $0 != .all }
            .map { genre in
                (genre, remaining.filter { appState.concertGenre(for: $0) == genre }.count)
            }
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
    }

    private var maxCount: Int {
        max(1, counts.map(\.count).max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("REMAINING SLOTS", systemImage: "chart.bar.fill")
                .font(.caption.bold())

            if counts.isEmpty {
                Text("No styles remaining in this filter.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                VStack(spacing: 4) {
                    ForEach(counts.prefix(5), id: \.genre) { row in
                        cartridgeRow(row.genre, count: row.count)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    private func cartridgeRow(_ genre: ConcertGenre, count: Int) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(appState.color(for: genre))
                .frame(width: 9, height: 9)
            Text(genre.label.uppercased())
                .font(.caption.bold())
                .frame(width: 72, alignment: .leading)
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 3)
                    .fill(appState.color(for: genre).opacity(0.85))
                    .frame(width: max(8, proxy.size.width * CGFloat(count) / CGFloat(maxCount)))
            }
            .frame(height: 10)
            Text("\(count)")
                .font(.caption.bold().monospacedDigit())
                .frame(width: 24, alignment: .trailing)
        }
    }
}

struct ConcertStatsPanel: View {
    let appState: AppState

    private var stats: [TrackPlayStat] { appState.playStats(limit: 5) }

    private var recentConcerts: [ConcertHistoryEntry] {
        appState.concertHistory
            .filter { !$0.playedTracks.isEmpty }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(3)
            .map { $0 }
    }

    private var currentRisk: TrackRiskLevel? {
        appState.currentlyLoadedTrack.map { appState.riskLevel(for: $0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Label("HISTORY / RISK", systemImage: "clock.arrow.circlepath")
                    .font(.caption.bold())

                if let track = appState.currentlyLoadedTrack, let currentRisk {
                    HStack(spacing: 6) {
                        RiskBadge(risk: currentRisk)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(track.name ?? "Current Song")
                                .font(.caption.bold())
                                .lineLimit(1)
                            Text(lastPlayedSubtitle(for: track, risk: currentRisk))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Divider()
                recentConcertsSection
                Divider()
                topTracksSection
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var recentConcertsSection: some View {
        if recentConcerts.isEmpty {
            Text("History is empty — it will fill up as you perform.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Recent Shows")
                .font(.caption.bold())
            ForEach(recentConcerts) { concert in
                VStack(alignment: .leading, spacing: 4) {
                    Text("Show on \(Self.dateFormatter.string(from: concert.startedAt)) — \(concert.setName)")
                        .font(.caption.bold())
                        .lineLimit(1)
                    ForEach(Array(orderedTracks(in: concert).prefix(6).enumerated()), id: \.element.id) { index, played in
                        HStack(spacing: 5) {
                            Text("\(displayPosition(played, fallback: index + 1)).")
                                .font(.caption2.bold().monospacedDigit())
                                .frame(width: 20, alignment: .trailing)
                            Text(played.title)
                                .font(.caption2)
                                .lineLimit(1)
                            Spacer()
                            Text(Self.timeFormatter.string(from: played.playedAt))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var topTracksSection: some View {
        if !stats.isEmpty {
            Text("Most played songs")
                .font(.caption.bold())
            ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
                HStack(spacing: 5) {
                    Text("\(index + 1)")
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(stat.title)
                            .font(.caption.bold())
                            .lineLimit(1)
                        if let last = stat.lastPlayedAt {
                            Text("Last: \(Self.dateFormatter.string(from: last))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text("\(stat.count)")
                        .font(.caption.bold().monospacedDigit())
                }
            }
        }
    }

    private func orderedTracks(in concert: ConcertHistoryEntry) -> [ConcertPlayedTrack] {
        concert.playedTracks.sorted {
            let lhs = $0.playPosition == 0 ? Int.max : $0.playPosition
            let rhs = $1.playPosition == 0 ? Int.max : $1.playPosition
            if lhs != rhs { return lhs < rhs }
            return $0.playedAt < $1.playedAt
        }
    }

    private func displayPosition(_ played: ConcertPlayedTrack, fallback: Int) -> Int {
        played.playPosition == 0 ? fallback : played.playPosition
    }

    private func lastPlayedSubtitle(for track: AudioFile, risk: TrackRiskLevel) -> String {
        guard let lastPlayed = appState.lastPlayedDate(for: track) else { return risk.detail }
        return "\(risk.detail) • \(Self.dateFormatter.string(from: lastPlayed))"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

/// Une demande de remplacement en attente de confirmation. Stocke la `Song`
/// cible et le titre du song en cours for afficher un message clair.
struct PendingReplacementRequest: Identifiable {
    let id = UUID()
    let song: Song
    let currentTitle: String
}

struct SetSongsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var appState: AppState
    let set: ShowSet
    let songs: [Song]
    /// Bouton focus concert — collapse/restore sidebar Shows + Quick Library.
    /// Nil si le contexte d'appel ne fournit pas cette action (ex. preview).
    var isFocusMode: Bool = false
    var toggleFocusMode: (() -> Void)? = nil
    @State private var selectedSongID: Song.ID?
    @State private var pendingReplacement: PendingReplacementRequest?
    @State private var draggingShowSongID: Song.ID?
    @State private var dragPreviewLocation: CGPoint?
    @State private var proposedDropIndex: Int?
    @State private var setlistTileFrames: [Song.ID: CGRect] = [:]
    @State private var editingColorSong: Song?
    @State private var isShowingMaestroPanel = false
    @State private var isShowingBrightnessPopover = false
    @State private var showRemainingCount = false
    @State private var trashingVelvetTrack: VelvetTrack?
    @State private var confirmRemoveFromConcert: Song?

    /// Texte saisi dans la barre de recherche instantanée.
    /// Vide = pas de filtre actif. Remis at "" dès qu'un song est lancé.
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool

    fileprivate static let showSongDragPrefix = "velvet-show-song:"
    private static let setlistCoordinateSpace = "setlist-wall"

    private var genreFilteredSongs: [Song] {
        let base = songs
        return appState.selectedConcertGenre == .all
            ? base
            : base.filter { appState.concertGenre(for: $0) == appState.selectedConcertGenre }
    }

    /// Sous-ensemble de `genreFilteredSongs` après application du filtre
    /// de recherche textuelle. Si `searchText` est vide, retourne tout.
    private var searchActiveSongs: [Song] {
        guard !searchText.isEmpty else { return genreFilteredSongs }
        let q = searchText
        return genreFilteredSongs.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    private var remainingSongs: [Song] {
        searchActiveSongs.filter { !appState.isPlayed($0, in: set) }
    }

    private var playedSongs: [Song] {
        searchActiveSongs.filter { appState.isPlayed($0, in: set) }
    }

    /// Vide le champ de recherche et retire le filtre.
    private func clearSearch() {
        guard !searchText.isEmpty else { return }
        searchText = ""
        isSearchFocused = false
    }

    private var priorityNextItem: ConcertQueueItem? {
        appState.queueItems(for: set).first
    }

    private var priorityNextSongID: Song.ID? {
        priorityNextItem?.setElementID
    }

    private var playedCount: Int {
        appState.playedCount(in: set, songs: songs)
    }

    private var remainingDuration: TimeInterval {
        songs
            .filter { !appState.isPlayed($0, in: set) }
            .compactMap { $0.audio?.lengthSecs }
            .reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // En-tête ultra compact : tout sur une seule ligne pour
            // récupérer un maximum d'espace vertical for la grille.
            HStack(spacing: 10) {
                // ◀/▶ Focus concert — collapse sidebar Shows + Quick Library.
                if let toggleFocusMode {
                    Button(action: toggleFocusMode) {
                        Image(systemName: isFocusMode
                              ? "arrowtriangle.right.fill"
                              : "arrowtriangle.left.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(VelvetPalette.gold)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isFocusMode
                          ? "Exit focus mode (show all columns)"
                          : "Focus mode (hide Shows and Quick Songs)")
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                }

                Text(set.name ?? "Untitled Show")
                    .font(.system(size: 17, weight: .black))
                    .lineLimit(1)

                // Compteur toujours visible — clic for permuter Played ↔ Restants.
                let remainingCount = songs.count - playedCount
                Button {
                    showRemainingCount.toggle()
                } label: {
                    Text(showRemainingCount
                         ? "Remaining \(remainingCount)/\(songs.count)"
                         : "Played \(playedCount)/\(songs.count)")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(playedCount > 0 ? .primary : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.065), in: Capsule())
                }
                .buttonStyle(.plain)
                .help(showRemainingCount ? "Show played songs" : "Show remaining songs")
                Text(Self.compactDuration(remainingDuration))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.secondary)

                // Recherche intégrée dans la barre — visible hors mode édition.
                if !appState.isShowEditMode {
                    HStack(spacing: 5) {
                        Button {
                            appState.isQuickLibraryVisible.toggle()
                        } label: {
                            Image(systemName: appState.isQuickLibraryVisible
                                  ? "books.vertical.fill"
                                  : "books.vertical")
                                .font(.system(size: 13))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(appState.isQuickLibraryVisible ? VSColor.interactive : nil)
                        .keyboardShortcut("b", modifiers: .command)
                        .help(appState.isQuickLibraryVisible
                              ? "Close Quick Songs (⌘B)"
                              : "Open Songs to add a song (⌘B)")

                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(searchText.isEmpty ? Color.secondary : VelvetPalette.nowPlayingYellow)
                            .font(.system(size: 13))
                        TextField("Search...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .frame(minWidth: 60, maxWidth: 100)
                            .focused($isSearchFocused)
                            .onSubmit {
                                let first = remainingSongs.first ?? playedSongs.first
                                if let song = first { requestPlay(song) }
                            }
                            .onKeyPress(.escape) {
                                clearSearch()
                                return .handled
                            }
                        if !searchText.isEmpty {
                            Button { clearSearch() } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Clear search (ESC)")
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(searchText.isEmpty ? 0.10 : 0.24), lineWidth: 1)
                    }
                    .background {
                        Button("") { isSearchFocused = true }
                            .keyboardShortcut("f", modifiers: .command)
                            .opacity(0)
                            .frame(width: 0, height: 0)
                    }
                }

                Spacer()

                // ⏮ ▶/⏸ ⏹ — transport inline dans l'en-tête du show.
                MiniTransportBar(appState: appState)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)

                // − 0 dB + VUMeter. ViewThatFits : si l'en-tête manque de
                // largeur (Quick Library ouverte, fenêtre étroite), bascule
                // sur la variante sans VU mètre au lieu de déborder sur les
                // colonnes voisines.
                ViewThatFits(in: .horizontal) {
                    LiveVolumeControl(appState: appState)
                    LiveVolumeControl(appState: appState, showsVUMeter: false)
                    // Dernier palier : fenêtre vraiment étroite, le contrôle
                    // de volume disparaît plutôt que de déborder.
                    Color.clear.frame(width: 0, height: 0)
                }

                // Filtre de genre — masqué en mode concert (rarement utilisé en
                // prestation ; la recherche instantanée remplit ce besoin).
                // Réactiver : remplacer `if false` par `if true` ou supprimer la condition.
                if false {
                    Picker("Genre", selection: $appState.selectedConcertGenre) {
                        ForEach(ConcertGenre.allCases) { genre in
                            Text(genre.label).tag(genre)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 110)
                }

                // Toggle "Mode Répétition" — icône seule, rouge vif quand actif.
                // État impossible at manquer : fond rouge + icône fill vs outline.
                Toggle(isOn: $appState.isRehearsalMode) {
                    Image(systemName: appState.isRehearsalMode
                          ? "repeat.circle.fill"
                          : "repeat.circle")
                    .foregroundStyle(appState.isRehearsalMode ? .red : .primary)
                }
                .toggleStyle(.button)
                .controlSize(.large)
                .tint(.red)
                .help(appState.isRehearsalMode
                      ? "Repeat Mode active — played songs are not counted. Disable before your show."
                      : "Enable Repeat Mode — played songs stay in Remaining")

                Button(role: .destructive) {
                    appState.resetProgress(for: set)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(playedCount == 0)
                .help("Reset show")

                Button {
                    isShowingBrightnessPopover.toggle()
                } label: {
                    Image(systemName: "sun.max.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(isShowingBrightnessPopover ? VelvetPalette.nowPlayingYellow : nil)
                .help("MaestroDMX master brightness")
                .popover(isPresented: $isShowingBrightnessPopover, arrowEdge: .bottom) {
                    MaestroBrightnessPopover(appState: appState)
                }

                Button {
                    isShowingMaestroPanel.toggle()
                } label: {
                    Image(systemName: "lightbulb.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.red)
                .help("Lights / Maestro Scenes")
                .popover(isPresented: $isShowingMaestroPanel, arrowEdge: .bottom) {
                    MaestroManualPopover(appState: appState)
                        .frame(width: 320, height: 380)
                        .padding(10)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: PerformanceChrome.hudRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PerformanceChrome.hudRadius, style: .continuous)
                    .stroke(PerformanceChrome.panelStroke, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.20), radius: 14, x: 0, y: 7)
            .padding(.horizontal, 10)
            .padding(.top, 8)

            CompactConcertStrip(appState: appState, set: set, songs: songs)

            // ── Bannière Mode Répétition ──────────────────────────────────
            // Orange vif + texte blanc — impossible at manquer.
            // Disparaît dès que le mode est désactivé.
            if appState.isRehearsalMode {
                HStack(spacing: 8) {
                    Image(systemName: "repeat.circle.fill")
                        .font(.system(size: 13, weight: .black))
                    Text("REPEAT MODE ACTIVE")
                        .font(.system(size: 13, weight: .black))
                        .tracking(1.2)
                    Spacer()
                    Text("Played songs stay in Remaining")
                        .font(.system(size: 11, weight: .semibold))
                        .opacity(0.85)
                    Button {
                        appState.isRehearsalMode = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .opacity(0.85)
                    }
                    .buttonStyle(.borderless)
                    .help("Disable Repeat Mode")
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.88))
            }

            // ── Timeline waveform compacte ────────────────────────────────
            // Visible uniquement quand un song est chargé.
            // Réutilise ShowTimelineStrip (waveform + curseur seek).
            // Aucun transport : le transport principal reste dans CompactConcertStrip.
            if let track = appState.currentlyLoadedTrack {
                ShowTimelineStrip(appState: appState, track: track)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }


            Color.clear
                .frame(height: 3)

            // En mode édition on remplace la grille concert par une liste
            // éditable : drag for réordonner, bouton trash for supprimer.
            // En mode normal on garde la grille `setlistWall` optimisée
            // for la lecture scène.
            if appState.isShowEditMode {
                editableShowList
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .onDrop(of: [.plainText], isTargeted: nil) { providers in
                        handleTrackDrop(providers)
                        return true
                    }
            } else {
                GeometryReader { proxy in
                    setlistWall(size: proxy.size)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .onDrop(of: [.plainText], isTargeted: nil) { providers in
                            handleSetlistBackgroundDrop(providers)
                            return true
                        }
                }
            }
        }
        // Transition Pads : déclenchés par le double-clic sur une tuile setlist
        // quand un autre song est déjà en lecture (mode sécurisé activé).
        .sheet(item: $pendingReplacement) { pending in
            TransitionPadPanel(
                appState: appState,
                incomingTitle: pending.song.title,
                currentTitle: pending.currentTitle
            ) { effect in
                if let audio = pending.song.audio {
                    appState.startReplacement(
                        track: audio,
                        set: set,
                        element: pending.song.element,
                        effect: effect
                    )
                }
                pendingReplacement = nil
            } onCancel: {
                pendingReplacement = nil
            }
        }
    }

    /// Déclenché par un double-clic sur une tuile setlist : sélection
    /// immédiate, puis lecture ou confirmation selon l'état courant.
    /// Vide la recherche instantanément — la recherche est un outil de
    /// localisation temporaire, pas d'état permanent.
    private func requestPlay(_ song: Song) {
        clearSearch()
        guard let audio = song.audio else { return }
        selectedSongID = song.id
        appState.selectShowSong(song, in: set)

        // Si on a double-cliqué sur le song qui joue déjà, on tombe
        // sur le toggle normal (= stop avec fade-out défini par AudioEngine).
        if appState.isCurrentTrack(audio) {
            appState.togglePlayback(track: audio, set: set, element: song.element)
            return
        }

        if appState.shouldConfirmReplacement(for: song) {
            let currentTitle = appState.currentlyLoadedTrack?.name ?? "current song"
            pendingReplacement = PendingReplacementRequest(song: song, currentTitle: currentTitle)
            return
        }

        appState.togglePlayback(track: audio, set: set, element: song.element)
    }

    private func showMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 110, alignment: .trailing)
    }

    // MARK: - Internal deprecated edit mode

    // TODO: Retain this temporarily for safety while the main UI uses direct
    // setlist drag/drop plus the sidebar "Reset Show Order" action.
    // This screen is intentionally hidden from the main toolbar.
    /// Grille multi-colonnes éditable : drag/drop for réordonner, bouton trash
    /// for supprimer. Appelle les mêmes méthodes AppState que setlistWall —
    /// aucune logique de réorganisation modifiée.
    private var editableShowList: some View {
        let orderedSongs = genreFilteredSongs

        return GeometryReader { proxy in
            let columns = editGridColumns(width: proxy.size.width)
            let gridCols = Array(repeating: GridItem(.flexible(), spacing: 6), count: columns)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // En-tête
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.pencil")
                        Text("Edit mode · drag to reorder · trash to delete")
                    }
                    .font(.caption.bold())
                    .foregroundStyle(VSColor.warning)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                    if orderedSongs.isEmpty {
                        Text("No songs in this show (possibly all filtered or deleted).")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(12)
                    } else {
                        LazyVGrid(columns: gridCols, spacing: 6) {
                            ForEach(Array(orderedSongs.enumerated()), id: \.element.id) { index, song in
                                editCard(song, index: index + 1, total: orderedSongs.count)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                    }

                    // Footer : annuler l'ordre personnalisé
                    if appState.customOrderBySetID[set.setID] != nil {
                        HStack {
                            Spacer()
                            Button {
                                appState.resetCustomOrder(for: set)
                            } label: {
                                Label("Undo Velvet edits on this show", systemImage: "arrow.uturn.backward")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private func editGridColumns(width: CGFloat) -> Int {
        if width > 800 { return 4 }
        if width > 540 { return 3 }
        return 2
    }

    private func editCardDragPreview(_ song: Song) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(appState.color(for: song, inSet: set))
                .frame(width: 8, height: 8)
            Text(song.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .frame(width: 180, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: PerformanceChrome.tileRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PerformanceChrome.tileRadius, style: .continuous)
                .stroke(appState.color(for: song, inSet: set).opacity(0.75), lineWidth: 1)
        }
        .scaleEffect(1.02)
        .opacity(0.84)
        .shadow(color: .black.opacity(0.34), radius: 14, x: 0, y: 8)
    }

    @ViewBuilder
    private func editCard(_ song: Song, index: Int, total: Int) -> some View {
        let isCurrent = appState.isCurrentTrack(song.audio)
        let isPlayed = appState.isPlayed(song, in: set)
        let genre = appState.concertGenre(for: song)
        let songID = song.id

        HStack(spacing: 8) {
            // Numéro d'ordre
            Text("\(index)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 22, alignment: .trailing)

            // Pastille couleur
            Circle()
                .fill(appState.color(for: song, inSet: set))
                .frame(width: 8, height: 8)
                .overlay { Circle().stroke(.primary.opacity(0.18), lineWidth: 0.5) }

            // Title + sous-titre
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(song.title)
                        .font(.system(size: 13, weight: isCurrent ? .black : .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(isCurrent ? VelvetPalette.gold : .primary)
                    if song.isLiveAdded {
                        Text("LIVE")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(VSColor.cueMarker)
                    }
                    if isPlayed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(VSColor.playActive)
                    }
                }
                HStack(spacing: 6) {
                    Text(genre.label)
                        .foregroundStyle(appState.color(for: genre))
                        .bold()
                    Text(song.duration)
                    if song.audio == nil {
                        Text("⚠").foregroundStyle(.red)
                    }
                }
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button(role: .destructive) {
                appState.removeFromShow(songID: song.element.setElementID, in: set)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove this song from the show")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(isCurrent ? VelvetPalette.gold.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onDrag {
            NSItemProvider(object: "\(Self.showSongDragPrefix)\(songID)" as NSString)
        } preview: {
            editCardDragPreview(song)
        }
        .onDrop(of: [.plainText], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let text = (object as? NSString) as String?,
                      text.hasPrefix(Self.showSongDragPrefix),
                      let sourceID = Int64(text.dropFirst(Self.showSongDragPrefix.count)),
                      sourceID != songID else { return }
                Task { @MainActor in
                    appState.moveSong(in: set, songID: sourceID, before: songID)
                }
            }
            return true
        }
    }

    private func setlistWall(size: CGSize) -> some View {
        // En mode recherche on affiche une fine ligne de contexte (terme + compteur).
        // En mode normal le header RESTANTS/XX est supprimé — l'info figure déjà
        // dans l'en-tête du show ("Played X/N").
        let remainingHeaderHeight: CGFloat = searchText.isEmpty ? 0 : 20
        let verticalSpacing: CGFloat = 4
        let columns = wallColumnCount(width: size.width)
        let rows = songRows(searchActiveSongs, columns: columns)
        let rowCount = max(1, rows.count)
        let remainingHeight = max(120, size.height - remainingHeaderHeight - 10)
        let tileHeight = min(54, max(24, (remainingHeight - CGFloat(rowCount - 1) * verticalSpacing) / CGFloat(rowCount)))

        return VStack(alignment: .leading, spacing: 5) {
            if !searchText.isEmpty {
                HStack(spacing: 8) {
                    Text("RESULTS")
                        .font(.system(size: 14, weight: .black))
                    Text("\(remainingSongs.count)")
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("\"\(searchText)\"")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(VelvetPalette.nowPlayingYellow)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                }
                .frame(height: remainingHeaderHeight)
            }

            if searchActiveSongs.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "Empty Show" : "No results",
                    systemImage: searchText.isEmpty ? "music.note.list" : "magnifyingglass",
                    description: searchText.isEmpty
                        ? Text("Add songs from the Songs tab or drag them here.")
                        : Text("No song matches \"\(searchText)\".")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let orderedIDs = searchActiveSongs.map(\.id)
                let tileWidth = max(1, (size.width - CGFloat(columns - 1) * 5) / CGFloat(columns))
                VStack(spacing: verticalSpacing) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: 5) {
                            // Index calculé depuis la position dans la
                            // grille — robuste si `searchActiveSongs` est
                            // brièvement désynchronisé d'un rendu (lookup
                            // firstIndex retournant nil produisait
                            // précédemment des trous invisibles dans la
                            // grille).
                            ForEach(Array(row.enumerated()), id: \.element.id) { positionInRow, song in
                                setlistTile(
                                    song,
                                    height: tileHeight,
                                    index: rowIndex * columns + positionInRow,
                                    tileWidth: tileWidth,
                                    orderedSongIDs: orderedIDs
                                )
                            }
                            ForEach(0..<max(0, columns - row.count), id: \.self) { _ in
                                // Hauteur explicitement bornée : sans ça
                                // Color.clear est greedy verticalement
                                // dans une HStack et fait gonfler toute
                                // la rangée (la dernière, qui contient
                                // ces placeholders, devenait énorme et
                                // créait un grand vide entre rangées).
                                Color.clear
                                    .frame(maxWidth: .infinity, minHeight: tileHeight, maxHeight: tileHeight)
                            }
                        }
                        .frame(height: tileHeight)
                    }
                    Spacer(minLength: 0)
                }
            }

        }
        .coordinateSpace(name: Self.setlistCoordinateSpace)
        .overlay(alignment: .topLeading) {
            setlistDragPreview
        }
        .onPreferenceChange(SetlistTileFramePreferenceKey.self) { frames in
            setlistTileFrames = frames
        }
    }

    @ViewBuilder
    private var setlistDragPreview: some View {
        if let draggingShowSongID,
           let location = dragPreviewLocation,
           let song = searchActiveSongs.first(where: { $0.id == draggingShowSongID }),
           let frame = setlistTileFrames[draggingShowSongID] {
            dragPreviewTile(song, frame: frame)
                .position(x: location.x, y: location.y)
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(1000)
        }
    }

    private func wallColumnCount(width: CGFloat) -> Int {
        let rawCount = Int(width / 175)
        return min(7, max(3, rawCount))
    }

    private func songRows(_ songs: [Song], columns: Int) -> [[Song]] {
        guard columns > 0 else { return [songs] }
        return stride(from: 0, to: songs.count, by: columns).map { index in
            Array(songs[index..<min(index + columns, songs.count)])
        }
    }

    @ViewBuilder
    private func setlistTile(
        _ song: Song,
        height: CGFloat,
        index: Int,
        tileWidth: CGFloat,
        orderedSongIDs: [Song.ID]
    ) -> some View {
        let isGhost = appState.isPlayed(song, in: set)
        if isGhost {
            ghostTile(song, height: height, tileWidth: tileWidth)
        } else {
        let isCurrent = appState.isCurrentTrack(song.audio)
        let isSelected = selectedSongID == song.id
        let showsLeadingInsertion = proposedDropIndex == index && draggingShowSongID != song.id
        let showsTrailingInsertion = proposedDropIndex == index + 1 && index == orderedSongIDs.count - 1 && draggingShowSongID != song.id
        let isPriorityNext = priorityNextSongID == song.id
        let priorityMode = isPriorityNext ? priorityNextItem?.playbackMode : nil
        let isPreloadedStop = !isPriorityNext
            && appState.preloadedStopElementID == song.id
            && appState.audioEngine.state == .stopped
        let hasActivePlayback = appState.currentlyLoadedTrack != nil && appState.audioEngine.state != .stopped
        let canPrioritizeNext = !isCurrent && song.audio != nil && hasActivePlayback
        let isRecentlyAdded = appState.recentlyAddedLiveElementID == song.element.setElementID
        let isNextNatural = song.element.setElementID == appState.nextNaturalSongElementID
        let titleSize = min(19, max(12, height * 0.44))
        let reservesNextUpControl = canPrioritizeNext

        HStack(spacing: isCurrent ? 7 : 0) {
            if isCurrent {
                // Icône ▶︎ bien visible at 2 m — taille proportionnelle au titre
                Image(systemName: "play.fill")
                    .font(.system(size: titleSize * 0.75, weight: .black))
                    .foregroundStyle(.black)
            }
            Text(song.title.uppercased())
                .font(.system(size: titleSize, weight: isCurrent ? .black : .bold))
                .lineLimit(height < 38 ? 1 : 2)
                .minimumScaleFactor(0.64)
                .foregroundStyle(tileTitleColor(song: song, isCurrent: isCurrent))
                // Pas d'ombre for texte noir sur fond jaune — inutile et brouillon
                .shadow(color: .black.opacity(isCurrent ? 0 : 0.20), radius: 1, x: 0, y: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .mask {
                    titleTrailingFadeMask(isEnabled: reservesNextUpControl)
                }
        }
        .padding(.horizontal, 12)
        .padding(.trailing, reservesNextUpControl ? nextUpTitleSafetyInset : 0)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
        .background {
            selectedTileBackground(song: song, isCurrent: isCurrent, isSelected: isSelected, isRecentlyAdded: isRecentlyAdded)
        }
        .overlay(alignment: .topLeading) {
            if isPriorityNext {
                nextUpBadge(height: height, mode: priorityMode) {
                    if let item = priorityNextItem {
                        let next: QueuePlaybackMode = item.playbackMode == .automatic ? .manual : .automatic
                        appState.setQueuePlaybackMode(next, for: item, in: set)
                    }
                }
            } else if isPreloadedStop {
                readyStopBadge(height: height)
            }
        }
        .overlay(alignment: .topTrailing) {
            if song.isLiveAdded {
                liveBadge(height: height)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if canPrioritizeNext {
                nextUpButton(song)
                    .padding(4)
            }
        }
        .overlay(alignment: .bottomLeading) {
            let behavior = appState.endBehavior(for: song, in: set)
            if behavior != .autoStop && height >= 28 {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: min(9, height * 0.22), weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(4)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: PerformanceChrome.tileRadius, style: .continuous)
                .stroke(
                    tileBorderColor(
                        song: song,
                        isCurrent: isCurrent,
                        isSelected: isSelected,
                        isLive: song.isLiveAdded,
                        isPriorityNext: isPriorityNext
                    ),
                    lineWidth: isCurrent ? 3.5 : (isPriorityNext ? 3 : (isSelected ? 2.5 : 1.4))
                )
        }
        .overlay {
            if isPriorityNext && priorityMode == .automatic {
                AutoBlinkBorder(cornerRadius: PerformanceChrome.tileRadius)
            }
        }
        .overlay {
            // Halo blanc très discret — indique visuellement que la lecture est active
            if isCurrent {
                NowPlayingPulseBorder(cornerRadius: PerformanceChrome.tileRadius)
            }
        }
        .overlay {
            if isNextNatural {
                NextNaturalBorder(cornerRadius: PerformanceChrome.tileRadius)
                    .transition(.opacity)
            }
        }
        .overlay {
            // Bordure jaune animée sur les tuiles correspondant at la recherche
            if !searchText.isEmpty && song.title.localizedCaseInsensitiveContains(searchText) {
                SearchMatchBorder(cornerRadius: PerformanceChrome.tileRadius)
            }
        }
        .overlay(alignment: .leading) {
            if showsLeadingInsertion {
                insertionLine(height: height)
            }
        }
        .overlay(alignment: .trailing) {
            if showsTrailingInsertion {
                insertionLine(height: height)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: PerformanceChrome.tileRadius, style: .continuous))
        // Ombre portée sur la tuile en cours : la fait ressortir de la liste
        .shadow(
            color: isCurrent
            ? VelvetPalette.nowPlayingYellow.opacity(0.34)
            : (isSelected || isPriorityNext ? .black.opacity(0.34) : .black.opacity(0.12)),
            radius: isCurrent ? 15 : (isSelected || isPriorityNext ? 9 : 3),
            x: 0,
            y: isCurrent ? 7 : 3
        )
        .contentShape(Rectangle())
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SetlistTileFramePreferenceKey.self,
                    value: [song.id: proxy.frame(in: .named(Self.setlistCoordinateSpace))]
                )
            }
        )
        .opacity(draggingShowSongID == song.id ? 0.45 : (song.audio == nil ? 0.52 : 1))
        .highPriorityGesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .named(Self.setlistCoordinateSpace))
                .onChanged { value in
                    updateSetlistDrag(songID: song.id, location: value.location, orderedSongIDs: orderedSongIDs)
                }
                .onEnded { value in
                    let destinationIndex = insertionIndex(
                        at: value.location,
                        draggingSongID: song.id,
                        orderedSongIDs: orderedSongIDs
                    )
                    moveDraggedSetlistSong(song.id, to: destinationIndex, orderedSongIDs: orderedSongIDs)
                    draggingShowSongID = nil
                    dragPreviewLocation = nil
                    proposedDropIndex = nil
                }
        )
        // Double-clic sécurisé : un simple clic ne fait que sélectionner,
        // un double-clic lance la lecture — et si un autre song joue
        // déjà, on demande une confirmation au lieu de couper sec.
        // L'ordre des modifiers compte : `count: 2` doit être déclaré
        // avant `count: 1` for que SwiftUI lui donne la priorité.
        .onTapGesture(count: 2) {
            requestPlay(song)
        }
        .onTapGesture {
            // Sélection simple : si une recherche est active, la vider
            // (la recherche est un outil de localisation, pas d'état permanent).
            clearSearch()
            selectedSongID = song.id
            appState.selectShowSong(song, in: set)
        }
        .contextMenu {
            if let audio = song.audio {
                Button {
                    appState.openInTrackLibrary(audio)
                } label: {
                    Label("Open in Songs", systemImage: "music.note.list")
                }
                Divider()
                Button("Play Next") {
                    appState.prioritizeSongNext(song, in: set)
                }
                Button("Add to Queue") {
                    appState.queueSong(song, in: set, atFront: false)
                }
                Divider()
                Button("Change Color...") {
                    editingColorSong = song
                }
                // Suppression du concert (tous types de show)
                Divider()
                Button("Remove from Show", role: .destructive) {
                    confirmRemoveFromConcert = song
                }
                // Actions avancées — uniquement for les shows Velvet
                if appState.isVelvetShow(set), let vt = appState.velvetTrack(for: audio) {
                    Button("Move to Velvet Trash...", role: .destructive) {
                        trashingVelvetTrack = vt
                    }
                }
            }
        }
        .sheet(item: $editingColorSong) { s in
            if let audio = s.audio {
                TrackColorSheet(track: audio, appState: appState, showSet: set)
            }
        }
        .sheet(item: $trashingVelvetTrack) { vt in
            TrackDeleteSheet(track: vt, sourceShow: appState.velvetShow(for: set)) {
                trashingVelvetTrack = nil
            }
            .environment(appState)
        }
        .confirmationDialog(
            "Remove \"\(confirmRemoveFromConcert?.audio?.name ?? "this song")\" from the show?",
            isPresented: Binding(
                get: { confirmRemoveFromConcert != nil },
                set: { if !$0 { confirmRemoveFromConcert = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove from Show", role: .destructive) {
                if let song = confirmRemoveFromConcert {
                    appState.removeFromShow(songID: song.element.setElementID, in: set)
                }
                confirmRemoveFromConcert = nil
            }
            Button("Cancel", role: .cancel) {
                confirmRemoveFromConcert = nil
            }
        } message: {
            Text("The song will be removed from this show only. Library, memos, trims and audio settings remain intact.")
        }
        }
    }

    private func ghostTile(_ song: Song, height: CGFloat, tileWidth: CGFloat) -> some View {
        let isNextNatural = song.element.setElementID == appState.nextNaturalSongElementID
        let isSelected = selectedSongID == song.id
        let titleSize = min(19, max(12, height * 0.44))
        let titleColor = playedTileTitleColor
        let metadataColor = playedTileMetadataColor
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: PerformanceChrome.tileRadius, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.08 : 0.045))
            RoundedRectangle(cornerRadius: PerformanceChrome.tileRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(isSelected ? 0.55 : 0.10), lineWidth: isSelected ? 2 : 1)
            HStack(spacing: 6) {
                Text(song.title.uppercased())
                    .font(.system(size: titleSize, weight: .bold))
                    .lineLimit(height < 38 ? 1 : 2)
                    .minimumScaleFactor(0.64)
                    .foregroundStyle(titleColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if height >= 28 {
                    Image(systemName: "checkmark")
                        .font(.system(size: min(10, height * 0.22), weight: .semibold))
                        .foregroundStyle(metadataColor)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .clipShape(RoundedRectangle(cornerRadius: PerformanceChrome.tileRadius, style: .continuous))
        .overlay {
            if isNextNatural {
                NextNaturalBorder(cornerRadius: PerformanceChrome.tileRadius)
                    .transition(.opacity)
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SetlistTileFramePreferenceKey.self,
                    value: [song.id: proxy.frame(in: .named(Self.setlistCoordinateSpace))]
                )
            }
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            requestPlay(song)
        }
        .onTapGesture {
            clearSearch()
            selectedSongID = song.id
            appState.selectShowSong(song, in: set)
        }
    }

    private var playedTileTitleColor: Color {
        colorScheme == .light ? .black.opacity(0.62) : .white.opacity(0.22)
    }

    private var playedTileMetadataColor: Color {
        colorScheme == .light ? .black.opacity(0.50) : .white.opacity(0.20)
    }

    private func dragPreviewTile(_ song: Song, frame: CGRect) -> some View {
        let isCurrent = appState.isCurrentTrack(song.audio)
        let isPriorityNext = priorityNextSongID == song.id
        let titleSize = min(19, max(12, frame.height * 0.44))

        return HStack(spacing: isCurrent ? 7 : 0) {
            if isCurrent {
                Image(systemName: "play.fill")
                    .font(.system(size: titleSize * 0.75, weight: .black))
                    .foregroundStyle(.black)
            }
            Text(song.title.uppercased())
                .font(.system(size: titleSize, weight: isCurrent ? .black : .bold))
                .lineLimit(frame.height < 38 ? 1 : 2)
                .minimumScaleFactor(0.64)
                .foregroundStyle(tileTitleColor(song: song, isCurrent: isCurrent))
                .shadow(color: .black.opacity(isCurrent ? 0 : 0.22), radius: 1, x: 0, y: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(width: frame.width, height: frame.height, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: PerformanceChrome.tileRadius, style: .continuous)
                .fill(AnyShapeStyle(tileBackground(song: song, isCurrent: isCurrent, isRecentlyAdded: song.isLiveAdded)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: PerformanceChrome.tileRadius, style: .continuous)
                .stroke(
                    tileBorderColor(
                        song: song,
                        isCurrent: isCurrent,
                        isSelected: true,
                        isLive: song.isLiveAdded,
                        isPriorityNext: isPriorityNext
                    ),
                    lineWidth: 2.4
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: PerformanceChrome.tileRadius, style: .continuous))
        .scaleEffect(1.02)
        .opacity(0.82)
        .shadow(color: .black.opacity(0.38), radius: 18, x: 0, y: 10)
        .shadow(color: VelvetPalette.goldLight.opacity(0.18), radius: 14, x: 0, y: 0)
    }

    private func updateSetlistDrag(songID: Song.ID, location: CGPoint, orderedSongIDs: [Song.ID]) {
        draggingShowSongID = songID
        dragPreviewLocation = location
        proposedDropIndex = insertionIndex(at: location, draggingSongID: songID, orderedSongIDs: orderedSongIDs)
    }

    private func insertionIndex(at location: CGPoint, draggingSongID: Song.ID, orderedSongIDs: [Song.ID]) -> Int {
        guard !orderedSongIDs.isEmpty else { return 0 }

        // Collecte toutes les frames valides (hors tuile glissée) avec leur index.
        let validFrames: [(index: Int, frame: CGRect)] = orderedSongIDs.enumerated().compactMap { idx, id in
            guard id != draggingSongID, let frame = setlistTileFrames[id] else { return nil }
            return (idx, frame)
        }
        guard !validFrames.isEmpty else { return 0 }

        // ── Étape 1 : tuiles sur la même rangée (plage Y du curseur) ──────────
        //
        // Le bug original itérait séquentiellement et s'arrêtait sur la
        // PREMIÈRE tuile de la rangée dont le Y correspondait, ignorant toutes
        // les colonnes suivantes. On collecte d'abord TOUTES les tuiles de la
        // rangée visée, puis on choisit la bonne colonne par midX.
        let rowTiles = validFrames.filter { location.y >= $0.frame.minY && location.y <= $0.frame.maxY }

        if !rowTiles.isEmpty {
            // Algorithme "bisection par midX" : si le curseur est at gauche
            // du midX d'une tuile, on insère AVANT elle ; sinon on continue
            // jusqu'à la dernière tuile, puis on insère après.
            for tile in rowTiles where location.x < tile.frame.midX {
                return tile.index
            }
            // Curseur at droite de tous les midX de la rangée → après la dernière tuile.
            return (rowTiles.last?.index ?? 0) + 1
        }

        // ── Étape 2 : curseur dans un inter-rangée ou hors grille ────────────
        //
        // Cherche la première tuile dont le haut est en dessous du curseur :
        // c'est le point d'insertion avant cette tuile.
        if let firstBelow = validFrames.first(where: { location.y < $0.frame.minY }) {
            return firstBelow.index
        }

        // ── Étape 3 : curseur après toutes les tuiles → append ───────────────
        return orderedSongIDs.count
    }

    private func moveDraggedSetlistSong(_ sourceID: Song.ID, to destinationIndex: Int, orderedSongIDs: [Song.ID]) {
        guard !orderedSongIDs.isEmpty else { return }
        if destinationIndex >= orderedSongIDs.count {
            guard let lastID = orderedSongIDs.last, sourceID != lastID else { return }
            appState.moveSong(in: set, songID: sourceID, after: lastID)
        } else {
            let targetID = orderedSongIDs[max(0, destinationIndex)]
            guard sourceID != targetID else { return }
            appState.moveSong(in: set, songID: sourceID, before: targetID)
        }
    }

    /// Tuile du song en cours : jaune vif Apple system yellow (#FFD60A).
    /// Identifiable instantanément at 2 m — contraste maximal avec le
    /// texte noir sur fond lumineux, lisible en salle sombre comme en plein jour.
    private var currentSongTileBackground: some ShapeStyle {
        AnyShapeStyle(
            LinearGradient(
                colors: [VelvetPalette.goldLight, VelvetPalette.nowPlayingYellow, VelvetPalette.gold],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func tileBackground(song: Song, isCurrent: Bool, isRecentlyAdded: Bool) -> some ShapeStyle {
        if isCurrent {
            return AnyShapeStyle(currentSongTileBackground)
        }
        let opacity = isRecentlyAdded || song.isLiveAdded ? 0.96 : 0.88
        let base = appState.color(for: song, inSet: set)
        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    base.opacity(min(1.0, opacity + 0.08)),
                    base.opacity(max(0.60, opacity - 0.10))
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    @ViewBuilder
    private func selectedTileBackground(song: Song, isCurrent: Bool, isSelected: Bool, isRecentlyAdded: Bool) -> some View {
        if isSelected && !isCurrent {
            // Prototype Liquid Glass — uniquement sur la tuile sélectionnée
            Color.clear
                .glassEffect(.regular.tint(appState.color(for: song, inSet: set).opacity(0.68)),
                             in: RoundedRectangle(cornerRadius: PerformanceChrome.tileRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: PerformanceChrome.tileRadius, style: .continuous)
                        .fill(PerformanceChrome.panelHighlight)
                }
        } else {
            RoundedRectangle(cornerRadius: PerformanceChrome.tileRadius, style: .continuous)
                .fill(AnyShapeStyle(tileBackground(song: song, isCurrent: isCurrent, isRecentlyAdded: isRecentlyAdded)))
        }
    }

    private func tileBorderColor(song: Song, isCurrent: Bool, isSelected: Bool, isLive: Bool, isPriorityNext: Bool) -> Color {
        // Tuile current : bordure noire nette sur fond jaune vif — contraste maximal.
        if isCurrent {
            return Color.black.opacity(0.60)
        }
        if isSelected {
            return VelvetPalette.goldLight
        }
        if isPriorityNext {
            return VelvetPalette.gold
        }
        return appState.color(for: song, inSet: set).opacity(0.95)
    }

    /// Color du titre d'une tuile.
    /// Toutes les couleurs `VSColor.Tile` étant foncées, le blanc est
    /// systématiquement lisible. La tuile courante utilise le noir sur fond jaune.
    private func tileTitleColor(song: Song, isCurrent: Bool) -> Color {
        isCurrent ? .black : .white
    }

    private func insertionLine(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(VSColor.dropIndicator)
            .frame(width: 4, height: max(22, height + 8))
            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
            .padding(.vertical, -4)
    }

    private var nextUpTitleSafetyInset: CGFloat { 32 }

    @ViewBuilder
    private func titleTrailingFadeMask(isEnabled: Bool) -> some View {
        if isEnabled {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(.white)
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(1.0), location: 0.00),
                        .init(color: .white.opacity(1.0), location: 0.18),
                        .init(color: .white.opacity(0.80), location: 0.36),
                        .init(color: .white.opacity(0.60), location: 0.52),
                        .init(color: .white.opacity(0.40), location: 0.68),
                        .init(color: .white.opacity(0.20), location: 0.84),
                        .init(color: .white.opacity(0.0), location: 1.00)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 38)
            }
        } else {
            Rectangle()
                .fill(.white)
        }
    }

    private func nextUpButton(_ song: Song) -> some View {
        let queue = appState.queueItems(for: set)
        // Ce song est-il le 1er de la queue (le song armé "à suivre") ?
        let priorityItem = queue.first(where: { $0.setElementID == song.element.setElementID
                                             && queue.first?.id == $0.id })
        let isPriorityNext = priorityItem != nil
        // Déjà en queue mais pas en position 1 (position 2+).
        let isAlreadyQueued = !isPriorityNext && queue.contains {
            $0.setElementID == song.element.setElementID
        }

        return Button {
            if isPriorityNext, let item = priorityItem {
                appState.removeQueueItem(item, from: set)
            } else {
                appState.prioritizeSongNext(song, in: set)
            }
        } label: {
            if isPriorityNext {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(VSColor.warning)
                    .contentTransition(.symbolEffect(.replace))
            } else {
                Image(systemName: isAlreadyQueued ? "arrow.up.circle.fill" : "arrow.up.circle")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(isAlreadyQueued
                                     ? VelvetPalette.gold
                                     : VelvetPalette.gold.opacity(0.55))
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(.plain)
        .help(isPriorityNext ? "Cancel next song" : (isAlreadyQueued ? "Already in Queue" : "Play Next"))
    }

    @ViewBuilder
    private func nextUpBadge(height: CGFloat, mode: QueuePlaybackMode?, action: @escaping () -> Void) -> some View {
        let isStop = mode == .manual
        let label  = isStop ? "NEXT · STOP" : "NEXT · AUTO"
        let color  = isStop ? VSColor.warning : VSColor.playActive
        Button(action: action) {
            if height >= 40 {
                Text(label)
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(VelvetPalette.velvetBlack)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color, in: Capsule())
                    .padding(4)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .padding(4)
            }
        }
        .buttonStyle(.plain)
        .help(isStop ? "Click: switch to AUTO (starts automatically)" : "Click: switch to STOP (stop after playback)")
    }

    @ViewBuilder
    private func readyStopBadge(height: CGFloat) -> some View {
        if height >= 40 {
            Text("READY · STOP")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(VelvetPalette.velvetBlack)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(VSColor.warning, in: Capsule())
                .padding(4)
        } else {
            Circle()
                .fill(VSColor.warning)
                .frame(width: 7, height: 7)
                .padding(4)
        }
    }

    /// Petit badge en haut at droite : "ADDED LIVE" si la tuile est haute,
    /// juste une pastille colorée si on est at la limite basse (24-32 pt).
    @ViewBuilder
    private func liveBadge(height: CGFloat) -> some View {
        if height >= 40 {
            Text("ADDED LIVE")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(VSColor.cueMarker.opacity(0.92), in: Capsule())
                .padding(4)
        } else {
            Circle()
                .fill(VSColor.cueMarker)
                .frame(width: 6, height: 6)
                .padding(4)
        }
    }

    private func handleTrackDrop(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = (object as? NSString) as String?,
                  !text.hasPrefix(Self.showSongDragPrefix),
                  let audioID = Int64(text) else { return }
            Task { @MainActor in
                if let track = appState.audioFilesByID[audioID] {
                    appState.addTrack(track, to: set)
                }
            }
        }
    }

    private func handleSetlistBackgroundDrop(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = (object as? NSString) as String? else { return }
            if text.hasPrefix(Self.showSongDragPrefix) {
                guard let songID = Int64(text.dropFirst(Self.showSongDragPrefix.count)) else { return }
                Task { @MainActor in
                    if let lastID = genreFilteredSongs.last?.id, songID != lastID {
                        appState.moveSong(in: set, songID: songID, after: lastID)
                    }
                    draggingShowSongID = nil
                    proposedDropIndex = nil
                }
            } else if let audioID = Int64(text) {
                Task { @MainActor in
                    if let track = appState.audioFilesByID[audioID] {
                        appState.addTrack(track, to: set)
                    }
                }
            }
        }
    }

    private func remainingSongCard(_ song: Song) -> some View {
        let isCurrent = appState.isCurrentTrack(song.audio)
        let isSelected = selectedSongID == song.id
        let isRecentlyAdded = appState.recentlyAddedLiveElementID == song.element.setElementID
        let genre = appState.concertGenre(for: song)
        let risk = song.audio.map { appState.riskLevel(for: $0) }

        return HStack(spacing: 14) {
            Button {
                if let audio = song.audio {
                    selectedSongID = song.id
                    appState.selectShowSong(song, in: set)
                    appState.togglePlayback(track: audio, set: set, element: song.element)
                }
            } label: {
                Image(systemName: isCurrent ? "stop.fill" : "play.fill")
                    .font(.system(size: 28, weight: .black))
                    .frame(width: 62, height: 62)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(isCurrent ? VelvetPalette.gold : .accentColor)
            .disabled(song.audio == nil)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(song.title)
                        .font(.system(size: 30, weight: isCurrent ? .black : .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    if isCurrent {
                        Text("NOW PLAYING")
                            .font(.headline.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .foregroundStyle(.white)
                            .background(VelvetPalette.gold, in: Capsule())
                    }
                    if song.isLiveAdded {
                        Text("ADDED LIVE")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .foregroundStyle(.white)
                            .background(Color.blue, in: Capsule())
                    }
                }

                HStack(spacing: 10) {
                    metadataChip(song.element.playOrder.map { "#\($0)" } ?? "#—")
                    metadataChip("Performer —")
                    metadataChip("Energy —")
                    metadataChip(genre.label)
                    metadataChip(song.duration)
                    if let risk {
                        metadataChip(risk.detail, color: riskChipColor(risk))
                    }
                    if song.audio == nil {
                        metadataChip("Audio Missing", color: .red)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(minHeight: 102)
        .background(cardBackground(isCurrent: isCurrent, isRecentlyAdded: isRecentlyAdded))
        .overlay {
            RoundedRectangle(cornerRadius: PerformanceChrome.hudRadius, style: .continuous)
                .stroke(isSelected ? VelvetPalette.goldLight : Color.white.opacity(0.08), lineWidth: isSelected ? 3 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: PerformanceChrome.hudRadius, style: .continuous))
        .shadow(
            color: isCurrent ? VelvetPalette.nowPlayingYellow.opacity(0.22) : .black.opacity(isSelected ? 0.24 : 0.10),
            radius: isCurrent || isSelected ? 13 : 5,
            x: 0,
            y: isCurrent || isSelected ? 7 : 2
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedSongID = song.id
            appState.selectShowSong(song, in: set)
            if let audio = song.audio {
                appState.togglePlayback(track: audio, set: set, element: song.element)
            }
        }
    }

    private func cardBackground(isCurrent: Bool, isRecentlyAdded: Bool) -> some ShapeStyle {
        if isCurrent {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [VelvetPalette.nowPlayingYellow.opacity(0.34), Color.orange.opacity(0.20)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        if isRecentlyAdded {
            return AnyShapeStyle(Color.blue.opacity(0.24))
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }

    private func riskChipColor(_ risk: TrackRiskLevel) -> Color {
        switch risk {
        case .recent: return .green
        case .sixMonths: return VSColor.warning
        case .oneYear, .unknown: return .red
        }
    }

    private func metadataChip(_ text: String, color: Color = .secondary) -> some View {
        Text(text.uppercased())
            .font(.system(size: 13, weight: .bold).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
    }

    private static func compactDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int((seconds / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h\(String(format: "%02d", minutes))"
        }
        return "\(minutes) min"
    }

}

struct SetlistTileFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Song.ID: CGRect] = [:]

    static func reduce(value: inout [Song.ID: CGRect], nextValue: () -> [Song.ID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

struct SetlistInsertionDropDelegate: DropDelegate {
    let appState: AppState
    let set: ShowSet
    let targetIndex: Int
    let tileWidth: CGFloat
    let orderedSongIDs: [Song.ID]
    let dragPrefix: String
    @Binding var draggingShowSongID: Song.ID?
    @Binding var proposedDropIndex: Int?

    func dropEntered(info: DropInfo) {
        updateProposedIndex(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateProposedIndex(info: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        proposedDropIndex = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        updateProposedIndex(info: info)
        let providers = info.itemProviders(for: [.plainText]) + info.itemProviders(for: [.text])
        guard let provider = providers.first else {
            clearDragState()
            return false
        }
        let destinationIndex = proposedDropIndex ?? targetIndex
        let orderedIDs = orderedSongIDs
        let prefix = dragPrefix
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = (object as? NSString) as String?,
                  text.hasPrefix(prefix),
                  let sourceID = Int64(text.dropFirst(prefix.count)) else {
                Task { @MainActor in clearDragState() }
                return
            }
            Task { @MainActor in
                move(sourceID: sourceID, destinationIndex: destinationIndex, orderedIDs: orderedIDs)
                clearDragState()
            }
        }
        return true
    }

    private func updateProposedIndex(info: DropInfo) {
        guard draggingShowSongID != nil else { return }
        let isAfterMidpoint = info.location.x > tileWidth / 2
        proposedDropIndex = targetIndex + (isAfterMidpoint ? 1 : 0)
    }

    private func move(sourceID: Song.ID, destinationIndex: Int, orderedIDs: [Song.ID]) {
        guard !orderedIDs.isEmpty else { return }
        if destinationIndex >= orderedIDs.count {
            guard let lastID = orderedIDs.last, sourceID != lastID else { return }
            appState.moveSong(in: set, songID: sourceID, after: lastID)
        } else {
            let targetID = orderedIDs[max(0, destinationIndex)]
            guard sourceID != targetID else { return }
            appState.moveSong(in: set, songID: sourceID, before: targetID)
        }
    }

    private func clearDragState() {
        draggingShowSongID = nil
        proposedDropIndex = nil
    }
}

#Preview {
    ContentView()
}
