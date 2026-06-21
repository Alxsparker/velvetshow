//
//  MidiSettingsView.swift
//  VELVET SHOW
//

import SwiftUI
import CoreMIDI
import UniformTypeIdentifiers
import AudioToolbox

// MARK: ───────────────────────────────────────────────────────────
// MARK: MIDI Settings (popover toolbar)
// MARK: ───────────────────────────────────────────────────────────

/// Popover de configuration MIDI déclenché depuis la toolbar.
///
/// Contenu :
///   1) statut du moteur CoreMIDI (prêt ou en erreur),
///   2) picker de la destination MaestroDMX (parmi celles vues par CoreMIDI),
///   3) liste complète des destinations détectées, marquant celle qui
///      est actuellement sélectionnée,
///   4) bouton "Rafraîchir" — utile si tu branches une interface MIDI
///      pendant que l'app tourne (normalement la liste se met at jour
///      toute seule via les notifications CoreMIDI, mais c'est un filet).
struct MidiSettingsView: View {
    @Bindable var appState: AppState

    @State private var trimImportResult:    String? = nil
    @State private var trimFixResult:       String? = nil
    @State private var isShowingTailCleanup = false
    @State private var isAdvancedExpanded   = false
    @State private var isRestCueExpanded    = false

    // MARK: Résumé Rest cue (label fermé du DisclosureGroup)

    private var restCueSceneName: String {
        switch appState.restCueType {
        case .midi:
            guard let id = appState.restCueMidiEventID,
                  let event = appState.midiEventsByID[id] else { return "Aucune" }
            return "\(event.name ?? "Event \(id)") (MIDI)"
        case .osc:
            guard let id = appState.restOscEventID,
                  let event = appState.oscEventsByID[id] else { return "Aucune" }
            return "\(event.name) (OSC)"
        }
    }

    private var isCurrentRestCueUnset: Bool {
        switch appState.restCueType {
        case .midi: return appState.restCueMidiEventID == nil
        case .osc:  return appState.restOscEventID    == nil
        }
    }

    private var restCueDelaySummary: String {
        switch appState.restCueDelaySeconds {
        case 0:  return "Immediate"
        case 1:  return "1 s"
        case 2:  return "2 s"
        default: return "\(Int(appState.restCueDelaySeconds)) s"
        }
    }

    private var restCueTriggerCount: Int {
        [appState.restCueTriggerOnStop,
         appState.restCueTriggerOnNaturalEnd,
         appState.restCueTriggerOnConcertEnd,
         appState.restCueTriggerBetweenTracks].filter { $0 }.count
    }

