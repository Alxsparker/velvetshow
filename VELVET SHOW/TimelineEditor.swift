//
//  TimelineEditor.swift
//  VELVET SHOW
//
//  Éditeur de timeline, inspecteur de mémos, inspecteur de cue points,
//  import de paroles. Extrait de ContentView.swift for garder les fichiers
//  sous les 2000 lignes.
//

import SwiftUI
import AVFoundation

private enum EditorChrome {
    static let panelRadius: CGFloat = 16
    static let cardRadius: CGFloat = 15
    static let clipRadius: CGFloat = 13
    static let controlRadius: CGFloat = 16

    static let panelStroke = Color.primary.opacity(0.11)
    static let subtleStroke = Color.primary.opacity(0.08)
    static let selectedStroke = VelvetPalette.goldLight.opacity(0.96)
    static let selectedGlow = VelvetPalette.goldLight.opacity(0.24)
    static let activeGlow = VelvetPalette.nowPlayingYellow.opacity(0.28)
    static let inactiveFill = Color.primary.opacity(0.060)
}

private extension View {
    func editorPanelChrome(radius: CGFloat = EditorChrome.panelRadius) -> some View {
        self
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(EditorChrome.panelStroke, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.13), radius: 18, x: 0, y: 9)
    }

    func editorFloatingChrome(radius: CGFloat = EditorChrome.controlRadius) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(EditorChrome.subtleStroke, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Éditeur de timeline

struct TimelineEditorView: View {
    let track: AudioFile
    let appState: AppState
    var isEmbedded: Bool = false
    @Environment(\.dismiss) private var dismiss

    @State private var editableMemos: [EditableMemo] = []
    /// IDs de tous les mémos actuellement sélectionnés (multi-sélection).
    @State private var selectedMemoIDs: Set<EditableMemo.ID> = []
    /// Dernier mémo touché — pilote l'inspecteur et le badge de compteur.
    @State private var primarySelectedMemoID: EditableMemo.ID?
    /// Déclenche la dialogue de confirmation de suppression.
    @State private var isConfirmingMemoDelete = false
    @State private var dragOrigins: [EditableMemo.ID: Double] = [:]
    @State private var resizeOrigins: [EditableMemo.ID: Double] = [:]
    @State private var isShowingLyricsImport = false
    @State private var isShowingMemoEditor = false
    @State private var isAnalyzingLoudness = false
    @State private var loudnessError: String? = nil
    @State private var bpmText: String = ""
    @State private var isDetectingBPM = false
    @State private var isShowingGenrePopover = false
    /// Carte du panneau de mémos en cours d'édition (double-clic).
    /// nil = toutes les cartes sont en lecture seule, cliquables partout.
    @State private var editingMemoCardID: EditableMemo.ID? = nil

    // Cue Points
    @State private var cuePoints: [CuePoint] = []
    @State private var selectedCuePointID: CuePoint.ID?
    @State private var cuePointDragOrigins: [CuePoint.ID: Double] = [:]
    @State private var editingCuePoint: CuePoint?
    // Position live pendant un drag de cue point (nil = pas de drag en cours)
    @State private var draggingCueTime: [CuePoint.ID: Double] = [:]

    // Cues MIDI timeline
    @State private var midiCues: [TimelineMidiCue] = []
    @State private var editingMidiCue: TimelineMidiCue?
    @State private var isAddingMidiCue = false

    // Cues OSC timeline
    @State private var oscCues: [TimelineOscCue] = []
    @State private var editingOscCue: TimelineOscCue?
    @State private var isAddingOscCue = false

    // Édition non destructive des bornes de lecture. Les valeurs ci-dessous
    // restent locales tant que l'utilisateur n'a pas cliqué "Save
    // trim" — apply-on-save, for ne pas perturber la lecture en cours.
    @State private var editingTrimStart: TimeInterval = 0
    @State private var editingTrimEnd: TimeInterval = 0
    @State private var trimDragStartOrigin: TimeInterval?
    @State private var trimDragEndOrigin: TimeInterval?
    @State private var initialTrimStart: TimeInterval = 0
    @State private var initialTrimEnd: TimeInterval = 0
    private static let iPadPreviewLogicalSize = CGSize(width: 1024, height: 768)
    private static let iPadPreviewScale: CGFloat = 0.42
    private static var iPadPreviewDisplayWidth: CGFloat {
        iPadPreviewLogicalSize.width * iPadPreviewScale
    }
    private static var iPadPreviewDisplayHeight: CGFloat {
        iPadPreviewLogicalSize.height * iPadPreviewScale
    }
    @State private var zoom: Double = 1.0
    /// Position visuelle pendant un drag de seek (nil = position audio réelle).
    @State private var seekDragPosition: TimeInterval?

    private var duration: Double {
        if isLoadedTrack, appState.audioEngine.totalDuration > 0 {
            return max(1, appState.audioEngine.totalDuration)
        }
        return max(1, track.lengthSecs ?? 1)
    }

    private var isLoadedTrack: Bool {
        appState.currentlyLoadedTrack?.audioFileID == track.audioFileID
    }

    private var editorPlayhead: Double {
        if let drag = seekDragPosition { return drag }
        return isLoadedTrack ? appState.audioEngine.currentPosition : 0
    }

    private var editorPlaybackState: AudioEngine.PlaybackState {
        isLoadedTrack ? appState.audioEngine.state : .stopped
    }

    private var volumeOffsetDB: Double {
        appState.volumeOffsetDB(for: track)
    }

    private var volumeTint: Color {
        if volumeOffsetDB > 0.05 { return .green }
        if volumeOffsetDB < -0.05 { return .red }
        return .secondary
    }

    /// `trimEnd == 0` signifie "lecture jusqu'à la fin" — on affiche
    /// alors `duration` comme borne effective.
    private var effectiveEditingTrimEnd: TimeInterval {
        editingTrimEnd > 0 ? min(editingTrimEnd, duration) : duration
    }

    private var selectedMemoIndex: Int? {
        guard let primarySelectedMemoID else { return nil }
        return editableMemos.firstIndex { $0.id == primarySelectedMemoID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            toolbar
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {

                    // 1. Prompteur + panneau mémo sélectionné
                    HStack(alignment: .top, spacing: 18) {
                        editorPrompterPreview
                        selectedMemoPanel
                    }

                    // 2. Timeline / waveform  +  3. Outils timeline
                    waveformOverview

                    // 4. Transport Bar
                    transportBar
                }
                .padding(.bottom, 12)
            }
        }
        .padding(22)
        .frame(minWidth: isEmbedded ? 620 : 760, minHeight: isEmbedded ? 0 : 560)
        .frame(
            minWidth: isEmbedded ? 0 : 1120,
            minHeight: isEmbedded ? 0 : 640
        )
        .onAppear {
            editableMemos = appState.editableMemos(for: track)
            if let first = editableMemos.first {
                selectedMemoIDs = [first.id]
                primarySelectedMemoID = first.id
            }
            let trim = appState.effectiveTrim(for: track)
            editingTrimStart = trim.start
            editingTrimEnd = trim.end
            initialTrimStart = trim.start
            initialTrimEnd = trim.end
            cuePoints = appState.cuePoints(for: track)
            midiCues  = appState.midiCues(for: track)
            oscCues   = appState.oscCues(for: track)
            if let bpm = appState.effectiveTempo(for: track) {
                bpmText = String(format: "%.0f", bpm)
            } else {
                bpmText = ""
            }
            // Sécurité édition : uniquement for la vue plein écran
            if !isEmbedded { appState.enterEditingMode() }
            // macOS donne automatiquement le focus au premier champ texte
            // (panneau mémos) at l'apparition de la vue — la barre espace
            // taperait alors dans le champ au lieu de piloter play/pause.
            // On rend le focus at la fenêtre ; cliquer dans un champ pour
            // éditer fonctionne toujours normalement.
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        .onDisappear {
            if !isEmbedded { appState.exitEditingMode() }
        }
        .onChange(of: editableMemos) { _, newValue in
            appState.saveEditableMemos(newValue, for: track)
        }
        .onChange(of: cuePoints) { _, newValue in
            appState.saveCuePoints(newValue, for: track)
        }
        .onChange(of: midiCues) { _, newValue in
            appState.saveMidiCues(newValue, for: track)
        }
        .onChange(of: oscCues) { _, newValue in
            appState.saveOscCues(newValue, for: track)
        }
        // Raccourcis clavier locaux at l'éditeur (J/L/Shift+J/Shift+L)
        // fonctionnent en mode sheet. Space est géré globalement par l'app.
        .background(
            Group {
                // J → -5 s
                Button("") { skipBackward() }
                    .keyboardShortcut("j", modifiers: [])
                    .hidden()
                // L → +5 s
                Button("") { skipForward() }
                    .keyboardShortcut("l", modifiers: [])
                    .hidden()
                // Shift+J → cue précédent
                Button("") { navigateToPrevCue() }
                    .keyboardShortcut("j", modifiers: .shift)
                    .hidden()
                // Shift+L → cue suivant
                Button("") { navigateToNextCue() }
                    .keyboardShortcut("l", modifiers: .shift)
                    .hidden()
                // Home / ESC → début song
                Button("") { goToStart() }
                    .keyboardShortcut(.home, modifiers: [])
                    .hidden()
                Button("") { goToStart() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .hidden()
                // End → fin song
                Button("") { goToEnd() }
                    .keyboardShortcut(.end, modifiers: [])
                    .hidden()
                // Delete → supprime les mémos sélectionnés (avec confirmation)
                Button("") {
                    if !selectedMemoIDs.isEmpty { isConfirmingMemoDelete = true }
                }
                .keyboardShortcut(.delete, modifiers: [])
                .hidden()
            }
        )
        .sheet(isPresented: $isShowingLyricsImport) {
            LyricsImportSheet(
                track: track,
                appState: appState,
                existingMemos: editableMemos,
                initialImportMode: editableMemos.isEmpty ? .replace : .append,
                onImport: { importedMemos in
                    editableMemos = importedMemos
                    if let first = importedMemos.first {
                        selectedMemoIDs = [first.id]
                        primarySelectedMemoID = first.id
                    } else {
                        selectedMemoIDs = []
                        primarySelectedMemoID = nil
                    }
                }
            )
        }
        .sheet(isPresented: $isShowingMemoEditor) {
            if let index = selectedMemoIndex {
                MemoInspectorView(
                    memo: $editableMemos[index],
                    appState: appState,
                    onDelete: {
                        let deletedID = editableMemos[index].id
                        editableMemos.remove(at: index)
                        selectedMemoIDs.remove(deletedID)
                        if primarySelectedMemoID == deletedID {
                            primarySelectedMemoID = selectedMemoIDs.first
                        }
                    }
                )
                .frame(width: 500, height: 430)
            }
        }
        .confirmationDialog(
            selectedMemoIDs.count == 1
                ? "Delete this memo?"
                : "Delete \(selectedMemoIDs.count) memos?",
            isPresented: $isConfirmingMemoDelete,
            titleVisibility: .visible
        ) {
            Button(
                selectedMemoIDs.count == 1
                    ? "Delete"
                    : "Delete \(selectedMemoIDs.count) memos",
                role: .destructive
            ) {
                let toDelete = selectedMemoIDs
                editableMemos.removeAll { toDelete.contains($0.id) }
                selectedMemoIDs = []
                primarySelectedMemoID = nil
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $editingCuePoint) { cue in
            CuePointInspectorSheet(
                cuePoint: cue,
                duration: duration,
                onSave: { updated in
                    if let i = cuePoints.firstIndex(where: { $0.id == updated.id }) {
                        cuePoints[i] = updated
                    }
                    editingCuePoint = nil
                },
                onDelete: { id in
                    cuePoints.removeAll { $0.id == id }
                    if selectedCuePointID == id { selectedCuePointID = nil }
                    editingCuePoint = nil
                }
            )
            .frame(width: 380)
        }
        .sheet(item: $editingMidiCue) { cue in
            MidiCueInspectorSheet(
                appState: appState,
                midiCue: cue,
                duration: duration,
                onSave: { updated in
                    if let i = midiCues.firstIndex(where: { $0.id == updated.id }) {
                        midiCues[i] = updated
                    }
                    editingMidiCue = nil
                },
                onDelete: { id in
                    midiCues.removeAll { $0.id == id }
                    editingMidiCue = nil
                }
            )
            .frame(width: 360)
        }
        .sheet(isPresented: $isAddingMidiCue) {
            MidiCueInspectorSheet(
                appState: appState,
                midiCue: TimelineMidiCue(
                    time: min(duration, max(0, editorPlayhead)),
                    midiEventID: appState.midiEventsByID.values
                        .sorted { ($0.name ?? "") < ($1.name ?? "") }.first?.midiEventID ?? -1
                ),
                duration: duration,
                onSave: { newCue in
                    midiCues.append(newCue)
                    isAddingMidiCue = false
                },
                onDelete: { _ in
                    isAddingMidiCue = false
                }
            )
            .frame(width: 360)
        }
        .sheet(item: $editingOscCue) { cue in
            OscCueInspectorSheet(
                appState: appState,
                oscCue: cue,
                duration: duration,
                onSave: { updated in
                    if let i = oscCues.firstIndex(where: { $0.id == updated.id }) {
                        oscCues[i] = updated
                    }
                    editingOscCue = nil
                },
                onDelete: { id in
                    oscCues.removeAll { $0.id == id }
                    editingOscCue = nil
                }
            )
            .frame(width: 400)
        }
        .sheet(isPresented: $isAddingOscCue) {
            OscCueInspectorSheet(
                appState: appState,
                oscCue: TimelineOscCue(
                    time: min(duration, max(0, editorPlayhead))
                ),
                duration: duration,
                onSave: { newCue in
                    oscCues.append(newCue)
                    isAddingOscCue = false
                },
                onDelete: { _ in
                    isAddingOscCue = false
                }
            )
            .frame(width: 400)
        }
    }

    @ViewBuilder
    private var toolbar: some View {
        if !isEmbedded {
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Transport Bar

    private var transportBar: some View {
        HStack(spacing: 0) {

            // ── Groupe 1 : contrôles de transport ──────────────────
            HStack(spacing: 2) {
                // Start
                transportButton(
                    icon: "backward.end.alt.fill",
                    help: "Start (Home)"
                ) { goToStart() }

                // -5 s
                transportButton(
                    icon: "gobackward.5",
                    help: "-5 secondes (J)"
                ) { skipBackward() }

                // Play / Pause
                transportPlayPauseButton

                // Stop
                transportButton(
                    icon: "stop.fill",
                    help: "Stop"
                ) {
                    appState.requestStop()
                }
                .foregroundStyle(
                    editorPlaybackState == .stopped ? Color.secondary : Color.primary
                )

                // +5 s
                transportButton(
                    icon: "goforward.5",
                    help: "+5 secondes (L)"
                ) { skipForward() }

                // End
                transportButton(
                    icon: "forward.end.alt.fill",
                    help: "End (End)"
                ) { goToEnd() }
            }

            transportDivider

            // ── Groupe 2 : timecodes ────────────────────────────────
            HStack(spacing: 4) {
                // Position courante
                Text(Self.timecodeMillis(editorPlayhead))
                    .font(.system(.body, design: .monospaced).bold())
                    .foregroundStyle(.primary)
                    .frame(minWidth: 88, alignment: .trailing)

                Text("/")
                    .font(.body)
                    .foregroundStyle(.tertiary)

                // Duration totale
                Text(Self.timecodeMillis(duration))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 88, alignment: .leading)
            }

            transportDivider

            // ── Groupe 3 : navigation cue points ──────────────────
            HStack(spacing: 2) {
                // Cue précédent
                transportButton(
                    icon: "backward.frame.fill",
                    help: prevCue.map { "Previous cue: \($0.name) (⇧J)" } ?? "No previous cue"
                ) { navigateToPrevCue() }
                .disabled(prevCue == nil)

                // Indicateur : nombre de cue points
                if !cuePoints.isEmpty {
                    Text("\(cuePoints.count)")
                        .font(VSFont.rank)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 18)
                }

                // Cue suivant
                transportButton(
                    icon: "forward.frame.fill",
                    help: nextCue.map { "Next cue: \($0.name) (⇧L)" } ?? "No next cue"
                ) { navigateToNextCue() }
                .disabled(nextCue == nil)
            }

            transportDivider

            // ── Groupe 4 : volume (compact) ─────────────────────────
            volumeControl

            transportDivider

            // ── Groupe 5 : analyse LUFS ──────────────────────────────
            loudnessControl

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .editorFloatingChrome(radius: 13)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var transportDivider: some View {
        Divider()
            .frame(height: 18)
            .padding(.horizontal, 10)
    }

    @ViewBuilder
    private var transportPlayPauseButton: some View {
        let isPlaying = editorPlaybackState == .playing
        Button {
            releaseTextFocus()
            if isPlaying {
                appState.requestPause()
            } else if isLoadedTrack {
                appState.requestResume()
            } else {
                appState.load(track: track)
                // Petit délai for laisser l'engine s'initialiser
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(50))
                    appState.requestResume()
                }
            }
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isPlaying ? VSColor.playActive : .primary)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isPlaying
                      ? VSColor.playActive.opacity(0.18)
                      : Color.clear)
        )
        .animation(.snappy(duration: 0.18), value: isPlaying)
        .help(isPlaying ? "Pause (Espace)" : "Play (Space)")
        .keyboardShortcut(.space, modifiers: [])
    }

    @ViewBuilder
    private func transportButton(
        icon: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            releaseTextFocus()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.001))
        )
        .help(help)
    }

    // MARK: - Navigation actions

    private func goToStart() {
        appState.seek(track: track, to: 0)
    }

    private func goToEnd() {
        appState.seek(track: track, to: max(0, duration - 0.1))
    }

    private func skipBackward() {
        let pos = max(0, editorPlayhead - 5)
        appState.seek(track: track, to: pos)
    }

    private func skipForward() {
        let pos = min(duration, editorPlayhead + 5)
        appState.seek(track: track, to: pos)
    }

    /// Cue point directement avant la position courante (tolérance 0.1 s).
    private var prevCue: CuePoint? {
        cuePoints
            .filter { $0.time < editorPlayhead - 0.1 }
            .max(by: { $0.time < $1.time })
    }

    /// Cue point directement après la position courante (tolérance 0.1 s).
    private var nextCue: CuePoint? {
        cuePoints
            .filter { $0.time > editorPlayhead + 0.1 }
            .min(by: { $0.time < $1.time })
    }

    private func navigateToPrevCue() {
        guard let cue = prevCue else { return }
        appState.seek(track: track, to: cue.time)
    }

    private func navigateToNextCue() {
        guard let cue = nextCue else { return }
        appState.seek(track: track, to: cue.time)
    }

    /// Format mm:ss.mmm — millisecondes incluses.
    private static func timecodeMillis(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let m  = Int(clamped) / 60
        let s  = Int(clamped) % 60
        let ms = Int((clamped.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d.%03d", m, s, ms)
    }

    /// Contrôle de volume — compact for s'intégrer dans la Transport Bar.
    private var volumeControl: some View {
        HStack(spacing: 8) {
            Image(systemName: volumeOffsetDB < -0.05 ? "speaker.fill"
                             : volumeOffsetDB > 0.05 ? "speaker.wave.3.fill"
                             : "speaker.wave.2.fill")
                .font(.caption)
                .foregroundStyle(volumeTint)

            Slider(
                value: Binding(
                    get: { volumeOffsetDB },
                    set: { appState.setVolumeOffsetDB($0, for: track) }
                ),
                in: VelvetTrackVolume.minimumDB...VelvetTrackVolume.maximumDB,
                step: 0.5
            )
            .frame(width: 140)
            .tint(volumeTint)

            Text(Self.volumeDBString(volumeOffsetDB))
                .font(VSFont.timecode)
                .foregroundStyle(volumeTint)
                .frame(width: 52, alignment: .trailing)

            if abs(volumeOffsetDB) >= 0.05 {
                Button {
                    appState.resetVolume(for: track)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Reset volume")
            }
        }
    }

    // MARK: - Contrôle LUFS

    private var loudnessControl: some View {
        HStack(spacing: 8) {
            if isAnalyzingLoudness {
                ProgressView().controlSize(.small)
                Text("Analyse...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let info = appState.loudnessInfo(for: track) {
                // Results disponibles
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(String(format: "%.1f LUFS", info.measuredLUFS ?? 0))
                            .font(.system(.caption, design: .monospaced).bold())
                            .foregroundStyle(loudnessTint(info.measuredLUFS ?? -99))
                        if let tp = info.measuredTruePeakDB {
                            Text(String(format: "TP %.2f dBTP", tp))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(tp > -1.0 ? .orange : .secondary)
                        }
                        if let gain = info.normGainDB {
                            let applied = appState.effectiveNormGainDB(for: track)
                            let isOn = appState.isNormalizationEnabled && info.measuredLUFS != nil
                            Text(isOn
                                 ? String(format: "norm %+.1f dB ▶ %+.1f dB", gain, applied)
                                 : String(format: "norm %+.1f dB", gain))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(abs(gain) < 0.5 ? .secondary : .primary)
                        }
                        Toggle("", isOn: Binding(
                            get: { appState.isNormalizationEnabled },
                            set: { appState.isNormalizationEnabled = $0 }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .help(appState.isNormalizationEnabled ? "Normalization enabled" : "Normalization disabled")
                    }
                    // Ligne de diagnostic : peak PCM + delta TP−PCM
                    if let tp = info.measuredTruePeakDB, let pcm = info.measuredPcmPeakDB {
                        let delta = tp - pcm
                        HStack(spacing: 6) {
                            Text(String(format: "PCM %.2f dBFS", pcm))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(String(format: "Δ %+.2f dB", delta))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(delta > 1.5 ? .red : delta > 0.5 ? .orange : .secondary)
                                .help("Delta TP − PCM peak. > 1.5 dB = suspect.")
                        }
                    }
                    if let err = loudnessError {
                        Text(err).font(.caption2).foregroundStyle(.red).lineLimit(1)
                    }
                }
                Button {
                    runAnalysis()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Reanalyze loudness")
            } else {
                // Non analysé
                if let err = loudnessError {
                    Text(err).font(.caption2).foregroundStyle(.red).lineLimit(1)
                }
                Button {
                    runAnalysis()
                } label: {
                    Label("Analyser LUFS", systemImage: "waveform.badge.magnifyingglass")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Measure integrated loudness (EBU R128)")
            }
        }
    }

    // MARK: - BPM

    /// Sauvegarde le BPM saisi (override persisté). Champ vide = efface
    /// l'override, retour aux valeurs Velvet/ShowBuddy.
    private func commitBPM() {
        let cleaned = bpmText.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty {
            appState.setTempoOverride(nil, for: track)
        } else if let bpm = Double(cleaned), bpm >= 40, bpm <= 240 {
            appState.setTempoOverride(bpm, for: track)
            bpmText = String(format: "%.0f", bpm)
        } else {
            // Saisie invalide : on réaffiche la valeur effective.
            bpmText = appState.effectiveTempo(for: track).map { String(format: "%.0f", $0) } ?? ""
        }
        releaseTextFocus()
    }

    /// Détection automatique : analyse d'énergie + autocorrélation des
    /// onsets. Résultat injecté dans le champ et sauvegardé comme override.
    private func detectBPM() {
        guard let url = appState.resolvedAudioURL(for: track) else { return }
        isDetectingBPM = true
        Task {
            let bpm = await BPMDetector.detect(url: url)
            isDetectingBPM = false
            if let bpm {
                bpmText = String(format: "%.0f", bpm)
                appState.setTempoOverride(bpm.rounded(), for: track)
            }
        }
    }

    private func runAnalysis() {
        isAnalyzingLoudness = true
        loudnessError = nil
        Task {
            do {
                try await appState.analyzeLoudness(for: track)
            } catch {
                loudnessError = error.localizedDescription
            }
            isAnalyzingLoudness = false
        }
    }

    private func loudnessTint(_ lufs: Double) -> Color {
        if lufs > -9  { return .red }
        if lufs > -14 { return .orange }
        if lufs > -18 { return .green }
        return .secondary
    }

    private var editorPrompterPreview: some View {
        let scale: CGFloat = 0.65
        let logicalW = Self.iPadPreviewLogicalSize.width
        let logicalH = Self.iPadPreviewLogicalSize.height
        let displayW = logicalW * scale
        let displayH = logicalH * scale

        return PrompterPreviewView(
            title: track.name ?? "Untitled",
            currentMemoTitle: activeMemoForPlayhead?.shortName,
            currentMemoText: memoDisplayText(activeMemoForPlayhead),
            nextMemoText: memoDisplayText(nextMemoForPlayhead),
            remainingTime: Self.timecode(max(0, duration - editorPlayhead)),
            playbackState: RemotePlaybackState(editorPlaybackState),
            audioURL: appState.resolvedAudioURL(for: track),
            duration: duration,
            currentPosition: editorPlayhead,
            timelineMemos: waveformMemos,
            palette: appState.prompterTheme.palette
        )
        .frame(width: logicalW, height: logicalH)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: displayW, height: displayH, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: EditorChrome.panelRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: EditorChrome.panelRadius, style: .continuous)
                .strokeBorder(EditorChrome.panelStroke, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 9)
    }

    @ViewBuilder
    private var selectedMemoPanel: some View {
        let displayH = Self.iPadPreviewLogicalSize.height * 0.65

        Group {
            if editableMemos.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.alignleft")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No Memo")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .editorPanelChrome()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 12) {
                            let activeID = activeMemoForPlayhead?.id
                            ForEach(editableMemos.indices, id: \.self) { index in
                                let memo = editableMemos[index]
                                let isSelected = memo.id == primarySelectedMemoID
                                let isActive = memo.id == activeID
                                memoPanelCard(index: index, isSelected: isSelected, isActive: isActive)
                                    .id(memo.id)
                                if index < editableMemos.count - 1 {
                                    insertBetweenButton(afterIndex: index)
                                }
                            }
                        }
                        .padding(14)
                    }
                    // Scroll automatique to le mémo at la position d'écoute —
                    // suit la lecture et tout seek dans la timeline.
                    .onChange(of: activeMemoForPlayhead?.id) { _, newID in
                        guard let newID else { return }
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(newID, anchor: .center)
                        }
                    }
                }
                .editorPanelChrome()
            }
        }
        .frame(maxWidth: .infinity)
            .frame(height: displayH)
            .animation(.snappy(duration: 0.18), value: primarySelectedMemoID)
            .animation(.snappy(duration: 0.18), value: activeMemoForPlayhead?.id)
    }

    private func midiMenu(index: Int, hasMidi: Bool) -> some View {
        Menu {
            Button("None") { editableMemos[index].startMidiEventID = nil }
            if !appState.maestroMidiEvents().isEmpty {
                Divider()
                ForEach(appState.maestroMidiEvents()) { event in
                    let name = event.name ?? "MidiEvent \(event.midiEventID)"
                    Button(name) { editableMemos[index].startMidiEventID = event.midiEventID }
                }
            }
        } label: {
            Image(systemName: "light.cylindrical.ceiling.fill")
                .font(.caption)
                .foregroundStyle(hasMidi ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tertiary))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(hasMidi ? "MaestroDMX assigned: click to change" : "Assign a MaestroDMX Event")
    }

    /// Petit bouton "+" entre deux cartes : insère un mémo at mi-chemin
    /// temporel entre la fin du mémo du dessus et le début du suivant.
    @ViewBuilder
    private func insertBetweenButton(afterIndex index: Int) -> some View {
        Button {
            insertMemoBetween(index: index)
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Insert a memo between these two memos")
    }

    /// Insère un nouveau mémo entre editableMemos[index] et le suivant.
    /// Position : milieu de l'intervalle entre la fin du premier et le
    /// début du second ; durée bornée at l'espace disponible (min 1 s).
    private func insertMemoBetween(index: Int) {
        guard editableMemos.indices.contains(index),
              editableMemos.indices.contains(index + 1) else { return }
        let prev = editableMemos[index]
        let next = editableMemos[index + 1]
        let prevEnd = min(prev.memoTime + prev.memoLength, next.memoTime)
        let gap = max(0, next.memoTime - prevEnd)
        let newTime = prevEnd + gap / 2
        let newLength = max(1, min(5, next.memoTime - newTime))
        let lightShowID = appState.lightShows(for: track).first?.lightShowID
        let memo = EditableMemo(
            lightShowID: lightShowID,
            shortName: "New memo",
            memo: "",
            memoTime: min(duration, max(0, newTime)),
            memoLength: newLength
        )
        editableMemos.insert(memo, at: index + 1)
        selectMemo(memo.id, extending: false)
    }

    @ViewBuilder
    private func memoPanelCard(index: Int, isSelected: Bool, isActive: Bool) -> some View {
        let hasMidi = editableMemos[index].startMidiEventID != nil
        HStack(spacing: 8) {
            // Poignée "aller at ce mémo" : large cible cliquable sur toute la
            // hauteur de la carte — les champs texte avalent les clics, il
            // fallait une zone dédiée. Jaune = at la position d'écoute.
            Button {
                selectMemo(editableMemos[index].id, extending: false)
                appState.seek(track: track, to: editableMemos[index].memoTime)
                releaseTextFocus()
            } label: {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isActive
                          ? VelvetPalette.nowPlayingYellow
                          : (isSelected ? EditorChrome.selectedStroke.opacity(0.80) : Color.secondary.opacity(0.35)))
                    .frame(width: isSelected || isActive ? 11 : 8)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Cue playback to this memo")

            memoPanelCardContent(index: index, hasMidi: hasMidi,
                                 isEditing: editingMemoCardID == editableMemos[index].id)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: EditorChrome.cardRadius, style: .continuous)
                .fill(cardFillColor(isSelected: isSelected, isActive: isActive,
                                    isEditing: editingMemoCardID == editableMemos[index].id))
        )
        .overlay {
            // Rouge = carte en édition (double-clic), jaune = at la position
            // d'écoute, bleu = sélectionnée. L'édition prime sur le reste.
            RoundedRectangle(cornerRadius: EditorChrome.cardRadius, style: .continuous)
                .stroke(
                    cardStrokeColor(isSelected: isSelected, isActive: isActive,
                                    isEditing: editingMemoCardID == editableMemos[index].id),
                    lineWidth: editingMemoCardID == editableMemos[index].id || isActive || isSelected ? 2.2 : 1
                )
        }
        .shadow(
            color: cardShadowColor(isSelected: isSelected, isActive: isActive,
                                   isEditing: editingMemoCardID == editableMemos[index].id),
            radius: isSelected || isActive || editingMemoCardID == editableMemos[index].id ? 13 : 5,
            x: 0,
            y: isSelected || isActive || editingMemoCardID == editableMemos[index].id ? 6 : 2
        )
        .animation(.snappy(duration: 0.18), value: isSelected)
        .animation(.snappy(duration: 0.18), value: isActive)
        .animation(.snappy(duration: 0.18), value: editingMemoCardID)
        .contentShape(Rectangle())
        // L'ordre compte : count:2 déclaré avant count:1 for que SwiftUI
        // lui donne la priorité (même pattern que les tuiles setlist).
        .onTapGesture(count: 2) {
            selectMemo(editableMemos[index].id, extending: false)
            editingMemoCardID = editableMemos[index].id
        }
        .onTapGesture {
            // Simple clic : sélection + playhead calé. Sort du mode édition
            // d'une éventuelle autre carte.
            if editingMemoCardID != editableMemos[index].id {
                editingMemoCardID = nil
                releaseTextFocus()
            }
            selectMemo(editableMemos[index].id, extending: false)
            appState.seek(track: track, to: editableMemos[index].memoTime)
        }
    }

    private func cardFillColor(isSelected: Bool, isActive: Bool, isEditing: Bool) -> Color {
        if isEditing { return VSColor.danger.opacity(0.13) }
        if isActive { return VelvetPalette.nowPlayingYellow.opacity(0.18) }
        if isSelected { return VelvetPalette.goldLight.opacity(0.13) }
        return EditorChrome.inactiveFill
    }

    private func cardStrokeColor(isSelected: Bool, isActive: Bool, isEditing: Bool) -> Color {
        if isEditing { return VSColor.danger }
        if isActive { return VelvetPalette.nowPlayingYellow }
        if isSelected { return EditorChrome.selectedStroke }
        return EditorChrome.subtleStroke
    }

    private func cardShadowColor(isSelected: Bool, isActive: Bool, isEditing: Bool) -> Color {
        if isEditing { return VSColor.danger.opacity(0.20) }
        if isActive { return VelvetPalette.nowPlayingYellow.opacity(0.22) }
        if isSelected { return EditorChrome.selectedGlow }
        return .black.opacity(0.09)
    }

    @ViewBuilder
    private func memoPanelCardContent(index: Int, hasMidi: Bool, isEditing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                if isEditing {
                    TextField("Title", text: $editableMemos[index].shortName)
                        .font(.system(size: 13, weight: .semibold))
                        .textFieldStyle(.plain)
                } else {
                    Text(editableMemos[index].shortName.isEmpty ? "Untitled" : editableMemos[index].shortName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }
                Spacer(minLength: 0)
                Text(Self.timecodeSeconds(editableMemos[index].memoTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                midiMenu(index: index, hasMidi: hasMidi)
                Button {
                    selectMemo(editableMemos[index].id, extending: false)
                    isConfirmingMemoDelete = true
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Delete this memo (confirmation required)")
            }
            if isEditing {
                TextEditor(text: $editableMemos[index].memo)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 54, maxHeight: 160)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(7)
                    .background(
                        RoundedRectangle(cornerRadius: EditorChrome.cardRadius, style: .continuous)
                            .fill(Color.primary.opacity(0.045))
                    )
            } else {
                Text(editableMemos[index].memo.isEmpty ? "—" : editableMemos[index].memo)
                    .font(.system(size: 13))
                    .foregroundStyle(editableMemos[index].memo.isEmpty ? .tertiary : .primary)
                    .lineLimit(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
            }
        }
    }

    private var activeMemoForPlayhead: EditableMemo? {
        let position = editorPlayhead
        return editableMemos
            .sorted { $0.memoTime < $1.memoTime }
            .filter { memo in
                let end = memo.memoTime + memo.memoLength
                return memo.memoTime <= position && position <= end
            }
            .last
    }

    private var nextMemoForPlayhead: EditableMemo? {
        let position = editorPlayhead
        return editableMemos
            .sorted { $0.memoTime < $1.memoTime }
            .first { $0.memoTime > position }
    }

    private func memoDisplayText(_ memo: EditableMemo?) -> String? {
        guard let memo else { return nil }
        let text = memo.memo.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
        let title = memo.shortName.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private var waveformOverview: some View {
        // Le waveform de l'éditeur affiche le fichier complet
        // (currentPosition / duration absolus), pas la fenêtre trimée :
        // on a besoin de voir ce qui se passe AVANT trimStart et APRÈS
        // trimEnd for pouvoir les déplacer.
        //
        // Le GeometryReader doit être at l'EXTÉRIEUR du ScrollView
        // horizontal — sinon il s'effondre at 0 de large (la ScrollView
        // accorde toute la largeur demandée au contenu, le GR n'a donc
        // pas de référence).
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { outer in
                let baseWidth = max(outer.size.width, 1)
                let contentWidth = baseWidth * CGFloat(zoom)
                ScrollView(.horizontal, showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.black.opacity(0.11))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                            }
                            .frame(width: contentWidth, height: 150)
                            .padding(.top, Self.trimBadgeHeight)

                        WaveformTimelineView(
                            audioURL: appState.resolvedAudioURL(for: track),
                            duration: duration,
                            currentPosition: editorPlayhead,
                            memos: [],
                            displayMode: .waveformOnly,
                            showsModePicker: false,
                            palette: .standard
                        )
                        .frame(width: contentWidth, height: 150)
                        .padding(.top, Self.trimBadgeHeight)

                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .frame(width: contentWidth, height: 150)
                            .padding(.top, Self.trimBadgeHeight)
                            .gesture(timelineSeekGesture(width: contentWidth))
                            // Clic dans une zone vide → désélectionne tous les mémos.
                            .onTapGesture {
                                selectedMemoIDs = []
                                primarySelectedMemoID = nil
                            }

                        ForEach(editableMemos) { memo in
                            memoBlock(memo, width: contentWidth)
                                .padding(.top, Self.trimBadgeHeight)
                        }

                        trimHandle(
                            time: editingTrimStart,
                            color: .green,
                            label: "Start",
                            contentWidth: contentWidth,
                            dragOrigin: $trimDragStartOrigin,
                            onCommit: commitTrimEdits
                        )

                        trimHandle(
                            time: effectiveEditingTrimEnd,
                            color: .red,
                            label: "End",
                            contentWidth: contentWidth,
                            dragOrigin: $trimDragEndOrigin,
                            onCommit: commitTrimEdits
                        )

                        ForEach(cuePoints) { cue in
                            cuePointMarker(cue, contentWidth: contentWidth)
                                .padding(.top, Self.trimBadgeHeight)
                        }
                        ForEach(midiCues) { cue in
                            midiCueMarker(cue, contentWidth: contentWidth)
                                .padding(.top, Self.trimBadgeHeight)
                        }
                        ForEach(oscCues) { cue in
                            oscCueMarker(cue, contentWidth: contentWidth)
                                .padding(.top, Self.trimBadgeHeight)
                        }
                    }
                    .frame(
                        width: contentWidth,
                        height: 150 + Self.trimBadgeHeight,
                        alignment: .topLeading
                    )
                }
            }
            .frame(height: 150 + Self.trimBadgeHeight + 10)
            .padding(12)
            .editorPanelChrome(radius: 16)
            trimZoomControls
        }
    }

    /// Hauteur réservée au-dessus de la waveform for que les badges
    /// "Start / End" des handles ne soient pas clippés par le ScrollView.
    private static let trimBadgeHeight: CGFloat = 24

    /// Contrôles de timeline : actions visibles, puis résumé trim compact.
    private var trimZoomControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "minus.magnifyingglass")
                        .foregroundStyle(.secondary)
                    Slider(value: $zoom, in: 1...16, step: 0.25)
                        .frame(width: 220)
                    Image(systemName: "plus.magnifyingglass")
                        .foregroundStyle(.secondary)
                    Text("\(Int(zoom * 100)) %")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.quaternary.opacity(0.58), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button {
                    addMemoAtPlayhead()
                } label: {
                    Label("Add Memo", systemImage: "plus.rectangle.on.rectangle")
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .fixedSize()

                Button {
                    isShowingLyricsImport = true
                } label: {
                    Label("Import Lyrics", systemImage: "text.quote")
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .fixedSize()

                Button {
                    addCuePointAtPlayhead()
                } label: {
                    Label("Cue Point", systemImage: "flag.fill")
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .tint(.orange)
                .fixedSize()

                Button {
                    guard !appState.midiEventsByID.isEmpty else { return }
                    isAddingMidiCue = true
                } label: {
                    Label("Cue MIDI", systemImage: "pianokeys")
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .tint(.purple)
                .fixedSize()
                .disabled(appState.midiEventsByID.isEmpty)
                .help(appState.midiEventsByID.isEmpty
                      ? "Create a MIDI event in Settings → Velvet MIDI Library first"
                      : "Add a MIDI cue at the playhead position")

                Button {
                    isAddingOscCue = true
                } label: {
                    Label("Cue OSC", systemImage: "dot.radiowaves.left.and.right")
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .tint(.teal)
                .fixedSize()
                .help("Add an OSC cue at the playhead position")

                // BPM : éditable (override persisté) + détection automatique.
                HStack(spacing: 6) {
                    Text("BPM")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    TextField("—", text: $bpmText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12).monospacedDigit())
                        .frame(width: 52)
                        .multilineTextAlignment(.center)
                        .onSubmit { commitBPM() }
                    if isDetectingBPM {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Auto") { detectBPM() }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                            .help("Detect BPM automatically (audio file analysis)")
                    }
                }

                // Genre : bouton pastille + nom, ouvre un popover de sélection/création.
                genreButton

                Spacer(minLength: 0)
            }
            .padding(11)
            .editorFloatingChrome(radius: EditorChrome.controlRadius)
            inlineTrimSummary
        }
    }

    @ViewBuilder
    private var genreButton: some View {
        let currentGenre = appState.concertGenre(for: track)
        let velvetGenre = appState.velvetTrack(for: track)?.genre ?? ""
        let isCustom = !velvetGenre.isEmpty
            && ConcertGenre.allCases.allSatisfy { !velvetGenre.lowercased().contains($0.rawValue) || $0 == .other }
            && appState.customGenreColors[velvetGenre.lowercased().trimmingCharacters(in: .whitespaces)] != nil
        let displayName: String = {
            if isCustom { return velvetGenre.trimmingCharacters(in: .whitespaces) }
            return velvetGenre.isEmpty ? currentGenre.label : currentGenre.label
        }()
        let dotColor = appState.color(for: track)

        Button {
            isShowingGenrePopover = true
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 9, height: 9)
                Text(displayName.isEmpty ? "Genre" : displayName)
                    .font(.caption.bold())
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .popover(isPresented: $isShowingGenrePopover, arrowEdge: .bottom) {
            GenrePickerPopover(track: track, appState: appState, isPresented: $isShowingGenrePopover)
        }
    }

    /// Summary inline (une seule ligne) : Start · End · Duration réelle.
    private var inlineTrimSummary: some View {
        HStack(spacing: 18) {
            inlineSummaryItem(color: .green, title: "Start", time: editingTrimStart)
            inlineSummaryItem(
                color: .red,
                title: "End",
                time: effectiveEditingTrimEnd,
                hint: editingTrimEnd == 0 ? "end of file" : nil
            )
            inlineSummaryItem(
                color: .accentColor,
                title: "Duration",
                time: max(0, effectiveEditingTrimEnd - editingTrimStart)
            )
        }
    }

    @ViewBuilder
    private func inlineSummaryItem(
        color: Color,
        title: String,
        time: TimeInterval,
        hint: String? = nil
    ) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(Self.timecodeSeconds(time))
                .font(.callout.monospacedDigit())
            if let hint {
                Text("(\(hint))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize()
    }

    /// Identité d'une borne, for aiguiller le drag sans comparer des
    /// valeurs `Color` (fragile).
    private enum TrimHandleKind { case start, end }

    /// Rend le focus clavier at la fenêtre. Appelé sur les interactions
    /// hors texte (seek waveform, boutons transport) for que la barre
    /// espace reprenne immédiatement le contrôle play/pause après une
    /// édition dans le panneau de mémos.
    private func releaseTextFocus() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func timelineSeekGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // Déplacement visuel du playhead pendant le drag.
                let ratio = min(1, max(0, value.location.x / max(width, 1)))
                seekDragPosition = Double(ratio) * duration
            }
            .onEnded { value in
                defer { seekDragPosition = nil }
                releaseTextFocus()
                let ratio = min(1, max(0, value.location.x / max(width, 1)))
                let position = Double(ratio) * duration
                // Seek musical : utilise le comportement configuré dans AppState.
                appState.seek(track: track, to: position)
            }
    }

    /// Ligne verticale draggable représentant une borne de trim. Hitbox
    /// élargi (24 pt) for rester confortable même at 1600 %, et drag
    /// gesture dans la coordinate space nommée du contenu for ne pas
    /// être perturbé par le scroll horizontal.
    @ViewBuilder
    private func trimHandle(
        time: TimeInterval,
        color: Color,
        label: String,
        contentWidth: CGFloat,
        dragOrigin: Binding<TimeInterval?>,
        onCommit: @escaping () -> Void
    ) -> some View {
        let x = CGFloat(min(1, max(0, time / duration))) * contentWidth
        let kind: TrimHandleKind = (color == .green) ? .start : .end
        VStack(spacing: 0) {
            Text("\(label) \(Self.timecodeSeconds(time))")
                .font(.caption2.monospacedDigit().bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.9), in: Capsule())
                .foregroundStyle(.white)
                .fixedSize()
                .frame(height: Self.trimBadgeHeight)
            Rectangle()
                .fill(color)
                .frame(width: 2, height: 150)
        }
        .frame(width: 24, height: 150 + Self.trimBadgeHeight, alignment: .top)
        .contentShape(Rectangle())
        .offset(x: x - 12, y: 0)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let origin = dragOrigin.wrappedValue ?? time
                    dragOrigin.wrappedValue = origin
                    let deltaSeconds = Double(value.translation.width / max(contentWidth, 1)) * duration
                    let new = origin + deltaSeconds
                    switch kind {
                    case .start:
                        editingTrimStart = clampedTrimStart(new)
                    case .end:
                        editingTrimEnd = clampedTrimEnd(new)
                    }
                }
                .onEnded { _ in
                    dragOrigin.wrappedValue = nil
                    onCommit()
                }
        )
        .help(label)
    }

    private func clampedTrimStart(_ candidate: TimeInterval) -> TimeInterval {
        let upper = editingTrimEnd > 0 ? editingTrimEnd : duration
        return max(0, min(candidate, max(0, upper - 0.05)))
    }

    private func clampedTrimEnd(_ candidate: TimeInterval) -> TimeInterval {
        return max(editingTrimStart + 0.05, min(candidate, duration))
    }

    // MARK: - Cue Points

    private static func cuePointColor(_ name: String?) -> Color {
        switch name {
        case "blue":   return .blue
        case "green":  return .green
        case "red":    return .red
        case "purple": return .purple
        default:       return .orange
        }
    }

    private func addCuePointAtPlayhead() {
        let t = min(duration, max(0, editorPlayhead))
        let index = cuePoints.count + 1
        let cue = CuePoint(name: "Cue \(index)", time: t)
        cuePoints.append(cue)
        selectedCuePointID = cue.id
    }

    @ViewBuilder
    private func cuePointMarker(_ cue: CuePoint, contentWidth: CGFloat) -> some View {
        let x = xPosition(cue.time, width: contentWidth)
        let color = Self.cuePointColor(cue.colorName)
        let isSelected = cue.id == selectedCuePointID
        let isDragging = cuePointDragOrigins[cue.id] != nil
        let lineWidth: CGFloat = isSelected ? 2.5 : 1.5
        let totalHeight: CGFloat = 150 + Self.trimBadgeHeight

        // Hitbox de 24 pt centré sur la ligne, avec badge au-dessus via overlay.
        // Cette architecture garantit que DragGesture capture correctement les
        // events sans dépendre d'un offset calculé dans un overlay parent.
        ZStack(alignment: .top) {
            // Badge nom + timecode si drag en cours
            VStack(spacing: 1) {
                HStack(spacing: 3) {
                    Image(systemName: "flag.fill").font(.system(size: 8))
                    Text(cue.name).font(.caption2.bold()).lineLimit(1)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(color.opacity(isSelected ? 1 : 0.82), in: Capsule())
                .foregroundStyle(.white)
                .fixedSize()

                if isDragging, let t = draggingCueTime[cue.id] {
                    Text(Self.timecodeSeconds(t))
                        .font(.system(size: 9).monospacedDigit().bold())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.black.opacity(0.75), in: Capsule())
                        .foregroundStyle(.white)
                        .fixedSize()
                        .transition(.opacity)
                }
            }
            .frame(height: Self.trimBadgeHeight, alignment: .bottom)

            // Ligne verticale pointillée
            Canvas { ctx, size in
                let dash: CGFloat = isSelected ? 5 : 4
                let gap: CGFloat = isSelected ? 2 : 3
                var y: CGFloat = Self.trimBadgeHeight
                while y < size.height {
                    ctx.fill(
                        Path(CGRect(x: (size.width - lineWidth) / 2,
                                    y: y,
                                    width: lineWidth,
                                    height: min(dash, size.height - y))),
                        with: .color(color.opacity(isSelected ? 1 : 0.65))
                    )
                    y += dash + gap
                }
            }
            .frame(width: 24, height: totalHeight)
            .allowsHitTesting(false)
        }
        .frame(width: 24, height: totalHeight, alignment: .top)
        .contentShape(Rectangle())
        .offset(x: x - 12, y: 0)
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    selectedCuePointID = cue.id
                    let origin = cuePointDragOrigins[cue.id] ?? cue.time
                    if cuePointDragOrigins[cue.id] == nil {
                        cuePointDragOrigins[cue.id] = origin
                    }
                    let delta = Double(value.translation.width / max(contentWidth, 1)) * duration
                    let newTime = min(duration, max(0, origin + delta))
                    draggingCueTime[cue.id] = newTime
                    if let i = cuePoints.firstIndex(where: { $0.id == cue.id }) {
                        cuePoints[i].time = newTime
                    }
                }
                .onEnded { _ in
                    cuePointDragOrigins[cue.id] = nil
                    draggingCueTime[cue.id] = nil
                }
        )
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                selectedCuePointID = cue.id
                editingCuePoint = cuePoints.first(where: { $0.id == cue.id })
            }
        )
        .simultaneousGesture(
            TapGesture(count: 1).onEnded {
                selectedCuePointID = cue.id
            }
        )
        .help("\(cue.name) — \(Self.timecodeSeconds(cue.time)) — drag to move, double-click to edit")
        .animation(.easeOut(duration: 0.08), value: isDragging)
    }

    // MARK: - Cues MIDI timeline

    @ViewBuilder
    private func midiCueMarker(_ cue: TimelineMidiCue, contentWidth: CGFloat) -> some View {
        let x = xPosition(cue.time, width: contentWidth)
        let eventName = appState.midiEventsByID[cue.midiEventID]?.name ?? "?"
        let displayLabel = cue.label.isEmpty ? eventName : cue.label
        let color = Self.midiCueColor(cue.colorName)
        let totalHeight: CGFloat = 150 + Self.trimBadgeHeight

        ZStack(alignment: .top) {
            // Badge
            HStack(spacing: 3) {
                Image(systemName: "pianokeys").font(.system(size: 7))
                Text(displayLabel).font(.caption2.bold()).lineLimit(1)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.9), in: Capsule())
            .foregroundStyle(.white)
            .fixedSize()
            .frame(height: Self.trimBadgeHeight, alignment: .bottom)

            // Ligne verticale pleine (distingue des CuePoints pointillés)
            Rectangle()
                .fill(color.opacity(0.75))
                .frame(width: 2, height: totalHeight)
                .offset(y: Self.trimBadgeHeight)
                .allowsHitTesting(false)
        }
        .frame(width: 24, height: totalHeight, alignment: .top)
        .contentShape(Rectangle())
        .offset(x: x - 12, y: 0)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { editingMidiCue = cue }
        )
        .help("\(displayLabel) — \(Self.timecodeSeconds(cue.time)) — double-click to edit")
    }

    private static func midiCueColor(_ name: String?) -> Color {
        switch name {
        case "orange": return .orange
        case "blue":   return .blue
        case "green":  return .green
        case "red":    return .red
        default:       return .purple
        }
    }

    // MARK: - Cues OSC timeline

    @ViewBuilder
    private func oscCueMarker(_ cue: TimelineOscCue, contentWidth: CGFloat) -> some View {
        let x = xPosition(cue.time, width: contentWidth)
        let eventName: String = {
            if let eid = cue.oscEventID, let event = appState.oscEventsByID[eid] {
                return event.name
            }
            return "(no event)"
        }()
        let displayLabel = cue.label.isEmpty ? eventName : cue.label
        let color = Self.oscCueColor(cue.colorName)
        let totalHeight: CGFloat = 150 + Self.trimBadgeHeight

        ZStack(alignment: .top) {
            HStack(spacing: 3) {
                Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 7))
                Text(displayLabel).font(.caption2.bold()).lineLimit(1)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.9), in: Capsule())
            .foregroundStyle(.white)
            .fixedSize()
            .frame(height: Self.trimBadgeHeight, alignment: .bottom)

            // Ligne verticale en tirets (distingue MIDI=plein / Cue=pointillés / OSC=tirets).
            Rectangle()
                .fill(color.opacity(0.75))
                .frame(width: 2, height: totalHeight)
                .offset(y: Self.trimBadgeHeight)
                .allowsHitTesting(false)
        }
        .frame(width: 24, height: totalHeight, alignment: .top)
        .contentShape(Rectangle())
        .offset(x: x - 12, y: 0)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { editingOscCue = cue }
        )
        .help("\(displayLabel) — \(Self.timecodeSeconds(cue.time)) — double-click to edit")
    }

    private static func oscCueColor(_ name: String?) -> Color {
        switch name {
        case "purple": return .purple
        case "blue":   return .blue
        case "green":  return .green
        case "orange": return .orange
        case "red":    return .red
        default:       return .teal
        }
    }

    private func commitTrimEdits() {
        editingTrimStart = clampedTrimStart(editingTrimStart)
        if editingTrimEnd > 0 {
            editingTrimEnd = clampedTrimEnd(editingTrimEnd)
        }
        // Si on revient sur les valeurs fallback ShowBuddy (ou 0/0), on
        // supprime le trim Velvet for ne pas masquer le fallback. Sinon
        // on enregistre les nouvelles bornes.
        let show = appState.lightShows(for: track).first
        let fallbackStart = max(0, min(show?.trimStart ?? 0, duration))
        let fallbackEnd: TimeInterval = {
            let e = show?.trimEnd ?? 0
            return (e > fallbackStart && e <= duration) ? e : 0
        }()
        let matchesFallback = abs(editingTrimStart - fallbackStart) < 0.0005
            && abs(editingTrimEnd - fallbackEnd) < 0.0005
        if matchesFallback {
            appState.clearTrim(for: track)
        } else {
            appState.setTrim(
                for: track,
                start: editingTrimStart,
                end: editingTrimEnd
            )
        }
        initialTrimStart = editingTrimStart
        initialTrimEnd = editingTrimEnd
    }

    private var waveformMemos: [WaveformTimelineMemo] {
        editableMemos.map { memo in
            WaveformTimelineMemo(
                id: memo.id.uuidString,
                title: memo.displayTitle,
                startTime: memo.memoTime,
                duration: memo.memoLength,
                hasMidi: memo.hasMidi
            )
        }
    }

    private func memoBlock(_ memo: EditableMemo, width: CGFloat) -> some View {
        let isSelected = selectedMemoIDs.contains(memo.id)
        let isPrimary  = primarySelectedMemoID == memo.id
        let multiCount = selectedMemoIDs.count
        let x = xPosition(memo.memoTime, width: width)
        let blockWidth = max(44, CGFloat(memo.memoLength / duration) * width)
        // 3 lanes max : avec la waveform at 150 px, la 4e lane (y=144+28)
        // sortait du cadre et les mémos du bas étaient quasi invisibles.
        let y = CGFloat(abs(memo.id.hashValue % 3)) * 36 + 42

        return HStack(spacing: 0) {
            Text(memo.displayTitle)
                .font(.caption.bold())
                .lineLimit(1)
                .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Poignée de redimensionnement : visuel 8 pt + zone de prise
            // élargie at 20 pt (dont débordement at droite du bloc) pour
            // qu'on l'attrape facilement même sur un mémo court.
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(.white.opacity(isSelected ? 0.95 : 0.78))
                .frame(width: 7)
                .overlay {
                    Image(systemName: "chevron.compact.left.chevron.compact.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.black.opacity(0.55))
                }
                .frame(width: 20, alignment: .center)
                .contentShape(Rectangle())
                .gesture(resizeGesture(for: memo, width: width))
                .help("Stretch / shorten")
        }
        .frame(width: blockWidth, height: isSelected ? 32 : 30)
        .foregroundStyle(.white)
        .background(
            clipFill(for: memo, isSelected: isSelected),
            in: RoundedRectangle(cornerRadius: EditorChrome.clipRadius, style: .continuous)
        )
        .overlay {
            // Contour de sélection : 2.5 pt for le mémo primaire,
            // 1.5 pt for les mémos secondaires de la sélection.
            RoundedRectangle(cornerRadius: EditorChrome.clipRadius, style: .continuous)
                .strokeBorder(clipStrokeColor(for: memo, isSelected: isSelected),
                              lineWidth: isPrimary ? 2.6 : (isSelected ? 2.0 : 1))

            // Badge compteur sur le mémo primaire quand plusieurs sont sélectionnés.
            if isPrimary && multiCount > 1 {
                Text("\(multiCount)")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.9), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(3)
                    .allowsHitTesting(false)
            }
        }
        .shadow(
            color: isSelected ? EditorChrome.selectedGlow : .black.opacity(0.16),
            radius: isSelected ? 12 : 5,
            x: 0,
            y: isSelected ? 5 : 2
        )
        .offset(x: x, y: y)
        .animation(.snappy(duration: 0.18), value: isSelected)
        .animation(.snappy(duration: 0.18), value: activeMemoForPlayhead?.id)
        .gesture(dragGesture(for: memo, width: width))
        .onTapGesture {
            // ⌘ ou ⇧ = bascule le mémo dans/hors de la sélection.
            let flags = NSEvent.modifierFlags
            let extending = flags.contains(.command) || flags.contains(.shift)
            selectMemo(memo.id, extending: extending)
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                selectMemo(memo.id, extending: false)
                isShowingMemoEditor = true
            }
        )
        .contextMenu {
            Button {
                selectMemo(memo.id, extending: false)
                isShowingMemoEditor = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button { duplicateMemo(memo) } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }

            Divider()

            if multiCount > 1 && isSelected {
                Button(role: .destructive) {
                    isConfirmingMemoDelete = true
                } label: {
                    Label("Delete \(multiCount) memos", systemImage: "trash")
                }
            } else {
                Button(role: .destructive) {
                    selectMemo(memo.id, extending: false)
                    isConfirmingMemoDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .help(memo.hasMidi ? "Memo with MIDI event: ⌘-click for multiple selection"
                           : "Memo: ⌘-click for multiple selection")
    }

    private func clipFill(for memo: EditableMemo, isSelected: Bool) -> LinearGradient {
        let base = clipBaseColor(for: memo)
        return LinearGradient(
            colors: [
                base.opacity(isSelected ? 1.0 : 0.90),
                base.opacity(isSelected ? 0.78 : 0.60)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func clipStrokeColor(for memo: EditableMemo, isSelected: Bool) -> Color {
        if isSelected { return EditorChrome.selectedStroke }
        if activeMemoForPlayhead?.id == memo.id { return VelvetPalette.nowPlayingYellow.opacity(0.95) }
        return .white.opacity(0.22)
    }

    private func clipBaseColor(for memo: EditableMemo) -> Color {
        if activeMemoForPlayhead?.id == memo.id { return VelvetPalette.nowPlayingYellow }
        if memo.hasMidi { return .orange }
        return VSColor.interactive
    }

    /// Sélectionne un mémo.
    /// - `extending = true` : bascule ce mémo dans/hors la sélection (⌘-clic / ⇧-clic).
    /// - `extending = false` : sélection exclusive de ce mémo.
    private func selectMemo(_ id: EditableMemo.ID, extending: Bool) {
        if extending {
            if selectedMemoIDs.contains(id) {
                selectedMemoIDs.remove(id)
                if primarySelectedMemoID == id {
                    primarySelectedMemoID = selectedMemoIDs.first
                }
            } else {
                selectedMemoIDs.insert(id)
                primarySelectedMemoID = id
            }
        } else {
            selectedMemoIDs = [id]
            primarySelectedMemoID = id
        }
    }

    /// Duplique un mémo, décalé de +2 secondes, et sélectionne le doublon.
    private func duplicateMemo(_ memo: EditableMemo) {
        let lightShowID = appState.lightShows(for: track).first?.lightShowID
        let newTime = min(duration, memo.memoTime + 2)
        var copy = EditableMemo(
            lightShowID: lightShowID,
            shortName: memo.shortName,
            memo: memo.memo,
            memoTime: newTime,
            memoLength: memo.memoLength
        )
        copy.startMidiEventID = memo.startMidiEventID
        editableMemos.append(copy)
        selectMemo(copy.id, extending: false)
    }

    private func addMemoAtPlayhead() {
        let lightShowID = appState.lightShows(for: track).first?.lightShowID
        let start = min(duration, max(0, editorPlayhead))
        let memo = EditableMemo(
            lightShowID: lightShowID,
            shortName: "New memo",
            memo: "",
            memoTime: start,
            memoLength: 5
        )
        editableMemos.append(memo)
        selectMemo(memo.id, extending: false)
    }

    private func dragGesture(for memo: EditableMemo, width: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                // Si le mémo glissé n'est pas dans la sélection, on bascule
                // en sélection exclusive sur lui (comportement Endder/Keynote).
                if !selectedMemoIDs.contains(memo.id) {
                    selectMemo(memo.id, extending: false)
                }

                // Initialise les origines de TOUS les mémos sélectionnés
                // at leur position courante (une seule fois par drag).
                for id in selectedMemoIDs {
                    if dragOrigins[id] == nil,
                       let idx = editableMemos.firstIndex(where: { $0.id == id }) {
                        dragOrigins[id] = editableMemos[idx].memoTime
                    }
                }

                let deltaSeconds = Double(value.translation.width / max(width, 1)) * duration

                // Déplace tous les mémos sélectionnés du même delta.
                for id in selectedMemoIDs {
                    guard let origin = dragOrigins[id],
                          let idx = editableMemos.firstIndex(where: { $0.id == id }) else { continue }
                    editableMemos[idx].memoTime = min(duration, max(0, origin + deltaSeconds))
                }

                primarySelectedMemoID = memo.id
            }
            .onEnded { _ in
                for id in selectedMemoIDs { dragOrigins[id] = nil }
            }
    }

    private func resizeGesture(for memo: EditableMemo, width: CGFloat) -> some Gesture {
        // minimumDistance: 0 — la prise répond dès le premier pixel, sans
        // seuil qui donnait l'impression de "rater" la poignée.
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let index = editableMemos.firstIndex(where: { $0.id == memo.id }) else { return }
                let origin = resizeOrigins[memo.id] ?? editableMemos[index].memoLength
                if resizeOrigins[memo.id] == nil {
                    resizeOrigins[memo.id] = origin
                    // Sélection une seule fois au début du drag : la muter à
                    // chaque tick provoquait des re-rendus en cascade — c'est
                    // ce qui rendait le redimensionnement saccadé.
                    selectMemo(memo.id, extending: false)
                }
                let deltaSeconds = Double(value.translation.width / max(width, 1)) * duration
                let maxLength = max(1, duration - editableMemos[index].memoTime)
                editableMemos[index].memoLength = min(maxLength, max(1, origin + deltaSeconds))
            }
            .onEnded { _ in
                resizeOrigins[memo.id] = nil
            }
    }

    private func xPosition(_ seconds: Double, width: CGFloat) -> CGFloat {
        CGFloat(min(1, max(0, seconds / duration))) * width
    }

    private static func timecode(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let m = Int(clamped) / 60
        let s = Int(clamped) % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Format simple for le trim affiché at l'écran : lisible en répétition,
    /// sans précision inutile au millième.
    static func timecodeSeconds(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let rounded = Int(clamped.rounded())
        let m = rounded / 60
        let s = rounded % 60
        return String(format: "%d:%02d", m, s)
    }

    private static func volumeDBString(_ value: Double) -> String {
        let clamped = VelvetTrackVolume.clamped(value)
        if abs(clamped) < 0.05 { return "0 dB" }
        let sign = clamped > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", clamped)) dB"
            .replacingOccurrences(of: ".", with: ",")
    }
}

struct MemoInspectorView: View {
    @Binding var memo: EditableMemo
    let appState: AppState
    /// Appelé quand l'utilisateur confirme la suppression depuis cet inspecteur.
    /// Le parent doit retirer le mémo de `editableMemos` et fermer la sheet.
    var onDelete: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false

    private var selectedMidiEvent: MidiEvent? {
        appState.midiEvent(id: memo.startMidiEventID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Memo", systemImage: "text.quote")
                    .font(.headline)
                Spacer()
                if onDelete != nil {
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .foregroundStyle(VSColor.danger)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete this memo")
                }
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            TextField("Title", text: $memo.shortName)
                .textFieldStyle(.roundedBorder)

            TextField("Text", text: $memo.memo, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(8...18)

            VStack(alignment: .leading, spacing: 10) {
                Label("MaestroDMX", systemImage: "light.cylindrical.ceiling.fill")
                    .font(.headline)

                if appState.maestroMidiEvents().isEmpty {
                    Text("No MaestroDMX event found in the database.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Action", selection: midiEventSelection) {
                        Text("None").tag(Int64(0))
                        ForEach(appState.maestroMidiEvents()) { event in
                            Text(event.name ?? "MidiEvent \(event.midiEventID)")
                                .tag(event.midiEventID)
                        }
                    }

                    HStack {
                        Button {
                            if let selectedMidiEvent {
                                appState.dispatch(event: selectedMidiEvent)
                            }
                        } label: {
                            Label("Send Now", systemImage: "paperplane.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedMidiEvent == nil)

                        if let selectedMidiEvent {
                            Text(selectedMidiEvent.name ?? "MidiEvent \(selectedMidiEvent.midiEventID)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(14)
            .editorPanelChrome(radius: 12)

            Spacer(minLength: 0)
        }
        .padding(20)
        .confirmationDialog(
            "Delete this memo?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete?()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private var midiEventSelection: Binding<Int64> {
        Binding(
            get: { memo.startMidiEventID ?? 0 },
            set: { memo.startMidiEventID = $0 == 0 ? nil : $0 }
        )
    }
}

// MARK: - Inspecteur de cue point

// MARK: - Cue Point Inspector

struct CuePointInspectorSheet: View {
    let cuePoint: CuePoint
    let duration: Double
    var onSave: (CuePoint) -> Void
    var onDelete: (CuePoint.ID) -> Void

    @State private var name: String
    @State private var time: Double
    @State private var colorName: String

    init(cuePoint: CuePoint, duration: Double,
         onSave: @escaping (CuePoint) -> Void,
         onDelete: @escaping (CuePoint.ID) -> Void) {
        self.cuePoint = cuePoint
        self.duration = duration
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: cuePoint.name)
        _time = State(initialValue: cuePoint.time)
        _colorName = State(initialValue: cuePoint.colorName ?? "orange")
    }

    private static func timecodeSeconds(_ s: Double) -> String {
        let clamped = max(0, s)
        let m = Int(clamped) / 60
        let sec = Int(clamped) % 60
        return String(format: "%d:%02d", m, sec)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Edit Cue Point", systemImage: "flag.fill")
                    .font(.headline)
                    .foregroundStyle(colorFor(colorName))
                Spacer()
            }

            // Nom
            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.caption.bold()).foregroundStyle(.secondary)
                TextField("Cue point name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(14)
            .editorPanelChrome(radius: 12)

            // Timecode éditable
            VStack(alignment: .leading, spacing: 8) {
                Text("Position").font(.caption.bold()).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Slider(value: $time, in: 0...max(1, duration))
                        .tint(colorFor(colorName))
                    Text(Self.timecodeSeconds(time))
                        .font(.callout.monospacedDigit())
                        .frame(width: 52, alignment: .trailing)
                }
            }
            .padding(14)
            .editorPanelChrome(radius: 12)

            // Color
            VStack(alignment: .leading, spacing: 8) {
                Text("Color").font(.caption.bold()).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(CuePointColor.allCases, id: \.rawValue) { c in
                        Circle()
                            .fill(colorFor(c.rawValue))
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle().stroke(Color.primary.opacity(0.3), lineWidth: colorName == c.rawValue ? 2 : 0)
                                    .padding(-3)
                            )
                            .onTapGesture { colorName = c.rawValue }
                    }
                }
            }
            .padding(14)
            .editorPanelChrome(radius: 12)

            HStack {
                Button(role: .destructive) {
                    onDelete(cuePoint.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Cancel") { onSave(cuePoint) }   // ferme sans changement
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered)

                Button("Save") {
                    var updated = cuePoint
                    updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if updated.name.isEmpty { updated.name = "Cue Point" }
                    updated.time = time
                    updated.colorName = colorName
                    onSave(updated)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
    }

    private func colorFor(_ name: String) -> Color {
        switch name {
        case "blue":   return .blue
        case "green":  return .green
        case "red":    return .red
        case "purple": return .purple
        default:       return .orange
        }
    }
}

// MARK: - Inspecteur de cue MIDI

struct MidiCueInspectorSheet: View {
    let appState: AppState
    var midiCue: TimelineMidiCue
    let duration: Double
    let onSave:   (TimelineMidiCue) -> Void
    let onDelete: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: TimelineMidiCue

    private var sortedEvents: [MidiEvent] {
        appState.midiEventsByID.values
            .filter { !appState.isArchived($0.midiEventID)
                || $0.midiEventID == draft.midiEventID }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    private var maestroEvents: [MidiEvent] {
        sortedEvents.filter { event in
            appState.midiMessages(for: event).contains { $0.maestroDescription != nil }
        }
    }
    private var otherEvents: [MidiEvent] {
        let maestroIDs = Set(maestroEvents.map(\.midiEventID))
        return sortedEvents.filter { !maestroIDs.contains($0.midiEventID) }
    }

    private func pickerLabel(for event: MidiEvent) -> String {
        let msgs = appState.midiMessages(for: event)
        guard let first = msgs.first else { return (event.name ?? "Event \(event.midiEventID)") + " — no message" }
        let t: String
        switch first.message {
        case 144: t = "Note On"
        case 128: t = "Note Off"
        case 176: t = "CC"
        case 192: t = "PC"
        default:  t = "0x\(String(first.message ?? 0, radix: 16).uppercased())"
        }
        let ch = (first.channel ?? 0) + 1
        let extra = msgs.count > 1 ? " +\(msgs.count - 1)" : ""
        return (event.name ?? "Event \(event.midiEventID)") + " — \(t) ch\(ch)\(extra)"
    }

    private var eventBinding: Binding<Int64> {
        Binding(
            get: { draft.midiEventID },
            set: { draft.midiEventID = $0 }
        )
    }

    init(appState: AppState, midiCue: TimelineMidiCue, duration: Double,
         onSave: @escaping (TimelineMidiCue) -> Void,
         onDelete: @escaping (UUID) -> Void) {
        self.appState  = appState
        self.midiCue   = midiCue
        self.duration  = duration
        self.onSave    = onSave
        self.onDelete  = onDelete
        _draft = State(initialValue: midiCue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cue MIDI")
                .font(.headline)

            // Event MIDI
            VStack(alignment: .leading, spacing: 8) {
                Text("Event").font(.caption.bold()).foregroundStyle(.secondary)
                Picker("Event", selection: eventBinding) {
                    if !maestroEvents.isEmpty {
                        Section("Recommended: MaestroDMX (Note On ch16)") {
                            ForEach(maestroEvents) { event in
                                Text(pickerLabel(for: event)).tag(event.midiEventID)
                            }
                        }
                    }
                    if !otherEvents.isEmpty {
                        Section("Other MIDI Events") {
                            ForEach(otherEvents) { event in
                                Text(pickerLabel(for: event)).tag(event.midiEventID)
                            }
                        }
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .foregroundStyle(.primary)
                if let event = appState.midiEventsByID[draft.midiEventID] {
                    let msgs = appState.midiMessages(for: event)
                    if msgs.isEmpty {
                        Text("⚠ No MIDI message: this event will not send anything")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(msgs) { msg in
                                Text(msg.humanDescription)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(msg.maestroDescription != nil ? Color.accentColor : .secondary)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .editorPanelChrome(radius: 12)

            // Label affiché sur le marqueur
            VStack(alignment: .leading, spacing: 6) {
                Text("Label (optional)").font(.caption.bold()).foregroundStyle(.secondary)
                TextField("Leave empty to show the event name", text: $draft.label)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(14)
            .editorPanelChrome(radius: 12)

            // Position
            VStack(alignment: .leading, spacing: 8) {
                Text("Position").font(.caption.bold()).foregroundStyle(.secondary)
                HStack {
                    Slider(value: $draft.time, in: 0...max(1, duration))
                    Text(TimelineEditorView.timecodeSeconds(draft.time))
                        .font(.caption.monospacedDigit())
                        .frame(width: 56, alignment: .trailing)
                }
            }
            .padding(14)
            .editorPanelChrome(radius: 12)

            // Color
            VStack(alignment: .leading, spacing: 8) {
                Text("Color").font(.caption.bold()).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(["purple", "blue", "green", "orange", "red"], id: \.self) { c in
                        let color: Color = c == "purple" ? .purple : c == "blue" ? .blue
                            : c == "green" ? .green : c == "orange" ? .orange : .red
                        Circle()
                            .fill(color)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle().stroke(Color.primary, lineWidth:
                                    (draft.colorName ?? "purple") == c ? 2 : 0)
                            )
                            .onTapGesture {
                                draft.colorName = c == "purple" ? nil : c
                            }
                    }
                }
            }
            .padding(14)
            .editorPanelChrome(radius: 12)

            Spacer()

            HStack {
                Button(role: .destructive) {
                    onDelete(draft.id)
                    dismiss()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(sortedEvents.isEmpty)
            }
        }
        .padding(22)
    }
}

// MARK: - Inspecteur de cue OSC
//
// Calque la logique de `MidiCueInspectorSheet` : on ne saisit pas le payload
// inline, on choisit un OscEvent nommé dans la Velvet OSC Library. La gestion
// de la library (création/édition/suppression) vit dans MidiSettingsView.

struct OscCueInspectorSheet: View {
    let appState: AppState
    var oscCue: TimelineOscCue
    let duration: Double
    let onSave:   (TimelineOscCue) -> Void
    let onDelete: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: TimelineOscCue
    @State private var testFeedback: String? = nil

    init(appState: AppState, oscCue: TimelineOscCue, duration: Double,
         onSave: @escaping (TimelineOscCue) -> Void,
         onDelete: @escaping (UUID) -> Void) {
        self.appState = appState
        self.oscCue   = oscCue
        self.duration = duration
        self.onSave   = onSave
        self.onDelete = onDelete
        // Si la cue n'a pas encore d'event lié et qu'il existe au moins un
        // event dans la library, présélectionne le premier — évite un état
        // « Aucun » dès l'ouverture du sheet sur une cue toute neuve.
        var initial = oscCue
        if initial.oscEventID == nil {
            initial.oscEventID = appState.sortedOscEvents.first?.oscEventID
        }
        _draft = State(initialValue: initial)
    }

    private var events: [OscEvent] { appState.sortedOscEvents }

    private var groupedByCategory: [(String, [OscEvent])] {
        let groups = Dictionary(grouping: events) { $0.category ?? "Other" }
        return groups
            .map { ($0.key, $0.value.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    private func pickerLabel(for event: OscEvent) -> String {
        let v = event.value?.displayValue ?? "no value"
        return "\(event.name) — \(event.address) \(v)"
    }

    private var eventBinding: Binding<UUID?> {
        Binding(
            get: { draft.oscEventID },
            set: { draft.oscEventID = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cue OSC").font(.headline)

            // OSC Event picker
            VStack(alignment: .leading, spacing: 8) {
                Text("OSC Event").font(.caption.bold()).foregroundStyle(.secondary)
                if events.isEmpty {
                    Text("No OSC event yet. Create one in Settings → OSC Library before placing a cue.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Picker("OSC Event", selection: eventBinding) {
                        Text("None").tag(UUID?.none)
                        ForEach(groupedByCategory, id: \.0) { (category, list) in
                            Section(category) {
                                ForEach(list) { event in
                                    Text(pickerLabel(for: event)).tag(Optional(event.oscEventID))
                                }
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                if let eid = draft.oscEventID, let event = appState.oscEventsByID[eid] {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("→ \(event.host):\(event.port)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("\(event.address)  \(event.value?.displayValue ?? "(no value)")")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .editorPanelChrome(radius: 12)

            // Label override
            VStack(alignment: .leading, spacing: 6) {
                Text("Label (optional)").font(.caption.bold()).foregroundStyle(.secondary)
                TextField("Leave empty to show the event name", text: $draft.label)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(14)
            .editorPanelChrome(radius: 12)

            // Position
            VStack(alignment: .leading, spacing: 8) {
                Text("Position").font(.caption.bold()).foregroundStyle(.secondary)
                HStack {
                    Slider(value: $draft.time, in: 0...max(1, duration))
                    Text(TimelineEditorView.timecodeSeconds(draft.time))
                        .font(.caption.monospacedDigit())
                        .frame(width: 56, alignment: .trailing)
                }
            }
            .padding(14)
            .editorPanelChrome(radius: 12)

            // Color
            VStack(alignment: .leading, spacing: 8) {
                Text("Color").font(.caption.bold()).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(["teal", "blue", "green", "orange", "red", "purple"], id: \.self) { c in
                        let color: Color = c == "teal" ? .teal : c == "blue" ? .blue
                            : c == "green" ? .green : c == "orange" ? .orange
                            : c == "red" ? .red : .purple
                        Circle()
                            .fill(color)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle().stroke(Color.primary, lineWidth:
                                    (draft.colorName ?? "teal") == c ? 2 : 0)
                            )
                            .onTapGesture {
                                draft.colorName = c == "teal" ? nil : c
                            }
                    }
                }
            }
            .padding(14)
            .editorPanelChrome(radius: 12)

            // Test
            HStack {
                Button {
                    if let eid = draft.oscEventID, let event = appState.oscEventsByID[eid] {
                        appState.dispatch(oscEvent: event)
                        testFeedback = "Test sent: \(event.name)"
                    } else {
                        testFeedback = "Select an OSC event first"
                    }
                } label: {
                    Label("Send Test", systemImage: "paperplane")
                }
                .buttonStyle(.bordered)
                .disabled(draft.oscEventID == nil)
                if let testFeedback {
                    Text(testFeedback).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack {
                Button(role: .destructive) {
                    onDelete(draft.id)
                    dismiss()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.oscEventID == nil)
            }
        }
        .padding(22)
    }
}

// MARK: - Import paroles

enum LyricsImportMode: String, CaseIterable, Identifiable {
    case replace = "Replace Existing Memos"
    case append = "Append"

    var id: String { rawValue }
}

enum LyricsSectionKind {
    case intro
    case couplet
    case preChorus
    case refrain
    case bridge
    case solo
    case `break`
    case coda
    case outro
    case unknown

    var weight: Double {
        switch self {
        case .intro: return 0.6
        case .couplet: return 1.2
        case .preChorus: return 0.6
        case .refrain: return 1.0
        case .bridge: return 0.8
        case .solo: return 1.0
        case .break: return 0.6
        case .coda: return 0.6
        case .outro: return 0.6
        case .unknown: return 1.0
        }
    }
}

struct LyricsMemoDraft: Identifiable, Hashable {
    let id = UUID()
    var shortName: String
    var memo: String
    var memoTime: Double
    var memoLength: Double
    var sectionKind: LyricsSectionKind

    var endTime: Double {
        memoTime + memoLength
    }
}

struct LyricsMemoImport {
    static func drafts(
        from lyrics: String,
        duration: Double,
        trimStart: Double,
        trimEnd: Double,
        existingMemos: [EditableMemo],
        mode: LyricsImportMode
    ) -> [LyricsMemoDraft] {
        let parsed = parse(lyrics)
        guard !parsed.isEmpty else { return [] }

        let safeDuration = max(1, duration)
        let baseStart = max(0, min(trimStart, safeDuration))
        let baseEnd = trimEnd > baseStart && trimEnd <= safeDuration ? trimEnd : safeDuration
        let existingEnd = existingMemos.map { $0.memoTime + $0.memoLength }.max() ?? baseStart
        let scheduleStart = mode == .append && !existingMemos.isEmpty
            ? min(max(baseStart, existingEnd), max(baseStart, baseEnd - 1))
            : baseStart
        let scheduleEnd = max(scheduleStart + 1, baseEnd)
        let totalWeight = max(0.1, parsed.reduce(0) { $0 + $1.kind.weight })

        var cursor = scheduleStart
        return parsed.enumerated().map { index, block in
            let isLast = index == parsed.count - 1
            let segmentLength = isLast
                ? max(1, scheduleEnd - cursor)
                : max(1, (scheduleEnd - scheduleStart) * block.kind.weight / totalWeight)
            let draft = LyricsMemoDraft(
                shortName: block.shortName,
                memo: block.memo,
                memoTime: cursor,
                memoLength: segmentLength,
                sectionKind: block.kind
            )
            cursor += segmentLength
            return draft
        }
    }

    static func editableMemos(
        from drafts: [LyricsMemoDraft],
        lightShowID: Int64?
    ) -> [EditableMemo] {
        drafts.map { draft in
            EditableMemo(
                lightShowID: lightShowID,
                shortName: draft.shortName,
                memo: draft.memo,
                memoTime: draft.memoTime,
                memoLength: draft.memoLength
            )
        }
    }

    private static func parse(_ lyrics: String) -> [(shortName: String, memo: String, kind: LyricsSectionKind)] {
        let normalizedText = lyrics
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var blocks: [[String]] = []
        var current: [String] = []

        for rawLine in normalizedText.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if !current.isEmpty {
                    blocks.append(current)
                    current.removeAll()
                }
            } else if markerKind(for: line) != nil, !current.isEmpty {
                blocks.append(current)
                current = [line]
            } else {
                current.append(rawLine)
            }
        }
        if !current.isEmpty {
            blocks.append(current)
        }

        return blocks.enumerated().map { index, lines in
            guard let first = lines.first else {
                return ("Memo \(index + 1)", "", .unknown)
            }
            if let marker = markerKind(for: first) {
                let title = cleanedMarkerTitle(first)
                let memo = lines.dropFirst().joined(separator: "\n")
                return (title, memo, marker)
            }
            return ("Memo \(index + 1)", lines.joined(separator: "\n"), .unknown)
        }
    }

    private static func markerKind(for line: String) -> LyricsSectionKind? {
        let marker = cleanedMarkerTitle(line)
        let normalized = marker
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let base = normalized.components(separatedBy: ":").first ?? normalized
        let words = base.split(separator: " ").map(String.init)
        let head = words.first ?? base

        if base == "intro" { return .intro }
        if base == "refrain" || base == "chorus" || base == "hook" || head == "chorus" || head == "hook" {
            return .refrain
        }
        if base == "pre-refrain" || base == "pre refrain" || base == "pre-chorus" || base == "pre chorus"
            || base.hasPrefix("pre-refrain ") || base.hasPrefix("pre refrain ")
            || base.hasPrefix("pre-chorus ") || base.hasPrefix("pre chorus ") {
            return .preChorus
        }
        if base == "post-chorus" || base == "post chorus"
            || base.hasPrefix("post-chorus ") || base.hasPrefix("post chorus ") {
            return .refrain
        }
        if base == "pont" || base == "bridge" || head == "bridge" { return .bridge }
        if base == "solo" || base == "instrumental" || head == "solo" || head == "instrumental" { return .solo }
        if base == "break" || base == "interlude" || base == "drop" || head == "break" || head == "interlude" {
            return .break
        }
        if base == "coda" || base == "tag" { return .coda }
        if base == "outro" { return .outro }
        if base == "couplet" || base == "verse" { return .couplet }
        if head == "couplet" || head == "verse" {
            return .couplet
        }
        return nil
    }

    private static func cleanedMarkerTitle(_ line: String) -> String {
        var marker = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if marker.hasPrefix("[") && marker.hasSuffix("]") && marker.count > 2 {
            marker.removeFirst()
            marker.removeLast()
        }
        if marker.hasSuffix(":") {
            marker.removeLast()
        }
        return marker.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct LyricsImportSheet: View {
    let track: AudioFile
    let appState: AppState
    let existingMemos: [EditableMemo]
    let initialImportMode: LyricsImportMode
    let onImport: ([EditableMemo]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var lyricsText = ""
    @State private var importMode: LyricsImportMode
    @State private var drafts: [LyricsMemoDraft] = []

    init(
        track: AudioFile,
        appState: AppState,
        existingMemos: [EditableMemo],
        initialImportMode: LyricsImportMode,
        onImport: @escaping ([EditableMemo]) -> Void
    ) {
        self.track = track
        self.appState = appState
        self.existingMemos = existingMemos
        self.initialImportMode = initialImportMode
        self.onImport = onImport
        _importMode = State(initialValue: existingMemos.isEmpty ? .replace : initialImportMode)
    }

    private var duration: Double {
        if appState.currentlyLoadedTrack?.audioFileID == track.audioFileID,
           appState.audioEngine.totalDuration > 0 {
            return max(1, appState.audioEngine.totalDuration)
        }
        return max(1, track.lengthSecs ?? 1)
    }

    private var hasExistingMemos: Bool {
        !existingMemos.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Import Lyrics")
                        .font(.title2.bold())
                    Text(track.name ?? "Untitled")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import") {
                    importDrafts()
                }
                .buttonStyle(.borderedProminent)
                .disabled(drafts.isEmpty)
            }

            if hasExistingMemos {
                Picker("Existing Memos", selection: $importMode) {
                    ForEach(LyricsImportMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            TextEditor(text: $lyricsText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 220)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: EditorChrome.panelRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: EditorChrome.panelRadius, style: .continuous)
                        .strokeBorder(EditorChrome.panelStroke, lineWidth: 1)
                }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Preview: \(drafts.count) memos generated")
                    .font(.headline)
                if drafts.isEmpty {
                    ContentUnavailableView(
                        "Paste lyrics",
                        systemImage: "text.quote",
                        description: Text("Each block separated by a blank line will become a memo.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 140)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach($drafts) { $draft in
                                HStack(spacing: 12) {
                                    TextField("Title", text: $draft.shortName)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 180)
                                    Text(Self.timeRange(draft))
                                        .font(.callout.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    Text(draft.memo.isEmpty ? "—" : draft.memo)
                                        .lineLimit(2)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(12)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: EditorChrome.cardRadius, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: EditorChrome.cardRadius, style: .continuous)
                                        .strokeBorder(EditorChrome.subtleStroke, lineWidth: 1)
                                }
                                .shadow(color: .black.opacity(0.07), radius: 5, x: 0, y: 2)
                            }
                        }
                    }
                    .frame(minHeight: 160, maxHeight: 260)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 620)
        .onAppear { regenerateDrafts() }
        .onChange(of: lyricsText) { _, _ in regenerateDrafts() }
        .onChange(of: importMode) { _, _ in regenerateDrafts() }
    }

    private func regenerateDrafts() {
        let trim = appState.effectiveTrim(for: track)
        drafts = LyricsMemoImport.drafts(
            from: lyricsText,
            duration: duration,
            trimStart: trim.start,
            trimEnd: trim.end,
            existingMemos: existingMemos,
            mode: importMode
        )
    }

    private func importDrafts() {
        let lightShowID = appState.lightShows(for: track).first?.lightShowID
        let generated = LyricsMemoImport.editableMemos(from: drafts, lightShowID: lightShowID)
        switch importMode {
        case .replace:
            onImport(generated)
        case .append:
            onImport((existingMemos + generated).sorted { $0.memoTime < $1.memoTime })
        }
        dismiss()
    }

    private static func timeRange(_ draft: LyricsMemoDraft) -> String {
        "\(timecode(draft.memoTime)) → \(timecode(draft.endTime))"
    }

    private static func timecode(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let m = Int(clamped) / 60
        let s = Int(clamped) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Détection automatique de BPM

/// Détecteur de tempo léger : enveloppe d'énergie (hop 512 samples) →
/// flux d'onsets (différences positives) → autocorrélation sur la plage
/// 60–190 BPM, avec correction d'octave to la plage usuelle 90–180.
/// Lecture par blocs de 64k frames — pas de chargement du fichier entier.
enum BPMDetector {
    static func detect(url: URL) async -> Double? {
        await Task.detached(priority: .userInitiated) { () -> Double? in
            guard let file = try? AVAudioFile(forReading: url) else { return nil }
            let format = file.processingFormat
            let sampleRate = format.sampleRate
            guard sampleRate > 0, file.length > 0 else { return nil }

            let hop = 512
            let envRate = sampleRate / Double(hop)
            var envelope: [Float] = []
            envelope.reserveCapacity(Int(file.length) / hop + 1)

            let chunkFrames: AVAudioFrameCount = 65536
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else { return nil }

            var carry: [Float] = []
            while file.framePosition < file.length {
                buffer.frameLength = 0
                guard (try? file.read(into: buffer, frameCount: chunkFrames)) != nil,
                      buffer.frameLength > 0,
                      let channels = buffer.floatChannelData else { break }
                let frames = Int(buffer.frameLength)
                let channelCount = Int(format.channelCount)
                // Mono mix du bloc, en continuant le reliquat du bloc précédent.
                var mono = carry
                mono.reserveCapacity(carry.count + frames)
                for i in 0..<frames {
                    var s: Float = 0
                    for c in 0..<channelCount { s += channels[c][i] }
                    mono.append(s / Float(channelCount))
                }
                // RMS par hop complet ; le reste part dans carry.
                var idx = 0
                while idx + hop <= mono.count {
                    var sum: Float = 0
                    for j in idx..<(idx + hop) { sum += mono[j] * mono[j] }
                    envelope.append(sqrt(sum / Float(hop)))
                    idx += hop
                }
                carry = Array(mono[idx...])
            }

            guard envelope.count > Int(envRate * 10) else { return nil }  // < 10 s : trop court

            // Flux d'onsets : différences positives, légèrement lissées.
            var flux = [Float](repeating: 0, count: envelope.count)
            for i in 1..<envelope.count {
                flux[i] = max(0, envelope[i] - envelope[i - 1])
            }

            // Autocorrélation sur la plage de BPM.
            func score(forBPM bpm: Double) -> Double {
                let lag = Int((60.0 / bpm) * envRate)
                guard lag > 1, lag < flux.count / 2 else { return 0 }
                var s: Double = 0
                for i in 0..<(flux.count - lag) {
                    s += Double(flux[i] * flux[i + lag])
                }
                return s / Double(flux.count - lag)
            }

            var bestBPM: Double = 0
            var bestScore: Double = 0
            var bpm = 60.0
            while bpm <= 190.0 {
                let s = score(forBPM: bpm)
                if s > bestScore { bestScore = s; bestBPM = bpm }
                bpm += 0.5
            }
            guard bestBPM > 0 else { return nil }

            // Correction d'octave : préférer 90–180 si le double/la moitié
            // obtient un score comparable.
            if bestBPM < 90 {
                let doubled = bestBPM * 2
                if doubled <= 190, score(forBPM: doubled) >= bestScore * 0.7 {
                    bestBPM = doubled
                }
            } else if bestBPM > 180 {
                let halved = bestBPM / 2
                if score(forBPM: halved) >= bestScore * 0.7 {
                    bestBPM = halved
                }
            }
            return bestBPM
        }.value
    }
}

// MARK: - Popover sélection / création de genre

private struct GenrePickerPopover: View {
    let track: AudioFile
    let appState: AppState
    @Binding var isPresented: Bool

    @State private var isCreating = false
    @State private var newGenreName: String = ""
    @State private var newGenreColor: Color = .cyan
    @FocusState private var newNameFocused: Bool

    private static let predefined: [ConcertGenre] = ConcertGenre.allCases.filter { $0 != .all }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Genres prédéfinis ──────────────────────────────
            Text("Genres")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 4)

            ForEach(Self.predefined) { genre in
                genreRow(
                    name: genre.label,
                    color: appState.color(for: genre),
                    isSelected: isSelected(rawValue: genre.rawValue)
                ) {
                    appState.setGenre(genre.rawValue, for: track)
                    isPresented = false
                }
            }

            // ── Genres personnalisés ───────────────────────────
            if !appState.customGenreNames.isEmpty {
                Divider().padding(.vertical, 4)
                Text("Mes genres")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)

                ForEach(appState.customGenreNames, id: \.self) { name in
                    HStack(spacing: 0) {
                        genreRow(
                            name: name.capitalized,
                            color: appState.colorForCustomGenre(name),
                            isSelected: isSelected(rawValue: name)
                        ) {
                            appState.setGenre(name, for: track)
                            isPresented = false
                        }
                        Spacer()
                        Button {
                            appState.deleteCustomGenre(name)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 14)
                    }
                }
            }

            // ── Création nouveau genre ────────────────────────
            Divider().padding(.vertical, 4)

            if isCreating {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Genre name", text: $newGenreName)
                        .textFieldStyle(.roundedBorder)
                        .focused($newNameFocused)
                    ColorPicker("Color", selection: $newGenreColor, supportsOpacity: false)
                    HStack {
                        Button("Cancel") {
                            isCreating = false
                            newGenreName = ""
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Spacer()
                        Button("Create") {
                            let trimmed = newGenreName.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            appState.setCustomGenreColor(newGenreColor, for: trimmed)
                            appState.setGenre(trimmed, for: track)
                            newGenreName = ""
                            isCreating = false
                            isPresented = false
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(newGenreName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            } else {
                Button {
                    isCreating = true
                    newNameFocused = true
                } label: {
                    Label("New Genre...", systemImage: "plus.circle")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .frame(width: 220)
    }

    private func isSelected(rawValue: String) -> Bool {
        guard let velvet = appState.velvetTrack(for: track) else { return false }
        return velvet.genre.lowercased().trimmingCharacters(in: .whitespaces) == rawValue.lowercased()
            || velvet.genre.lowercased().contains(rawValue.lowercased())
    }

    private func genreRow(name: String, color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                Text(name)
                    .font(.callout)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
    }
}