    private var seekBehaviorCaption: String {
        switch appState.seekBehavior {
        case .raw:
            return "Immediate cut. May create an audio click."
        case .fade:
            return "150 ms fade out → seek → 150 ms fade in. Recommended."
        case .fadeSnapBeat:
            if appState.currentlyLoadedTrack.flatMap({ appState.effectiveTempo(for: $0) }) != nil {
                return "Fondu + alignement automatique au beat le plus proche (BPM connu)."
            } else {
                return "Short fade; BPM is unavailable for this song, snap disabled."
            }
        }
    }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 12) {

            // ── En-tête ─────────────────────────────────────────────
            HStack(spacing: 8) {
                Label("Preferences", systemImage: "gearshape")
                    .font(.headline)
                Spacer()
                Button {
                    appState.midiEngine.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh the MIDI destination list")
            }

            if !appState.midiEngine.isReady {
                Label(
                    appState.midiEngine.lastError ?? "CoreMIDI engine is not initialized",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.red)
                .font(.caption)
            } else {
                Label("CoreMIDI Engine Ready", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }

            Divider()

            // ── Sortie MIDI (ex Destination MaestroDMX) ─────────────
            Text("Sortie MIDI")
                .font(.subheadline.bold())

            if appState.midiEngine.destinations.isEmpty {
                Label(
                    "No MIDI destination detected; connect your USB-MIDI interface, then click Refresh.",
                    systemImage: "cable.connector"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Picker("Destination", selection: $appState.maestroDestinationID) {
                    Text("Aucune").tag(MIDIUniqueID?.none)
                    ForEach(appState.midiEngine.destinations) { dest in
                        Text(dest.displayName).tag(Optional(dest.id))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .foregroundStyle(.primary)
            }

            if appState.maestroDestination == nil {
                Label(
                    "No MIDI output configured; messages will be logged as \"NO DESTINATION\".",
                    systemImage: "exclamationmark.bubble"
                )
                .font(.caption)
                .foregroundStyle(VSColor.warning)
            }

            Divider()

            // ── Avance d'envoi (ex Offset MIDI global) ───────────────
            Text("Avance d'envoi")
                .font(.subheadline.bold())
            Picker("Avance", selection: $appState.midiGlobalOffsetMillis) {
                ForEach(AppState.midiGlobalOffsetChoices, id: \.self) { ms in
                    Text(ms == 0 ? "0 ms (none)" : "\(ms) ms").tag(ms)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .foregroundStyle(.primary)
            Text("Send MIDI cues early to compensate for DMX / fixture latency. Memo positions are not changed.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            // ── Comportement au seek (ex Seek pendant la lecture) ────
            VStack(alignment: .leading, spacing: 6) {
                Text("Seek Behavior")
                    .font(.subheadline.bold())
                Picker("Seek", selection: $appState.seekBehavior) {
                    ForEach(AppState.SeekBehavior.allCases, id: \.self) { b in
                        Text(b.label).tag(b)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(seekBehaviorCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // ── Show Safety ─────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                Text("Show Safety")
                    .font(.subheadline.bold())
                Toggle(isOn: $appState.isSafePlayEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Confirm song changes during playback")
                            .font(.callout)
                        Text(appState.isSafePlayEnabled
                             ? "Double-click required to start a song. If another song is playing, VELVET SHOW asks for confirmation before switching with a fade-out."
                             : "One click starts or stops a song. Useful in preparation, risky during a show.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(VSColor.warning)
            }

            Divider()

            // ── Rest cue (DisclosureGroup) ───────────────────────
            DisclosureGroup(isExpanded: $isRestCueExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Event sent automatically when no song is playing. Choose MIDI or OSC — only one protocol fires at a time.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Toggle("", isOn: $appState.restCueEnabled)
                            .labelsHidden()
                            .tint(Color.accentColor)
                    }

                    // Type selector — MIDI vs OSC, mutuellement exclusif.
                    HStack {
                        Text("Type").font(.callout)
                        Picker("Type", selection: $appState.restCueType) {
                            Text("MIDI").tag(AppState.RestCueType.midi)
                            Text("OSC").tag(AppState.RestCueType.osc)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 200)
                    }

                    // Event picker — change selon le type.
                    HStack {
                        Text("Event").font(.callout)
                        switch appState.restCueType {
                        case .midi:
                            let midiBinding = Binding<Int?>(
                                get: { appState.restCueMidiEventID.map(Int.init) },
                                set: { appState.restCueMidiEventID = $0.map(Int64.init) }
                            )
                            Picker("MIDI Event", selection: midiBinding) {
                                Text("None").tag(Int?.none)
                                ForEach(
                                    appState.midiEventsByID.values
                                        .filter { !appState.isArchived($0.midiEventID)
                                            || appState.restCueMidiEventID == $0.midiEventID }
                                        .sorted { ($0.name ?? "") < ($1.name ?? "") }
                                ) { event in
                                    Text(event.name ?? "Event \(event.midiEventID)")
                                        .tag(Optional(Int(event.midiEventID)))
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .foregroundStyle(.primary)
                            .frame(maxWidth: 240)
                        case .osc:
                            let oscBinding = Binding<UUID?>(
                                get: { appState.restOscEventID },
                                set: { appState.restOscEventID = $0 }
                            )
                            Picker("OSC Event", selection: oscBinding) {
                                Text("None").tag(UUID?.none)
                                ForEach(appState.sortedOscEvents) { event in
                                    Text(event.name).tag(Optional(event.oscEventID))
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .foregroundStyle(.primary)
                            .frame(maxWidth: 240)
                        }
                    }

                    HStack {
                        Text("Delay").font(.callout)
                        Picker("Delay", selection: $appState.restCueDelaySeconds) {
                            Text("Immediate").tag(0.0)
                            Text("1 seconde").tag(1.0)
                            Text("2 secondes").tag(2.0)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .foregroundStyle(.primary)
                        .frame(maxWidth: 140)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Send lors de :").font(.caption.bold()).foregroundStyle(.secondary)
                        Toggle(isOn: $appState.restCueTriggerOnStop) {
                            Text("Stop manuel").font(.callout)
                        }
                        Toggle(isOn: $appState.restCueTriggerOnNaturalEnd) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("End naturelle d'un song").font(.callout)
                                Text("Ignored if a MIDI memo was triggered in the last \(Int(AppState.naturalEndMidiWindowSeconds)) seconds.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Toggle(isOn: $appState.restCueTriggerOnConcertEnd) {
                            Text("End of the Last Song in the Show").font(.callout)
                        }
                        Toggle(isOn: $appState.restCueTriggerBetweenTracks) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Between Two Songs (AUTO SHOW Off)").font(.callout)
                                Text("Sent when the next song is loaded but not started yet.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(!appState.restCueEnabled || isCurrentRestCueUnset)
                }
                .padding(.top, 6)
            } label: {
                // Label fermé : titre + résumé compact
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cue de repos")
                        .font(.subheadline.bold())
                    if !isRestCueExpanded {
                        if appState.restCueEnabled {
                            HStack(spacing: 8) {
                                Text(restCueSceneName)
                                    .foregroundStyle(.primary)
                                Text("·")
                                    .foregroundStyle(.tertiary)
                                Text(restCueDelaySummary)
                                Text("·")
                                    .foregroundStyle(.tertiary)
                                Text("\(restCueTriggerCount) trigger\(restCueTriggerCount != 1 ? "s" : "")")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else {
                            Text("Disabled")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Divider()

            // ── MIDI Library ────────────────────────────────────
            VelvetMidiLibrarySection(appState: appState)

            Divider()

            // ── OSC Library ─────────────────────────────────────
            VelvetOscLibrarySection(appState: appState)

            Divider()

            // ── OSC Test ────────────────────────────────────────
            OscTestSection(appState: appState)

            Divider()

            // ── Demo / First Steps ──────────────────────────────────
            DemoContentSection(appState: appState)

            Divider()

            // ── Credits & Licenses ───────────────────────────────────
            CreditsSection()

            Divider()

            // ── Advanced / Maintenance ─────────────────────────────────
            DisclosureGroup(isExpanded: $isAdvancedExpanded) {
                VStack(alignment: .leading, spacing: 12) {

                    // Nettoyage MIDI
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nettoyage MIDI")
                            .font(.subheadline.bold())
                        Button {
                            isShowingTailCleanup = true
                        } label: {
                            Label("End-of-Song MIDI Memos...", systemImage: "wand.and.sparkles")
                        }
                        .controlSize(.small)
                        Text("Lists MIDI memos triggered in the final seconds of songs (stop cue, Purple Rain...); they can override incoming-song scenes during a crossfade. No change without confirmation.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Detected Destinations (liste technique)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Detected Destinations (\(appState.midiEngine.destinations.count))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if appState.midiEngine.destinations.isEmpty {
                            Text("—")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(appState.midiEngine.destinations) { dest in
                                HStack(spacing: 6) {
                                    Image(systemName:
                                            dest.id == appState.maestroDestinationID
                                            ? "checkmark.circle.fill"
                                            : "circle")
                                        .foregroundStyle(
                                            dest.id == appState.maestroDestinationID
                                            ? Color.accentColor
                                            : .secondary
                                        )
                                    Text(dest.displayName)
                                    Spacer()
                                    Text("ID \(dest.id)")
                                        .monospacedDigit()
                                        .foregroundStyle(.tertiary)
                                }
                                .font(.caption)
                            }
                        }
                    }

                    Divider()

                    // Audio Library
                    MediaLibrarySummarySection(appState: appState)

                    Divider()

                    // Trims ShowBuddy + Correction TrimEnd
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Trims ShowBuddy")
                            .font(.subheadline.bold())
                        Text("Import song starts/endings defined in ShowBuddy. Only songs without Velvet trims are updated; trims you set yourself are not touched.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let result = trimImportResult {
                            Label(result, systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }

                        Button {
                            if let count = presentTrimImportPanel(appState: appState) {
                                trimImportResult = count == 0
                                    ? "No new trim to import."
                                    : "\(count) trim\(count > 1 ? "s" : "") imported\(count > 1 ? "s" : "")."
                            }
                        } label: {
                            Label("Import ShowBuddy Trims...", systemImage: "dial.medium")
                        }
                        .controlSize(.small)

                        Divider()
                            .padding(.vertical, 2)

                        Text("Correction TrimEnd")
                            .font(.subheadline.bold())
                        Text("Rereads ShowBuddy.db and recalculates song endings. Use this if songs stop too early after an import. A backup is created before any change.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let result = trimFixResult {
                            Label(result, systemImage: trimFixResult?.hasPrefix("⚠") == true
                                  ? "exclamationmark.triangle"
                                  : "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(trimFixResult?.hasPrefix("⚠") == true
                                                 ? VSColor.warning : .green)
                        }

                        Button {
                            if let r = presentTrimFixPanel(appState: appState) {
                                if r.fixed == 0 && r.skipped == 0 {
                                    trimFixResult = "No trim to fix."
                                } else if r.skipped > 0 {
                                    trimFixResult = "\(r.fixed) fixed\(r.fixed > 1 ? "s" : "") · ⚠ \(r.skipped) skipped\(r.skipped > 1 ? "s" : "") (unknown duration)"
                                } else {
                                    trimFixResult = "\(r.fixed) trim\(r.fixed > 1 ? "s" : "") fixed\(r.fixed > 1 ? "s" : "")."
                                }
                            }
                        } label: {
                            Label("Corriger les trims ShowBuddy...", systemImage: "waveform.path.ecg")
                        }
                        .controlSize(.small)
                        .tint(VSColor.warning)
                    }
                }
                .padding(.top, 8)
            } label: {
                Label("Advanced / Maintenance", systemImage: "wrench.and.screwdriver")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        } // end ScrollView
        .frame(minWidth: 380, idealWidth: 420)
        .sheet(isPresented: $isShowingTailCleanup) {
            TailMidiCleanupSheet(appState: appState)
        }
    }
}

// MARK: - Nom de note MIDI

private func midiNoteName(_ number: Int) -> String {
    guard number >= 0 && number <= 127 else { return "?" }
    let names = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
    let octave = (number / 12) - 2
    return "\(names[number % 12])\(octave)"
}

// MARK: - Types de messages MIDI (éditeur natif)

private enum MidiMessageType: String, CaseIterable, Identifiable {
    case noteOn        = "Note On"
    case noteOff       = "Note Off"
    case controlChange = "Control Change"
    case programChange = "Program Change"

    var id: String { rawValue }

    var statusByte: Int64 {
        switch self {
        case .noteOn:        return 144
        case .noteOff:       return 128
        case .controlChange: return 176
        case .programChange: return 192
        }
    }

    var hasData2: Bool { self != .programChange }

    var localizedLabel: LocalizedStringKey { LocalizedStringKey(rawValue) }

    var data1Label: LocalizedStringKey {
        switch self {
        case .noteOn, .noteOff: return "Note"
        case .controlChange:    return "CC#"
        case .programChange:    return "Prog"
        }
    }

    var data2Label: LocalizedStringKey {
        switch self {
        case .noteOn, .noteOff: return "Velocity"
        case .controlChange:    return "Valeur"
        case .programChange:    return ""
        }
    }

    static func from(statusByte: Int64?) -> MidiMessageType {
        switch statusByte {
        case 144: return .noteOn
        case 128: return .noteOff
        case 176: return .controlChange
        case 192: return .programChange
        default:  return .noteOn
        }
    }
}

// MARK: - MIDI Library globale

private enum MidiLibraryFilter: String, CaseIterable, Identifiable {
    case all           = "Tous"
    case maestro       = "MaestroDMX"
    case programChange = "PC"
    case unused        = "Unused"
    case duplicates    = "Doublons"
    case velvet        = "Velvet natifs"
    case archived      = "Archived"
    var id: String { rawValue }
    var localizedLabel: LocalizedStringKey { LocalizedStringKey(rawValue) }
}

private struct VelvetMidiLibrarySection: View {
    @Bindable var appState: AppState
    @State private var newEventName       = ""
    @State private var isCreating         = false
    @State private var filter             = MidiLibraryFilter.all
    @State private var showingImport      = false
    @State private var showingMidiImport  = false
    @State private var isExpanded         = false

    private var maestroCount: Int {
        appState.midiEventsByID.values.filter { e in
            appState.midiMessages(for: e).contains { $0.maestroDescription != nil }
        }.count
    }

    private var archivedCount: Int {
        appState.archivedMidiEventIDs.count
    }

    private var allEvents: [MidiEvent] {
        appState.midiEventsByID.values
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    private var duplicateNames: Set<String> {
        var seen = Set<String>(); var dupes = Set<String>()
        for e in allEvents {
            let n = e.name ?? ""
            if seen.contains(n) { dupes.insert(n) } else { seen.insert(n) }
        }
        return dupes
    }

    private func isMaestro(_ e: MidiEvent) -> Bool {
        appState.midiMessages(for: e).contains { $0.maestroDescription != nil }
    }
    private func isPC(_ e: MidiEvent) -> Bool {
        appState.midiMessages(for: e).first?.message == 192
    }

    private var filteredEvents: [MidiEvent] {
        switch filter {
        case .all:           return allEvents
        case .maestro:       return allEvents.filter { isMaestro($0) }
        case .programChange: return allEvents.filter { isPC($0) }
        case .unused:        return allEvents.filter { !appState.midiEventUsage(for: $0.midiEventID).isUsed }
        case .duplicates:    return allEvents.filter { duplicateNames.contains($0.name ?? "") }
        case .velvet:        return allEvents.filter { $0.midiEventID < 0 }
        case .archived:      return allEvents.filter { appState.isArchived($0.midiEventID) }
        }
    }

    private var nativeEvents: [MidiEvent] {
        appState.midiEventsByID.values
            .filter { $0.midiEventID < 0 }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
        VStack(alignment: .leading, spacing: 8) {
            // En-tête actions
            HStack {
                Spacer()
                Menu {
                    Button {
                        showingImport = true
                    } label: {
                        Label("MaestroDMX Show...", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        showingMidiImport = true
                    } label: {
                        Label("Fichier MIDI (.mid)...", systemImage: "doc.badge.arrow.up")
                    }
                    Divider()
                    Button { } label: {
                        Label("Wolfmix... (soon)", systemImage: "sparkles")
                    }
                    .disabled(true)
                    Button { } label: {
                        Label("QLab... (soon)", systemImage: "sparkles")
                    }
                    .disabled(true)
                    Button { } label: {
                        Label("Lightkey... (soon)", systemImage: "sparkles")
                    }
                    .disabled(true)
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down.on.square")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                Button {
                    isCreating = true
                } label: {
                    Label("New Event", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(isCreating)
            }

            Text("\(appState.midiEventsByID.count) events · \(nativeEvents.count) native Velvet")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Filtres
            Picker("Filtre", selection: $filter) {
                ForEach(MidiLibraryFilter.allCases) { f in
                    Text(f.localizedLabel).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // Liste filtrée
            if filteredEvents.isEmpty {
                Text("No event in this category.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(filteredEvents) { event in
                    MidiEventGlobalRow(appState: appState, event: event)
                }
            }

            // Formulaire de création (Velvet natif uniquement)
            if isCreating {
                HStack(spacing: 6) {
                    TextField("Event Name", text: $newEventName)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .onSubmit { commitCreate() }
                    Button("Create") { commitCreate() }
                        .controlSize(.small)
                        .disabled(newEventName.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Cancel") { isCreating = false; newEventName = "" }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
                .padding(.top, 2)
            }
        }
        .padding(.top, 6)
        .sheet(isPresented: $showingImport) {
            MaestroDMXImportSheet(appState: appState)
        }
        .sheet(isPresented: $showingMidiImport) {
            MidiFileImportSheet(appState: appState)
        }
        } label: {
            // Label fermé : titre + résumé compact
            VStack(alignment: .leading, spacing: 3) {
                Text("MIDI Library")
                    .font(.subheadline.bold())
                if !isExpanded {
                    HStack(spacing: 0) {
                        Text("\(appState.midiEventsByID.count) events")
                        if maestroCount > 0 {
                            Text(" • \(maestroCount) MaestroDMX")
                        }
                        if archivedCount > 0 {
                            Text(" • \(archivedCount) archived\(archivedCount > 1 ? "s" : "")")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func commitCreate() {
        let name = newEventName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        appState.createVelvetMidiEvent(name: name)
        newEventName = ""
        isCreating = false
    }
}

// MARK: - Sheet import fichier MIDI standard (.mid)

private struct MidiFileImportSheet: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var report:       AppState.MidiFileImportReport? = nil
    @State private var applied       = false
    @State private var isPickingFile = false
    @State private var parseError:   String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // ── En-tête ─────────────────────────────────────────────
            HStack {
                Label("Import MIDI File", systemImage: "doc.badge.arrow.up")
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Text("Select a .mid / .smf file exported from Ableton, Logic, Cubase, Reaper, QLab... Note On, CC, and Program Change messages are imported as reusable events in the MIDI library. SysEx, Pitch Bend, and MIDI Clock are ignored.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // ── Bouton sélection fichier ─────────────────────────────
            HStack {
                Button {
                    isPickingFile = true
                } label: {
                    Label("Choose a .mid File...", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                if let r = report {
                    Text(r.sourceFileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }

            if let err = parseError {
                Text("⚠ \(err)").font(.caption2).foregroundStyle(.red)
            }

            // ── Rapport scrollable ───────────────────────────────────
            if let r = report {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        reportView(r)
                    }
                    .padding(.trailing, 4)
                }
                .frame(maxHeight: 400)
            }

            Divider()

            // ── Boutons actions (toujours visibles) ─────────────────
            HStack(spacing: 12) {
                if let r = report, !r.newEntries.isEmpty, !applied {
                    Button("Appliquer (\(r.newEntries.count) nouveau\(r.newEntries.count > 1 ? "x" : ""))") {
                        appState.applyMidiFileImport(r)
                        applied = true
                    }
                    .buttonStyle(.borderedProminent)
                }

                if applied {
                    Label("Import Applied", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                }

                Spacer()
            }
        }
        .padding(20)
        .frame(minWidth: 580, idealWidth: 660)
        .fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: [.midi],
            allowsMultipleSelection: false
        ) { result in
            parseError = nil
            switch result {
            case .failure(let err):
                parseError = err.localizedDescription
            case .success(let urls):
                guard let url = urls.first else { return }
                parseMidiFile(url: url)
            }
        }
    }

    // MARK: - Rapport

    @ViewBuilder
    private func reportView(_ r: AppState.MidiFileImportReport) -> some View {
        // Résumé
        HStack(spacing: 16) {
            statBadge("\(r.newEntries.count) nouveau\(r.newEntries.count != 1 ? "x" : "")", color: .green)
            statBadge("\(r.alreadyPresent.count) already present\(r.alreadyPresent.count != 1 ? "s" : "")", color: .secondary)
            if !r.equivalents.isEmpty {
                statBadge("\(r.equivalents.count) already covered\(r.equivalents.count != 1 ? "s" : "")", color: .yellow)
            }
        }

        // Détail
        VStack(alignment: .leading, spacing: 3) {
            ForEach(r.entries) { entry in
                HStack(spacing: 8) {
                    statusIcon(entry.status)
                    Text(entry.suggestedName)
                        .font(.caption)
                        .frame(minWidth: 200, alignment: .leading)
                    Text(entry.fingerprint)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(minWidth: 120, alignment: .leading)
                    if let match = entry.matchedEvent {
                        Text("→ ID \(match.midiEventID) \"\(match.name ?? "?")\"")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        if !r.equivalents.isEmpty {
            Text("ℹ Already covered: an existing event already contains this MIDI message. Nothing created.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: AppState.MidiFileImportReport.EntryStatus) -> some View {
        switch status {
        case .new:           Image(systemName: "plus.circle.fill").foregroundStyle(.green)
        case .alreadyPresent:Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
        case .midiEquivalent:Image(systemName: "equal.circle").foregroundStyle(.yellow)
        }
    }

    @ViewBuilder
    private func statBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color == .secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(color))
    }

    // MARK: - Parsing AudioToolbox

    private func parseMidiFile(url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }

        var sequence: MusicSequence?
        guard NewMusicSequence(&sequence) == noErr, let seq = sequence else {
            parseError = String(localized: "Could not create the MIDI sequence.")
            return
        }
        defer { DisposeMusicSequence(seq) }

        guard MusicSequenceFileLoad(seq, url as CFURL, .midiType, []) == noErr else {
            parseError = String(localized: "Could not read the file. Check that it is a valid MIDI file (.mid).")
            return
        }

        // Collecte (hi, ch, d1, d2) → occurrences
        var counts: [String: (AppState.MidiFileCandidate, Int)] = [:]

        var trackCount: UInt32 = 0
        MusicSequenceGetTrackCount(seq, &trackCount)

        for i in 0..<trackCount {
            var track: MusicTrack?
            guard MusicSequenceGetIndTrack(seq, i, &track) == noErr, let t = track else { continue }

            var iter: MusicEventIterator?
            guard NewMusicEventIterator(t, &iter) == noErr, let it = iter else { continue }
            defer { DisposeMusicEventIterator(it) }

            var hasEvent: DarwinBoolean = false
            MusicEventIteratorHasCurrentEvent(it, &hasEvent)

            while hasEvent.boolValue {
                var ts: MusicTimeStamp = 0
                var type: MusicEventType = 0
                var dataPtr: UnsafeRawPointer?
                var dataSize: UInt32 = 0
                MusicEventIteratorGetEventInfo(it, &ts, &type, &dataPtr, &dataSize)

                if type == kMusicEventType_MIDINoteMessage, let ptr = dataPtr {
                    let msg = ptr.load(as: MIDINoteMessage.self)
                    // Ignorer velocity 0 (= Note Off déguisé)
                    if msg.velocity > 0 {
                        let c = AppState.MidiFileCandidate(
                            statusHighNibble: 0x90,
                            channel:          Int(msg.channel),
                            data1:            Int(msg.note),
                            data2:            Int(msg.velocity),
                            occurrences:      1
                        )
                        let key = "\(0x90)-\(msg.channel)-\(msg.note)-\(msg.velocity)"
                        counts[key] = (c, (counts[key]?.1 ?? 0) + 1)
                    }
                } else if type == kMusicEventType_MIDIChannelMessage, let ptr = dataPtr {
                    let msg  = ptr.load(as: MIDIChannelMessage.self)
                    let hi   = Int(msg.status & 0xF0)
                    let ch   = Int(msg.status & 0x0F)
                    // Garder Note On (0x90), CC (0xB0), PC (0xC0) — ignorer le reste
                    guard [0x90, 0xB0, 0xC0].contains(hi) else {
                        MusicEventIteratorNextEvent(it)
                        MusicEventIteratorHasCurrentEvent(it, &hasEvent)
                        continue
                    }
                    // Note On via MIDIChannelMessage : ignorer vel=0
                    if hi == 0x90 && msg.data2 == 0 {
                        MusicEventIteratorNextEvent(it)
                        MusicEventIteratorHasCurrentEvent(it, &hasEvent)
                        continue
                    }
                    let d2: Int? = (hi == 0xC0) ? nil : Int(msg.data2)
                    let c = AppState.MidiFileCandidate(
                        statusHighNibble: hi,
                        channel:          ch,
                        data1:            Int(msg.data1),
                        data2:            d2,
                        occurrences:      1
                    )
                    let key = "\(hi)-\(ch)-\(msg.data1)-\(d2 ?? -1)"
                    counts[key] = (c, (counts[key]?.1 ?? 0) + 1)
                }

                MusicEventIteratorNextEvent(it)
                MusicEventIteratorHasCurrentEvent(it, &hasEvent)
            }
        }

        if counts.isEmpty {
            parseError = String(localized: "No Note On, CC, or PC event found in this file.")
            return
        }

        // Reconstruire avec occurrences réelles, trier par (hi, ch, d1)
        let candidates = counts.values
            .map { (c, n) in AppState.MidiFileCandidate(
                statusHighNibble: c.statusHighNibble,
                channel:          c.channel,
                data1:            c.data1,
                data2:            c.data2,
                occurrences:      n
            )}
            .sorted { a, b in
                if a.statusHighNibble != b.statusHighNibble { return a.statusHighNibble < b.statusHighNibble }
                if a.channel != b.channel { return a.channel < b.channel }
                return a.data1 < b.data1
            }

        let fileName = url.deletingPathExtension().lastPathComponent
        report  = appState.analyzeMidiFileImport(candidates, sourceFileName: fileName)
        applied = false
    }
}

// MARK: - Sheet import MaestroDMX

private struct MaestroDMXImportSheet: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    struct DraftEntry: Identifiable {
        let id = UUID()
        var name:   String = ""
        var number: String = ""
    }

    @State private var drafts:       [DraftEntry] = [DraftEntry()]
    @State private var report:       AppState.MaestroDMXImportReport? = nil
    @State private var applied       = false
    @State private var isPickingFile = false
    @State private var fileError:    String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // ── En-tête (fixe) ──────────────────────────────────────
            HStack {
                Label("Import MaestroDMX", systemImage: "square.and.arrow.down")
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 10) {
                Text("Enter scene names and their cue numbers (1–98). Each cue maps to Note On channel 16, note = cue + 28, velocity 0.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { isPickingFile = true } label: {
                    Label("Import from Show File...", systemImage: "doc.badge.arrow.up")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            if let err = fileError {
                Text("⚠ \(err)").font(.caption2).foregroundStyle(.red)
            }

            // ── Zone scrollable : tableau + rapport ─────────────────
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {

                    // En-tête colonnes
                    HStack {
                        Text("Scene Name").font(.caption.bold()).frame(minWidth: 180, alignment: .leading)
                        Text("Cue n°").font(.caption.bold()).frame(width: 60, alignment: .leading)
                        Text("Note").font(.caption.bold()).frame(width: 50, alignment: .leading)
                        Spacer()
                    }
                    .foregroundStyle(.secondary)

                    // Lignes de saisie
                    ForEach($drafts) { $draft in
                        HStack(spacing: 8) {
                            TextField("Ex : PURPLE RAIN", text: $draft.name)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                .frame(minWidth: 180)
                            TextField("1–98", text: $draft.number)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                .frame(width: 56)
                            let note = Int(draft.number).map { $0 + 28 }
                            Text(note.map { "\($0)" } ?? "—")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 44)
                            Button {
                                drafts.removeAll { $0.id == draft.id }
                                if drafts.isEmpty { drafts.append(DraftEntry()) }
                                report = nil
                            } label: {
                                Image(systemName: "minus.circle").foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    Button {
                        drafts.append(DraftEntry())
                        report = nil
                    } label: {
                        Label("Add Row", systemImage: "plus.circle").font(.caption)
                    }
                    .buttonStyle(.borderless)

                    // Rapport (s'il existe)
                    if let r = report {
                        Divider()
                        reportView(r)
                    }
                }
                .padding(.trailing, 4) // espace for la scrollbar
            }
            .frame(maxHeight: 420)

            Divider()

            // ── Boutons (toujours visibles en bas) ──────────────────
            HStack(spacing: 12) {
                Button("Analyser") {
                    report = appState.analyzeMaestroDMXImport(validPairs)
                }
                .buttonStyle(.bordered)
                .disabled(validPairs.isEmpty)

                if let r = report, !r.newEntries.isEmpty, !applied {
                    Button("Appliquer (\(r.newEntries.count) nouveau\(r.newEntries.count > 1 ? "x" : ""))") {
                        appState.applyMaestroDMXImport(r)
                        applied = true
                        report  = appState.analyzeMaestroDMXImport(validPairs)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if applied {
                    Label("Import Applied", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                }

                Spacer()
            }
        }
        .padding(20)
        .frame(minWidth: 560, idealWidth: 620)
        .fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            fileError = nil
            switch result {
            case .failure(let err):
                fileError = err.localizedDescription
            case .success(let urls):
                guard let url = urls.first else { return }
                parseMaestroDMXShowFile(url: url)
            }
        }
    }

    private func parseMaestroDMXShowFile(url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let show = json["show"] as? [String: Any],
              let patternCues = show["patternCue"] as? [[String: Any]] else {
            fileError = String(localized: "Unknown format: expected a MaestroDMX show file.")
            return
        }

        var newDrafts: [DraftEntry] = []
        for cue in patternCues {
            guard let name = cue["name"] as? String else { continue }
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard let midi = noteNameToMidi(trimmed) else { continue }
            let cueNumber = midi - 28
            guard (1...98).contains(cueNumber) else { continue }
            newDrafts.append(DraftEntry(name: trimmed, number: "\(cueNumber)"))
        }

        if newDrafts.isEmpty {
            fileError = String(localized: "No cue with a valid note suffix was found in this file.")
        } else {
            drafts  = newDrafts
            report  = nil
            applied = false
        }
    }

    private func noteNameToMidi(_ s: String) -> Int? {
        let noteNames = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        guard let regex = try? NSRegularExpression(pattern: #"([A-G]#?)(-?\d)$"#),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let pitchRange = Range(match.range(at: 1), in: s),
              let octaveRange = Range(match.range(at: 2), in: s),
              let octave = Int(s[octaveRange]),
              let semitone = noteNames.firstIndex(of: String(s[pitchRange])) else { return nil }
        return (octave + 2) * 12 + semitone
    }

    private var validPairs: [(name: String, cueNumber: Int)] {
        drafts.compactMap { d in
            let name = d.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, let n = Int(d.number), (1...98).contains(n) else { return nil }
            return (name: name, cueNumber: n)
        }
    }

    @ViewBuilder
    private func reportView(_ r: AppState.MaestroDMXImportReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rapport d'analyse").font(.subheadline.bold())

            // Résumé chiffré
            HStack(spacing: 20) {
                statBadge("\(r.newEntries.count) nouveau\(r.newEntries.count != 1 ? "x" : "")", color: .green)
                statBadge("\(r.alreadyPresent.count) already present\(r.alreadyPresent.count != 1 ? "s" : "")", color: .secondary)
                if !r.nameConflicts.isEmpty  { statBadge("\(r.nameConflicts.count) conflit\(r.nameConflicts.count != 1 ? "s" : "") de nom", color: .orange) }
                if !r.midiEquivalents.isEmpty { statBadge("\(r.midiEquivalents.count) equivalent\(r.midiEquivalents.count != 1 ? "s" : "") MIDI", color: .yellow) }
            }

            // Détail par entrée
            VStack(alignment: .leading, spacing: 3) {
                ForEach(r.entries) { entry in
                    HStack(spacing: 8) {
                        statusIcon(entry.status)
                        Text(entry.cueName)
                            .font(.caption)
                            .frame(minWidth: 160, alignment: .leading)
                        Text("cue \(entry.cueNumber) → note \(entry.note)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if let match = entry.matchedEvent {
                            Text("→ ID \(match.midiEventID) \"\(match.name ?? "?")\"")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !r.nameConflicts.isEmpty {
                Text("⚠ Name conflicts: same name, different MIDI message. Both events will be kept if you apply.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if !r.midiEquivalents.isEmpty {
                Text("ℹ Already covered: an existing event already contains this Note On ch16 (same MaestroDMX cue). Nothing created; the existing event is reused as is, even if it has a different name or contains additional messages (for example PC ch1).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func statusIcon(_ status: AppState.MaestroDMXImportReport.EntryStatus) -> some View {
        switch status {
        case .new:           Image(systemName: "plus.circle.fill").foregroundStyle(.green)
        case .alreadyPresent:Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
        case .nameConflict:  Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .midiEquivalent:Image(systemName: "equal.circle").foregroundStyle(.yellow)
        }
    }

    @ViewBuilder
    private func statBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color == .secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(color))
    }
}

// MARK: - Import MaestroDMX → OSC Library
//
// Lit un fichier JSON exporté ou sauvegardé depuis MaestroDMX et produit
// des OscEvents nommés (address = /show/cue/index, value = Int(index)).
// Formats acceptés, par ordre de tentative :
//   • Backup global : { "shows": [ { "name": "...", "patternCue": [...] }, ... ] }
//   • Export show   : { "show":  { "name": "...", "patternCue": [...] } }
//   • Export stage  : { "patternCue": [...] } ou { "cues": [...] }
//   • Inconnu       : JSON valide mais aucune structure de cues reconnue
//   • Chiffré       : non-JSON (binaire / base64 / archive) → message dédié
//
// Stratégie d'index par cue :
//   1) Note suffix dans le nom (ex « Warm Glowing F#0 ») → cue n° = note − 28
//      (même logique que l'import MIDI MaestroDMX). Range valide 1…98.
//   2) Sinon : position dans le tableau (1-based) — pour cues sans suffixe.
//
// Déduplication : un OscEvent existant avec même (address, value, category)
// est compté comme « already present », pas re-créé.

private struct MaestroDMXOscImportSheet: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var pickedFileName: String? = nil
    @State private var detectedFormat: MaestroDMXOscFormat = .unknown
    @State private var planByShow: [PlannedShow] = []
    @State private var totalCueCount: Int = 0
    @State private var skippedCount: Int = 0
    @State private var fileError: String? = nil
    @State private var isPickingFile = false
    @State private var report: ApplyReport? = nil

    enum MaestroDMXOscFormat: String {
        case backup, show, stage, unknown, encrypted
        var label: String {
            switch self {
            case .backup:    return "MaestroDMX Backup"
            case .show:      return "MaestroDMX Show"
            case .stage:     return "MaestroDMX Stage"
            case .unknown:   return "Unknown JSON"
            case .encrypted: return "Encrypted / unreadable"
            }
        }
    }

    struct PlannedShow: Identifiable {
        let id = UUID()
        var showName: String
        var entries:  [PlannedRow]
    }

    struct PlannedRow: Identifiable {
        let id = UUID()
        var cueName: String
        var cueIndex: Int
        var isAlreadyPresent: Bool
    }

    struct ApplyReport {
        var created: Int
        var alreadyPresent: Int
        var skipped: Int
    }

    private var newCount: Int {
        planByShow.flatMap(\.entries).filter { !$0.isAlreadyPresent }.count
    }

    private var existingCount: Int {
        planByShow.flatMap(\.entries).filter { $0.isAlreadyPresent }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Import MaestroDMX → OSC Library", systemImage: "square.and.arrow.down")
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Text("Reads a MaestroDMX show or backup file and creates OSC events with address /show/cue/index. The OSC engine will send the cue number as Int when the cue plays. Default destination: 192.168.37.1:7672 (editable per event afterwards).")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button {
                    isPickingFile = true
                } label: {
                    Label("Choose File...", systemImage: "doc.badge.arrow.up")
                }
                .buttonStyle(.bordered)

                if let name = pickedFileName {
                    Text(name)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            if let err = fileError {
                Text("⚠ \(err)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if !planByShow.isEmpty {
                HStack(spacing: 10) {
                    statBadge("Format: \(detectedFormat.label)", color: .secondary)
                    statBadge("\(planByShow.count) show\(planByShow.count == 1 ? "" : "s")", color: .blue)
                    statBadge("\(totalCueCount) cue\(totalCueCount == 1 ? "" : "s")", color: .blue)
                    statBadge("\(newCount) new", color: .green)
                    if existingCount > 0 {
                        statBadge("\(existingCount) existing", color: .secondary)
                    }
                    if skippedCount > 0 {
                        statBadge("\(skippedCount) skipped", color: .orange)
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(planByShow) { show in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(show.showName)
                                    .font(.caption.bold())
                                ForEach(show.entries) { e in
                                    HStack(spacing: 8) {
                                        Image(systemName: e.isAlreadyPresent ? "checkmark.circle" : "plus.circle.fill")
                                            .foregroundStyle(e.isAlreadyPresent ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.green))
                                            .font(.caption2)
                                        Text(e.cueName)
                                            .font(.caption)
                                            .lineLimit(1)
                                            .frame(minWidth: 220, alignment: .leading)
                                        Text("→ /show/cue/index Int(\(e.cueIndex))")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(8)
                            .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.trailing, 6)
                }
                .frame(maxHeight: 320)
            }

            Divider()

            HStack {
                if let r = report {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("\(r.created) created · \(r.alreadyPresent) existing · \(r.skipped) skipped")
                        .font(.caption)
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Spacer()
                    if !planByShow.isEmpty {
                        Button("Apply (\(newCount) new)") {
                            applyPlan()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newCount == 0)
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 620, idealWidth: 680)
        .fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handlePicker(result: result)
        }
    }

    // MARK: - Actions

    private func handlePicker(result: Result<[URL], Error>) {
        fileError = nil
        report = nil
        switch result {
        case .failure(let err):
            fileError = err.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            parseAndPlan(url: url)
        }
    }

    private func parseAndPlan(url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }

        pickedFileName = url.lastPathComponent
        planByShow     = []
        totalCueCount  = 0
        skippedCount   = 0
        detectedFormat = .unknown

        guard let data = try? Data(contentsOf: url) else {
            fileError = String(localized: "Cannot read this file.")
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            detectedFormat = .encrypted
            fileError = String(localized: "This MaestroDMX backup seems encrypted or not decodable. Export a show or a readable cue list from MaestroDMX.")
            return
        }

        let (shows, format) = extractShows(from: json)
        detectedFormat = format

        guard !shows.isEmpty else {
            fileError = String(localized: "No MaestroDMX cues found in this file.")
            return
        }

        var total = 0
        var skipped = 0
        var built: [PlannedShow] = []

        for show in shows {
            var rows: [PlannedRow] = []
            for (i, cueDict) in show.cues.enumerated() {
                guard let parsed = parseCue(cueDict, position: i + 1) else {
                    skipped += 1
                    continue
                }
                total += 1
                let already = appState.findOscEvent(
                    matchingAddress: "/show/cue/index",
                    value: .int(parsed.index),
                    category: show.name
                ) != nil
                rows.append(PlannedRow(
                    cueName: parsed.name,
                    cueIndex: parsed.index,
                    isAlreadyPresent: already
                ))
            }
            if !rows.isEmpty {
                built.append(PlannedShow(showName: show.name, entries: rows))
            }
        }

        totalCueCount = total
        skippedCount  = skipped
        planByShow    = built

        if total == 0 {
            fileError = String(localized: "No MaestroDMX cues found in this file.")
        }
    }

    private func applyPlan() {
        var created = 0
        var present = 0
        for show in planByShow {
            for e in show.entries {
                if e.isAlreadyPresent {
                    present += 1
                    continue
                }
                _ = appState.createOscEvent(
                    name: e.cueName,
                    category: show.showName,
                    host: "192.168.37.1",
                    port: 7672,
                    address: "/show/cue/index",
                    value: .int(e.cueIndex)
                )
                created += 1
            }
        }
        report = ApplyReport(created: created, alreadyPresent: present, skipped: skippedCount)
        print("[OSC] MaestroDMX import applied — \(created) created · \(present) existing · \(skippedCount) skipped")
    }

    // MARK: - Parsing helpers

    /// Tente d'extraire la liste des shows et leur tableau patternCue.
    /// Tolérant aux variations de nommage : `shows`, `show`, `patternCue`,
    /// `patterns`, `cues`. Renvoie aussi le format détecté pour la UI.
    private func extractShows(from json: Any) -> (shows: [(name: String, cues: [[String: Any]])], format: MaestroDMXOscFormat) {
        guard let dict = json as? [String: Any] else { return ([], .unknown) }

        // A. Backup : { shows: [ {name, patternCue}, ... ] }
        if let shows = dict["shows"] as? [[String: Any]] {
            let list: [(name: String, cues: [[String: Any]])] = shows.compactMap { s in
                let name = (s["name"] as? String) ?? (s["title"] as? String) ?? "Untitled Show"
                if let cues = cuesArray(in: s) {
                    return (name, cues)
                }
                return nil
            }
            if !list.isEmpty { return (list, .backup) }
        }

        // B. Show export : { show: {name, patternCue} }
        if let show = dict["show"] as? [String: Any] {
            let name = (show["name"] as? String) ?? (show["title"] as? String) ?? "Default Show"
            if let cues = cuesArray(in: show) {
                return ([(name, cues)], .show)
            }
        }

        // C. Stage export : { patternCue: [...] } directly
        if let cues = cuesArray(in: dict) {
            let name = (dict["name"] as? String) ?? (dict["title"] as? String) ?? "MaestroDMX"
            return ([(name, cues)], .stage)
        }

        return ([], .unknown)
    }

    private func cuesArray(in dict: [String: Any]) -> [[String: Any]]? {
        if let arr = dict["patternCue"] as? [[String: Any]] { return arr }
        if let arr = dict["patterns"]   as? [[String: Any]] { return arr }
        if let arr = dict["cues"]       as? [[String: Any]] { return arr }
        return nil
    }

    /// Extrait nom + index d'une cue MaestroDMX. Utilise note - 28 si suffix
    /// valide, sinon fallback sur la position 1-based.
    private func parseCue(_ cue: [String: Any], position: Int) -> (name: String, index: Int)? {
        let rawName = (cue["name"] as? String)
            ?? (cue["title"] as? String)
            ?? ""
        let trimmed = rawName.trimmingCharacters(in: .whitespaces)
        if let midi = noteNameToMidi(trimmed) {
            let cueNumber = midi - 28
            if (1...98).contains(cueNumber) {
                return (name: trimmed, index: cueNumber)
            }
        }
        // Cherche un champ explicite « index » / « cueNumber » avant de tomber
        // sur la position. Certains exports tiers les exposent en clair.
        if let n = cue["index"] as? Int,        (1...98).contains(n) {
            return (name: trimmed.isEmpty ? "Cue \(n)" : trimmed, index: n)
        }
        if let n = cue["cueNumber"] as? Int,    (1...98).contains(n) {
            return (name: trimmed.isEmpty ? "Cue \(n)" : trimmed, index: n)
        }
        if let n = cue["number"] as? Int,       (1...98).contains(n) {
            return (name: trimmed.isEmpty ? "Cue \(n)" : trimmed, index: n)
        }
        // Pas de suffix note, pas de champ index — on n'a que la position.
        if trimmed.isEmpty { return nil }
        return (name: trimmed, index: position)
    }

    private func noteNameToMidi(_ s: String) -> Int? {
        let noteNames = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        guard let regex = try? NSRegularExpression(pattern: #"([A-G]#?)(-?\d)$"#),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let pitchRange  = Range(match.range(at: 1), in: s),
              let octaveRange = Range(match.range(at: 2), in: s),
              let octave   = Int(s[octaveRange]),
              let semitone = noteNames.firstIndex(of: String(s[pitchRange])) else { return nil }
        return (octave + 2) * 12 + semitone
    }

    @ViewBuilder
    private func statBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color == .secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(color))
    }
}

// MARK: - Ligne d'un événement MIDI (bibliothèque globale)

private struct MidiEventGlobalRow: View {
    @Bindable var appState: AppState
    let event: MidiEvent

    @State private var isExpanded       = false
    @State private var deleteConfirm    = false
    @State private var archiveConfirm   = false

    private var isVelvetNative: Bool { event.midiEventID < 0 }
    private var isArchived: Bool { appState.isArchived(event.midiEventID) }
    private var isRestCue: Bool {
        // Lock seulement si le rest cue actif est en mode MIDI ET pointe sur ce
        // MidiEvent. Si l'utilisateur a basculé en OSC, ce MidiEvent redevient
        // librement archivable même s'il était le rest cue précédent.
        appState.restCueType == .midi
            && appState.restCueMidiEventID == event.midiEventID
    }
    private var usage: AppState.MidiEventUsage { appState.midiEventUsage(for: event.midiEventID) }
    private var messages: [MidiMessage] {
        appState.midiMessages(for: event).sorted { $0.midiMessageID < $1.midiMessageID }
    }
    private var typeSummary: String {
        guard let first = messages.first else { return "no message" }
        let t: String
        switch first.message {
        case 144: t = "Note On"
        case 128: t = "Note Off"
        case 176: t = "CC"
        case 192: t = "PC"
        default:  t = first.message.map { "0x\(String($0, radix: 16).uppercased())" } ?? "?"
        }
        let ch = (first.channel ?? 0) + 1
        return messages.count > 1 ? "\(t) ch\(ch) +\(messages.count - 1)" : "\(t) ch\(ch)"
    }
    private var isMaestro: Bool {
        messages.contains { $0.maestroDescription != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // Expand
                Button { isExpanded.toggle() } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)

                // Nom (grisé si archived)
                Text(event.name ?? "Event \(event.midiEventID)")
                    .font(.callout.bold())
                    .lineLimit(1)
                    .foregroundStyle(isArchived ? Color.secondary : Color.primary)

                // Badge source
                Text(isVelvetNative ? "Velvet" : "ShowBuddy")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(isVelvetNative ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(isVelvetNative ? Color.accentColor : .secondary)

                // Badge archived
                if isArchived {
                    Text("Archived")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.2), in: Capsule())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Type
                Text(typeSummary)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(isArchived ? AnyShapeStyle(.tertiary) : (isMaestro ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary)))

                // Bouton test
                Button { appState.dispatch(event: event) } label: {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.borderless)
                .help("Tester l'envoi")

                // Archiver / Restore
                if isArchived {
                    Button {
                        appState.unarchiveMidiEvent(event.midiEventID)
                    } label: {
                        Image(systemName: "archivebox.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.borderless)
                    .help("Restore: appears in pickers again")
                } else if isRestCue {
                    Image(systemName: "archivebox")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .help("Cue de repos actif — archivage interdit")
                } else {
                    Button {
                        if usage.isUsed {
                            archiveConfirm = true
                        } else {
                            appState.archiveMidiEvent(event.midiEventID)
                        }
                    } label: {
                        Image(systemName: "archivebox")
                    }
                    .buttonStyle(.borderless)
                    .help(usage.isUsed ? "Archive: this event is used, confirmation will be requested" : "Archive: hide from pickers")
                }

                // Suppression sécurisée (Velvet natifs uniquement)
                if isVelvetNative {
                    if usage.isUsed {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help("Used: \(usage.description)")
                    } else {
                        Button(role: .destructive) { deleteConfirm = true } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Delete (unused)")
                    }
                } else {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .help("Event ShowBuddy — non modifiable")
                }
            }

            // Usage
            HStack(spacing: 4) {
                Image(systemName: usage.isUsed ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.caption2)
                    .foregroundStyle(usage.isUsed ? Color.green : Color.secondary)
                Text(usage.description)
                    .font(.caption2)
                    .foregroundStyle(usage.isUsed ? .primary : .tertiary)
            }
            .padding(.leading, 20)

            // Détail messages (expanded)
            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    if messages.isEmpty {
                        Text("No MIDI message.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(messages) { msg in
                            Text(msg.humanDescription)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(msg.maestroDescription != nil ? Color.accentColor : .secondary)
                        }
                    }

                    // Éditeur messages for Velvet natif
                    if isVelvetNative {
                        VelvetMidiEventRow(appState: appState, event: event)
                            .padding(.top, 4)
                    }
                }
                .padding(.leading, 20)
                .padding(.top, 2)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
        .confirmationDialog(
            "Delete \"\(event.name ?? "this event")\"?",
            isPresented: $deleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                appState.deleteVelvetMidiEvent(event)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The event and all of its MIDI messages will be deleted. This action cannot be undone.")
        }
        .confirmationDialog(
            "Archive \"\(event.name ?? "this event")\"?",
            isPresented: $archiveConfirm,
            titleVisibility: .visible
        ) {
            Button("Archive Anyway", role: .destructive) {
                appState.archiveMidiEvent(event.midiEventID)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This event is referenced by \(usage.description). Existing triggers will keep working; archiving only hides it from pickers.")
        }
    }
}

// MARK: - Ligne d'un événement MIDI Velvet

private struct VelvetMidiEventRow: View {
    @Bindable var appState: AppState
    let event: MidiEvent

    @State private var isExpanded      = true
    @State private var isRenaming      = false
    @State private var renameDraft     = ""
    @State private var isAddingMessage = false
    @State private var newMsgType      = MidiMessageType.noteOn
    @State private var newMsgChannel   = 1
    @State private var newMsgData1     = 0
    @State private var newMsgData2     = 100
    @State private var deleteConfirm   = false

    private var messages: [MidiMessage] {
        (appState.midiMessagesByEventID[event.midiEventID] ?? [])
            .sorted { $0.midiMessageID < $1.midiMessageID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // En-tête
            HStack(spacing: 6) {
                Button { isExpanded.toggle() } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)

                if isRenaming {
                    TextField("Nom", text: $renameDraft)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .onSubmit { commitRename() }
                    Button("OK") { commitRename() }
                        .controlSize(.mini)
                        .disabled(renameDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button { isRenaming = false } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .controlSize(.mini)
                } else {
                    Text(event.name ?? "Event \(event.midiEventID)")
                        .font(.callout.bold())
                    Text("· \(messages.count) message\(messages.count != 1 ? "s" : "")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button { renameDraft = event.name ?? ""; isRenaming = true } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help("Rename")
                    Button { appState.dispatch(event: event) } label: {
                        Image(systemName: "play.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Test sending to the configured destination")
                    Button(role: .destructive) { deleteConfirm = true } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete the event")
                }
            }

            // Corps (messages + formulaire ajout)
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(messages) { msg in
                        HStack(spacing: 6) {
                            Text(messageLabel(msg))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button { appState.deleteVelvetMidiMessage(msg) } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                            .help("Delete this message")
                        }
                        .padding(.leading, 20)
                    }

                    if isAddingMessage {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Picker("Type", selection: $newMsgType) {
                                    ForEach(MidiMessageType.allCases) { t in
                                        Text(t.localizedLabel).tag(t)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .foregroundStyle(.primary)
                                .frame(maxWidth: 160)

                                Stepper("Channel \(newMsgChannel)", value: $newMsgChannel, in: 1...16)
                                    .font(.caption)
                                    .controlSize(.small)
                            }

                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(newMsgType.data1Label)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    HStack(spacing: 6) {
                                        TextField("0–127", value: $newMsgData1, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .controlSize(.small)
                                            .frame(width: 56)
                                        if newMsgType == .noteOn || newMsgType == .noteOff {
                                            Text(midiNoteName(newMsgData1))
                                                .font(.caption.monospacedDigit().bold())
                                                .foregroundStyle(Color.accentColor)
                                                .frame(width: 36, alignment: .leading)
                                        }
                                    }
                                }
                                if newMsgType.hasData2 {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(newMsgType.data2Label)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        TextField("0–127", value: $newMsgData2, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .controlSize(.small)
                                            .frame(width: 64)
                                    }
                                }
                                Spacer()
                                Button("Add") { commitAddMessage() }
                                    .controlSize(.small)
                                Button("Cancel") { isAddingMessage = false }
                                    .buttonStyle(.borderless)
                                    .controlSize(.small)
                            }
                        }
                        .padding(8)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                        .padding(.leading, 20)
                    } else {
                        Button {
                            isAddingMessage = true
                        } label: {
                            Label("Add Message", systemImage: "plus.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .padding(.leading, 20)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        .confirmationDialog(
            "Delete \"\(event.name ?? "this event")\"?",
            isPresented: $deleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                appState.deleteVelvetMidiEvent(event)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The event and all of its MIDI messages will be deleted.")
        }
    }

    private func commitRename() {
        appState.renameVelvetMidiEvent(event, to: renameDraft.trimmingCharacters(in: .whitespaces))
        isRenaming = false
    }

    private func commitAddMessage() {
        let d1 = Int64(max(0, min(127, newMsgData1)))
        let d2 = newMsgType.hasData2 ? Int64(max(0, min(127, newMsgData2))) : nil
        appState.addVelvetMidiMessage(
            to: event,
            messageType: newMsgType.statusByte,
            channel: Int64(newMsgChannel),
            data1: d1,
            data2: d2
        )
        isAddingMessage = false
        newMsgData1 = 0
        newMsgData2 = 100
    }

    private func messageLabel(_ msg: MidiMessage) -> String {
        let typeStr: String
        switch msg.message {
        case 144: typeStr = "Note On"
        case 128: typeStr = "Note Off"
        case 176: typeStr = "CC"
        case 192: typeStr = "PC"
        default:  typeStr = msg.message.map { "0x\(String($0, radix: 16).uppercased())" } ?? "?"
        }
        let ch = (msg.channel ?? 0) + 1
        let d1 = msg.data1.map(Int.init) ?? 0
        if msg.message == 192 {
            return "\(typeStr)  channel:\(ch)  prog:\(d1)"
        } else if msg.message == 144 || msg.message == 128 {
            return "\(typeStr)  channel:\(ch)  \(midiNoteName(d1)) (\(d1))  vel:\(msg.data2 ?? 0)"
        } else {
            return "\(typeStr)  channel:\(ch)  \(d1)/\(msg.data2 ?? 0)"
        }
    }
}

// MARK: - Nettoyage des mémos MIDI de fin

/// Outil de nettoyage : liste les mémos MIDI déclenchés dans les X dernières
/// secondes des songs. Trois actions par mémo : désactiver le MIDI,
/// supprimer le mémo (confirmation), ou garder tel quel (ne rien faire).
/// Aucune action automatique — l'utilisateur valide chaque ligne.
private struct TailMidiCleanupSheet: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var windowSeconds: TimeInterval = 5
    @State private var findings: [AppState.TailMidiEndding] = []
    @State private var confirmingDelete: AppState.TailMidiEndding?

    private static let windowChoices: [TimeInterval] = [3, 5, 10]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("End-of-Song MIDI Memos", systemImage: "wand.and.sparkles")
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 8) {
                Text("Window:")
                    .font(.callout)
                Picker("Window", selection: $windowSeconds) {
                    ForEach(Self.windowChoices, id: \.self) { s in
                        Text("\(Int(s)) final seconds").tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)
            }

            if findings.isEmpty {
                ContentUnavailableView(
                    "No MIDI Memo in the Window",
                    systemImage: "checkmark.seal",
                    description: Text("No song has a MIDI memo triggered in its final \(Int(windowSeconds)) seconds.")
                )
                .frame(maxHeight: 200)
            } else {
                Text("\(findings.count) memo(s) found; no changes without explicit action.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                List(findings) { finding in
                    findingRow(finding)
                }
                .listStyle(.inset)
                .frame(minHeight: 220, maxHeight: 380)
            }
        }
        .padding(16)
        .frame(minWidth: 600, idealWidth: 680)
        .onAppear { rescan() }
        .onChange(of: windowSeconds) { _, _ in rescan() }
        .confirmationDialog(
            "Delete memo \"\(confirmingDelete?.memo.shortName ?? "")\" from \"\(confirmingDelete?.track.name ?? "")\"?",
            isPresented: Binding(
                get: { confirmingDelete != nil },
                set: { if !$0 { confirmingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Memo", role: .destructive) {
                if let f = confirmingDelete {
                    appState.deleteMemo(memoID: f.memo.id, in: f.track)
                    rescan()
                }
                confirmingDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        }
    }

    @ViewBuilder
    private func findingRow(_ finding: AppState.TailMidiEndding) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(finding.track.name ?? "Untitled")
                        .font(.callout.bold())
                        .lineLimit(1)
                    if finding.isStopCueLike {
                        Text("STOP CUE")
                            .font(.system(size: 9, weight: .black))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.85), in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                Text("\(finding.memo.shortName.isEmpty ? "Untitled" : finding.memo.shortName) · \(timecode(finding.triggerTime)) / fin \(timecode(finding.effectiveEnd)) · \(finding.eventName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Disable MIDI") {
                appState.disableMidi(memoID: finding.memo.id, in: finding.track)
                rescan()
            }
            .controlSize(.small)
            .help("Removes MIDI sending; the memo and its text stay intact")
            Button("Delete...", role: .destructive) {
                confirmingDelete = finding
            }
            .controlSize(.small)
            .help("Deletes the entire memo (confirmation required)")
        }
        .padding(.vertical, 2)
    }

    private func rescan() {
        findings = appState.scanTailMidiMemos(within: windowSeconds)
    }

    private func timecode(_ s: TimeInterval) -> String {
        let t = max(0, Int(s.rounded()))
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

// MARK: - Sheet wrapper

/// Enveloppe de `MidiSettingsView` for une présentation en sheet
/// (depuis un menu toolbar plutôt qu'un popover direct).
struct MidiSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Settings", systemImage: "gearshape")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
            MidiSettingsView(appState: appState)
        }
        .frame(width: 440)
    }
}

// MARK: - OSC raw-test value kind

/// Type d'argument pour le test brut OSC. Indépendant des OscEvents nommés —
/// utilisé uniquement par `OscTestSection`.
enum OscRawValueKind: String, CaseIterable, Identifiable {
    case none, int, float, string, bool
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none:   return "None"
        case .int:    return "Int"
        case .float:  return "Float"
        case .string: return "String"
        case .bool:   return "Bool"
        }
    }
}

// MARK: - OSC Test Section (free-form, brand-agnostic)

/// Panneau de test OSC en saisie libre : host/port/adresse/valeur en clair,
/// envoyé directement via OSCEngine sans passer par la Library. Conservé tel
/// quel pour les tests d'intégration tiers (QLab, MaestroDMX, Companion,
/// Protokol…) — l'utilisateur n'a pas envie de créer une entrée Library
/// pour ping une cible une seule fois.
private struct OscTestSection: View {
    let appState: AppState

    @State private var host: String = UserDefaults.standard.string(forKey: "oscTestHost") ?? "127.0.0.1"
    @State private var portText: String = String(UserDefaults.standard.object(forKey: "oscTestPort") as? Int ?? 8000)
    @State private var address: String = UserDefaults.standard.string(forKey: "oscTestAddress") ?? "/cue/scene/1"
    @State private var valueKind: OscRawValueKind = {
        let raw = UserDefaults.standard.string(forKey: "oscTestValueKind") ?? "none"
        return OscRawValueKind(rawValue: raw) ?? .none
    }()
    @State private var intText: String = "1"
    @State private var floatText: String = "1.0"
    @State private var stringText: String = ""
    @State private var boolValue: Bool = true
    @State private var feedback: String? = nil

    private func currentValue() -> OSCValue? {
        switch valueKind {
        case .none:   return nil
        case .int:    return .int(Int(intText) ?? 0)
        case .float:  return .float(Double(floatText) ?? 0)
        case .string: return .string(stringText)
        case .bool:   return .bool(boolValue)
        }
    }

    private var isValid: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty
            && address.hasPrefix("/")
            && (1...65535).contains(Int(portText) ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OSC Test (raw)")
                .font(.subheadline.bold())
            Text("Send a one-shot OSC message via UDP without touching the Library. Useful to verify QLab, MaestroDMX, Resolume, Companion, Protokol… before creating named events.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                TextField("Host / IP", text: $host)
                    .textFieldStyle(.roundedBorder)
                TextField("Port", text: $portText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }

            TextField("/cue/scene/1", text: $address)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            Picker("Value", selection: $valueKind) {
                ForEach(OscRawValueKind.allCases) { k in
                    Text(k.label).tag(k)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch valueKind {
            case .none:
                EmptyView()
            case .int:
                TextField("Integer value", text: $intText)
                    .textFieldStyle(.roundedBorder)
            case .float:
                TextField("Float value", text: $floatText)
                    .textFieldStyle(.roundedBorder)
            case .string:
                TextField("String value", text: $stringText)
                    .textFieldStyle(.roundedBorder)
            case .bool:
                Toggle(isOn: $boolValue) {
                    Text(boolValue ? "true (T)" : "false (F)").font(.caption)
                }
            }

            HStack {
                Button {
                    let port = Int(portText) ?? 0
                    appState.sendTestOSC(
                        host: host,
                        port: port,
                        address: address,
                        value: currentValue()
                    )
                    UserDefaults.standard.set(host, forKey: "oscTestHost")
                    UserDefaults.standard.set(port, forKey: "oscTestPort")
                    UserDefaults.standard.set(address, forKey: "oscTestAddress")
                    UserDefaults.standard.set(valueKind.rawValue, forKey: "oscTestValueKind")
                    if let err = appState.oscEngine.lastError {
                        feedback = "Sent — last error: \(err)"
                    } else {
                        feedback = "Sent to \(host):\(port) \(address)"
                    }
                } label: {
                    Label("Send OSC Test", systemImage: "paperplane.fill")
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .disabled(!isValid)

                if let feedback {
                    Text(feedback)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

// MARK: - Velvet OSC Library Section

/// Bibliothèque d'OscEvents nommés — miroir de `VelvetMidiLibrarySection`.
/// Permet de créer, renommer, modifier et supprimer les events que les cues
/// OSC de la timeline référenceront.
private struct VelvetOscLibrarySection: View {
    @Bindable var appState: AppState
    @State private var isExpanded     = false
    @State private var isCreating     = false
    @State private var newEventName   = ""
    @State private var isShowingMaestroImport = false

    private var events: [OscEvent] { appState.sortedOscEvents }

    private var groupedByCategory: [(String, [OscEvent])] {
        let groups = Dictionary(grouping: events) { $0.category ?? "Other" }
        return groups
            .map { ($0.key, $0.value.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()
                    Button {
                        isShowingMaestroImport = true
                    } label: {
                        Label("Import from MaestroDMX…", systemImage: "square.and.arrow.down")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    Button {
                        isCreating = true
                    } label: {
                        Label("New OSC Event", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isCreating)
                }

                if events.isEmpty && !isCreating {
                    Text("No OSC event yet. Click \"New OSC Event\" to create one — give it a name, a destination, an address, and (optionally) a value. Place it on the timeline by picking it in a Cue OSC inspector.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(groupedByCategory, id: \.0) { (category, list) in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category)
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            ForEach(list) { event in
                                OscEventRow(appState: appState, event: event)
                            }
                        }
                    }
                }

                if isCreating {
                    HStack(spacing: 6) {
                        TextField("Event Name (e.g. Purple Rain Intro)", text: $newEventName)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .onSubmit { commitCreate() }
                        Button("Create") { commitCreate() }
                            .controlSize(.small)
                            .disabled(newEventName.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("Cancel") {
                            isCreating = false
                            newEventName = ""
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.top, 6)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("OSC Library")
                    .font(.subheadline.bold())
                if !isExpanded {
                    Text("\(events.count) named OSC event\(events.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $isShowingMaestroImport) {
            MaestroDMXOscImportSheet(appState: appState)
        }
    }

    private func commitCreate() {
        let name = newEventName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        appState.createOscEvent(name: name)
        newEventName = ""
        isCreating   = false
    }
}

// MARK: - OSC Event Row (édition inline)

private struct OscEventRow: View {
    @Bindable var appState: AppState
    let event: OscEvent

    @State private var isExpanded   = false
    @State private var deleteConfirm = false
    @State private var draft: OscEvent
    @State private var portText: String
    @State private var valueKind: OscRawValueKind
    @State private var intText: String   = "0"
    @State private var floatText: String = "0.0"
    @State private var stringText: String = ""
    @State private var boolValue: Bool = true

    init(appState: AppState, event: OscEvent) {
        self.appState = appState
        self.event    = event
        _draft        = State(initialValue: event)
        _portText     = State(initialValue: String(event.port))
        switch event.value {
        case .none:
            _valueKind = State(initialValue: .none)
        case .some(.int(let v)):
            _valueKind = State(initialValue: .int)
            _intText   = State(initialValue: String(v))
        case .some(.float(let v)):
            _valueKind = State(initialValue: .float)
            _floatText = State(initialValue: String(format: "%g", v))
        case .some(.string(let v)):
            _valueKind  = State(initialValue: .string)
            _stringText = State(initialValue: v)
        case .some(.bool(let v)):
            _valueKind = State(initialValue: .bool)
            _boolValue = State(initialValue: v)
        }
    }

    private var usage: Int { appState.oscEventUsage(for: event.oscEventID) }

    /// True si cet OscEvent est le rest cue actif (type OSC). Bloque la
    /// suppression — sinon le STOP n'enverrait plus rien sans avertissement.
    private var isRestCue: Bool {
        appState.restCueType == .osc
            && appState.restOscEventID == event.oscEventID
    }

    private func currentValue() -> OSCValue? {
        switch valueKind {
        case .none:   return nil
        case .int:    return .int(Int(intText) ?? 0)
        case .float:  return .float(Double(floatText) ?? 0)
        case .string: return .string(stringText)
        case .bool:   return .bool(boolValue)
        }
    }

    private var summary: String {
        let v = event.value?.displayValue ?? "no value"
        return "\(event.host):\(event.port)  \(event.address)  \(v)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button { isExpanded.toggle() } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)

                Text(event.name)
                    .font(.callout.bold())
                    .lineLimit(1)

                Spacer()

                Text(summary)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Button {
                    appState.dispatch(oscEvent: event)
                } label: {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.borderless)
                .help("Test send this OSC event")

                if isRestCue {
                    Image(systemName: "moon.zzz.fill")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                        .help("Active rest cue (OSC) — cannot be deleted while selected")
                } else if usage > 0 {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help("Used by \(usage) cue\(usage == 1 ? "" : "s")")
                } else {
                    Button(role: .destructive) { deleteConfirm = true } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete (unused)")
                }
            }

            if usage > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text("\(usage) timeline cue\(usage == 1 ? "" : "s")")
                        .font(.caption2)
                }
                .padding(.leading, 20)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Name").frame(width: 70, alignment: .leading).font(.caption)
                        TextField("Name", text: $draft.name)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Text("Category").frame(width: 70, alignment: .leading).font(.caption)
                        TextField("Optional", text: Binding(
                            get: { draft.category ?? "" },
                            set: { draft.category = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Text("Host").frame(width: 70, alignment: .leading).font(.caption)
                        TextField("127.0.0.1", text: $draft.host)
                            .textFieldStyle(.roundedBorder)
                        Text("Port").font(.caption)
                        TextField("8000", text: $portText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }
                    HStack {
                        Text("Address").frame(width: 70, alignment: .leading).font(.caption)
                        TextField("/cue/scene/1", text: $draft.address)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                    Picker("Value", selection: $valueKind) {
                        ForEach(OscRawValueKind.allCases) { k in
                            Text(k.label).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    switch valueKind {
                    case .none:
                        EmptyView()
                    case .int:
                        TextField("Integer", text: $intText).textFieldStyle(.roundedBorder)
                    case .float:
                        TextField("Float", text: $floatText).textFieldStyle(.roundedBorder)
                    case .string:
                        TextField("String", text: $stringText).textFieldStyle(.roundedBorder)
                    case .bool:
                        Toggle(isOn: $boolValue) { Text(boolValue ? "true" : "false").font(.caption) }
                    }
                    HStack {
                        Spacer()
                        Button("Apply") {
                            draft.port  = Int(portText) ?? draft.port
                            draft.value = currentValue()
                            appState.updateOscEvent(draft)
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty
                                  || !draft.address.hasPrefix("/")
                                  || draft.host.trimmingCharacters(in: .whitespaces).isEmpty
                                  || (Int(portText) ?? 0) < 1
                                  || (Int(portText) ?? 0) > 65535)
                    }
                }
                .padding(.leading, 20)
                .padding(.top, 4)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
        .confirmationDialog(
            "Delete \"\(event.name)\"?",
            isPresented: $deleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                appState.deleteOscEvent(event)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This OSC event will be removed. Existing timeline cues that referenced it will become unlinked.")
        }
    }
}

// MARK: - Demo / First Steps

private struct DemoContentSection: View {
    @Bindable var appState: AppState
    @State private var showDeleteConfirm  = false
    @State private var showInstallConfirm = false
    @State private var installError: String? = nil

    private var bundleAvailable: Bool { DemoContentStore.shared.bundleDemoAvailable }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Demo / First Steps")
                .font(.subheadline.bold())

            if let manifest = appState.demoManifest {
                // ── Démo installée ────────────────────────────────────
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("Demo installed: version \(manifest.version)")
                        .font(.callout)
                }
                Text("\(manifest.showIDs.count) show · \(manifest.trackIDs.count) songs · \(manifest.midiEventIDs.count) MIDI events")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete Demo...", systemImage: "trash")
                }
                .controlSize(.small)
                .confirmationDialog(
                    "Delete the Demo Project?",
                    isPresented: $showDeleteConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Delete Demo", role: .destructive) {
                        appState.removeDemoContent()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Les \(manifest.trackIDs.count) demo songs, memos, cues, and MIDI events will be deleted. Your personal data is not touched.")
                }

            } else {
                // ── Démo non installée ────────────────────────────────
                if bundleAvailable {
                    Label("Demo Available: Not Installed", systemImage: "tray.and.arrow.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("No Demo Content in This Build", systemImage: "tray")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let err = installError {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    showInstallConfirm = true
                } label: {
                    Label("Install Demo", systemImage: "sparkles")
                }
                .controlSize(.small)
                .disabled(!bundleAvailable)
                .help(bundleAvailable
                      ? "Load the demo project into your library"
                      : "No demo content in this build")
                .confirmationDialog(
                    "Install the Demo Project?",
                    isPresented: $showInstallConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Installer") {
                        installError = nil
                        do {
                            try appState.installDemoContent()
                        } catch {
                            installError = error.localizedDescription
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("A \"Velvet Demo Show\" show and 5 demo songs will be added to your library. Your existing data will not be changed.")
                }
            }
        }
    }
}

// MARK: - Audio Library — résumé

private struct MediaLibrarySummarySection: View {
    let appState: AppState
    @State private var isExpanded = false
    @State private var librarySize: String = "..."

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Audio Library")
                .font(.subheadline.bold())

            // Résumé : nombre de songs + taille
            HStack(spacing: 16) {
                Label("\(appState.audioFiles.count) songs", systemImage: "music.note")
                    .font(.callout)
                Label(librarySize, systemImage: "internaldrive")
                    .font(.callout)
            }
            .foregroundStyle(.secondary)

            if appState.mediaFolderBookmarkData == nil {
                Label(
                    "Folder not authorized; audio playback may fail.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(VSColor.warning)
            }

            // Bouton Gérer
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    if let path = appState.mediaFolderDisplayPath {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill").foregroundStyle(.green)
                            Text(path)
                                .font(.caption)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                    }
                    HStack {
                        Button {
                            presentMediaFilesOpenPanel(appState: appState)
                        } label: {
                            Label(
                                appState.mediaFolderBookmarkData == nil
                                    ? "Locate Folder..."
                                    : "Change Folder...",
                                systemImage: "folder.badge.plus"
                            )
                        }
                        .controlSize(.small)

                        if appState.mediaFolderBookmarkData != nil {
                            Button(role: .destructive) {
                                appState.mediaFolderBookmarkData = nil
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Oublier l'autorisation actuelle")
                        }
                    }
                }
                .padding(.top, 6)
            } label: {
                Text(isExpanded ? "Hide Details" : "Manage Library...")
                    .font(.callout)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .onAppear { computeLibrarySize() }
    }

    private func computeLibrarySize() {
        let urls = appState.velvetTracks.map(\.fileURL)
        Task.detached(priority: .utility) {
            var total: Int64 = 0
            let fm = FileManager.default
            for url in urls {
                if let size = try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64 {
                    total += size
                }
            }
            let formatted = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            await MainActor.run { librarySize = formatted }
        }
    }
}

// MARK: - Credits & Licenses

private struct CreditsSection: View {
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 16) {

                // ── Music Credits ──────────────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    Text("Music Credits")
                        .font(.subheadline.bold())

                    Text("Demo audio tracks included with Velvet Show use music by Kevin MacLeod.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        ForEach([
                            "Big Rock",
                            "Gymnopedie No. 1",
                            "Cold Funk",
                            "Infinite Perspective",
                            "Upbeat Forever"
                        ], id: \.self) { track in
                            Text("· \(track)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, 4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Music by Kevin MacLeod — incompetech.com")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Licensed under Creative Commons Attribution 4.0 International (CC BY 4.0)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Link("creativecommons.org/licenses/by/4.0/",
                             destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                            .font(.caption)
                    }
                }

                Divider()

                // ── Velvet Show ────────────────────────────────────────
                VStack(alignment: .leading, spacing: 4) {
                    Text("Velvet Show")
                        .font(.subheadline.bold())
                    Text("© Alexandre CHALON")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link("loveandlive.fr",
                         destination: URL(string: "https://www.loveandlive.fr")!)
                        .font(.caption)
                }
            }
            .padding(.top, 8)

        } label: {
            Text("Credits & Licenses")
                .font(.subheadline.bold())
        }
    }
}

