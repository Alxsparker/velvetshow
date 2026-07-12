//
//  ContentView.swift
//  VELVET SHOW
//
//  Vue racine de l'application, organisée autour des deux modes ShowBuddy :
//
//  ┌─────────────────────────────────────────────────────────────────┐
//  │ Toolbar : [ Track Library | Show Library ]   ...   [ Import.db ] │
//  ├─────────────────────────────────────────────────────────────────┤
//  │                                                                 │
//  │   Track Library (3 colonnes)        Show Library (2 colonnes)   │
//  │   ┌────────┬────────┬───────┐       ┌──────────┬──────────────┐ │
//  │   │ Catég. │ Morc.  │ Fiche │       │ Sets     │ Setlist      │ │
//  │   └────────┴────────┴───────┘       └──────────┴──────────────┘ │
//  └─────────────────────────────────────────────────────────────────┘
//
//  L'AppState est unique : changer de mode n'efface AUCUNE sélection,
//  on peut basculer librement entre l'édition et la performance.
//

import SwiftUI
import UniformTypeIdentifiers
import CoreMIDI
import AppKit

struct ContentView: View {

    // L'AppState est désormais injecté via l'environnement (cf.
    // `VELVET_SHOWApp`). Il est partagé avec la fenêtre Prompter.
    @Environment(AppState.self) private var appState
    @Environment(LicenseManager.self) private var licenseManager
    @Environment(BetaManager.self) private var betaManager
    @Environment(UpdateChecker.self) private var updateChecker
    @Environment(\.openWindow) private var openWindow

    // (Le Menu Settings ⚙️ + ses @State + sheets ont été déplacés dans
    //  SetsSidebar (ShowLibraryViews.swift) pour rejoindre la pilule
    //  Reset · + · Shows · Books.)

    var body: some View {
        // Pour binder dans la Picker, on a besoin d'une enveloppe Bindable
        // autour de l'observable injecté. C'est le pattern recommandé
        // depuis Swift 5.9 (`@Bindable var x = x` dans le body).
        @Bindable var appState = appState

        VStack(spacing: 0) {
            FixedAppToolbar(
                appState: appState,
                betaManager: betaManager,
                licenseManager: licenseManager,
                updateChecker: updateChecker
            ) {
                openWindow(id: PrompterView.windowID)
            }
            Group {
                switch appState.mode {
                case .trackLibrary:
                    TrackLibraryRoot(appState: appState)
                case .showLibrary:
                    ShowLibraryRoot(appState: appState)
                }
            }
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { appState.lastError != nil },
                set: { if !$0 { appState.lastError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(appState.lastError ?? "")
        }
        .onAppear {
            appState.refreshPrompterEnvironment()
            appState.checkAudioFileAccessibility()
        }
        // (Migration / Trash sheets déplacées dans SetsSidebar avec le menu Settings)
    }

}

private struct FixedAppToolbar: View {
    @Bindable var appState: AppState
    @Environment(\.openWindow) private var openWindow
    let betaManager: BetaManager
    let licenseManager: LicenseManager
    let updateChecker: UpdateChecker
    let openPrompter: () -> Void
    @State private var importSourceURL: IdentifiableURL?
    @State private var isCreatingVelvetShow = false
    @State private var isConfirmingResetAll = false
    @State private var isShowingStylesPanel = false
    @State private var isShowingMigrationSheet = false
    @State private var migrationResult: AppState.MigrationResult?
    @State private var isShowingVelvetTrash = false
    @State private var isShowingMediaLibraryRemap = false

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                leftControls
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()

                Color.clear
                    .frame(width: 180)

                rightControls
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .clipped()
            }
            .padding(.leading, 124)
            .padding(.trailing, 16)

            ModeSelector(selection: $appState.mode)
                .fixedSize(horizontal: true, vertical: false)
                .help("Switch between Songs and Shows")
                .anchorPreference(key: TourAnchorsKey.self, value: .bounds) {
                    [TourAnchor.sidebarModeSwitcher: $0]
                }
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
        .frame(height: 44)
        .background(.bar)
        .sheet(item: $importSourceURL) { item in
            AudioImportSheet(appState: appState, sourceURL: item.url)
        }
        .sheet(isPresented: $isCreatingVelvetShow) {
            VelvetShowEditorSheet(mode: .create, appState: appState)
        }
        .confirmationDialog(
            "Reset all shows?",
            isPresented: $isConfirmingResetAll,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                appState.resetAllShows()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Played songs will be moved back to remaining songs.")
        }
        .modifier(SettingsMenuSheetsModifier(
            appState: appState,
            isShowingStylesPanel: $isShowingStylesPanel,
            isShowingMediaLibraryRemap: $isShowingMediaLibraryRemap,
            isShowingMigrationSheet: $isShowingMigrationSheet,
            migrationResult: $migrationResult,
            isShowingVelvetTrash: $isShowingVelvetTrash
        ))
    }

    private var leftControls: some View {
        HStack(spacing: 14) {
            focusButton
                .frame(width: 116, alignment: .leading)

            modeSpecificControls
        }
    }

    private var rightControls: some View {
        HStack(spacing: 10) {
            MediaFolderWarningPill(appState: appState)

            DjayVinylButton(
                isArmed: appState.isDjayArmed,
                isPlaying: appState.audioEngine.state == .playing
            ) {
                if appState.isDjayArmed {
                    appState.isDjayArmed = false
                    return
                }
                if appState.audioEngine.state == .playing {
                    appState.isDjayArmed = true
                } else {
                    Task {
                        do { try await appState.performDJHandoff() }
                        catch { appState.lastError = error.localizedDescription }
                    }
                }
            }
            .help(appState.isDjayArmed
                  ? "\(appState.djHandoffDisplayName) armed — launches at end of current song. Click again to disarm."
                  : (appState.audioEngine.state == .playing
                     ? "Arm \(appState.djHandoffDisplayName) to launch automatically at end of this song"
                     : "Launch \(appState.djHandoffDisplayName) now"))

            if case .error = appState.saveStatus {
                SaveStatusPill(status: appState.saveStatus)
            }

            TrialStatusBadge(betaManager: betaManager, licenseManager: licenseManager)
            UpdateAvailableBadge(updateChecker: updateChecker)

            Button {
                openPrompter()
            } label: {
                Label("Prompter", systemImage: "rectangle.on.rectangle")
            }
            .labelStyle(.iconOnly)
            .tint(prompterTint)
            .help(prompterHelp)

            Button {
                appState.triggerPrompterPanic()
            } label: {
                Text(appState.isPanicPrompterVisible ? "🚨 PANIC ON" : "🚨 PANIC")
                    .font(.callout.weight(.black))
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .help("Show or hide the backup Prompter built into the main window (⌘⇧P)")
        }
    }

    @ViewBuilder
    private var modeSpecificControls: some View {
        switch appState.mode {
        case .trackLibrary:
            Button {
                importSong()
            } label: {
                Label("Import a Song", systemImage: "square.and.arrow.down")
            }
            .labelStyle(.iconOnly)
            .help("Import a Song")

        case .showLibrary:
            HStack(spacing: 8) {
                settingsMenu

                Button {
                    isConfirmingResetAll = true
                } label: {
                    Image(systemName: "arrow.counterclockwise.circle")
                }
                .disabled(appState.sets.isEmpty)
                .help("Reset all shows")

                Button {
                    isCreatingVelvetShow = true
                } label: {
                    Label("New Show", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .help("New Show")

                Button {
                    appState.toggleShowsSidebar()
                } label: {
                    Image(systemName: appState.showsSidebarVisibility == .detailOnly
                          ? "sidebar.left"
                          : "sidebar.leading")
                }
                .help(appState.showsSidebarVisibility == .detailOnly
                      ? "Show Shows sidebar"
                      : "Hide Shows sidebar")

                Button {
                    appState.isQuickLibraryVisible.toggle()
                } label: {
                    Image(systemName: appState.isQuickLibraryVisible
                          ? "books.vertical.fill"
                          : "books.vertical")
                }
                .keyboardShortcut("b", modifiers: .command)
                .help(appState.isQuickLibraryVisible
                      ? "Hide Tracks library (⌘B)"
                      : "Show Tracks library (⌘B)")
            }
        }
    }

    private var settingsMenu: some View {
        Menu {
            Picker("App theme", selection: $appState.appTheme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.label).tag(theme)
                }
            }
            Picker("Prompter theme", selection: $appState.prompterTheme) {
                ForEach(PrompterTheme.allCases) { theme in
                    Text(theme.label).tag(theme)
                }
            }
            Button("Styles & Colors...") {
                isShowingStylesPanel = true
            }
            Divider()
            Button {
                openWindow(id: "midiSettings")
            } label: {
                Label("Settings...", systemImage: "gearshape")
            }
            Button {
                isShowingMediaLibraryRemap = true
            } label: {
                Label("Change audio library...", systemImage: "folder.badge.gearshape")
            }
            Divider()
            Button {
                isShowingVelvetTrash = true
            } label: {
                let count = appState.trashedTracks.count
                Label(
                    count > 0 ? "Trash (\(count))..." : "Trash...",
                    systemImage: count > 0 ? "trash.fill" : "trash"
                )
            }
            if !appState.store.state.hasMigratedFromShowBuddy {
                Divider()
                if appState.database != nil {
                    Button {
                        isShowingMigrationSheet = true
                    } label: {
                        Label("Migrate to Velvet...", systemImage: "arrow.up.forward.app")
                    }
                } else {
                    Button {
                        presentDatabaseOpenPanel(appState: appState)
                    } label: {
                        Label("Import ShowBuddy.db...", systemImage: "tray.and.arrow.down")
                    }
                }
            }
        } label: {
            Label("Settings", systemImage: "gearshape")
        }
        .labelStyle(.iconOnly)
        .help("Themes, MIDI, audio library, trash, and migration")
    }

    private func importSong() {
        if appState.mediaRootURL != nil {
            if let url = pickAudioFile(
                title: "Import a Song into MediaFiles",
                prompt: "Import"
            ) {
                importSourceURL = IdentifiableURL(url: url)
            }
        } else {
            presentVelvetTrackImportPanel(appState: appState)
        }
    }

    private var focusButton: some View {
        let isTrackMode = appState.mode == .trackLibrary
        let isFocused = appState.trackLibraryVisibility == .detailOnly

        return Button {
            appState.toggleTrackLibraryColumns()
        } label: {
            Label("Focus", systemImage: "arrow.up.left.and.arrow.down.right")
                .labelStyle(.titleAndIcon)
        }
        .tint(isFocused ? VSColor.interactive : nil)
        .help(isFocused
              ? "Editor focus is on — click to show columns (T)"
              : "Editor focus: hide columns and use full width (T)")
        .disabled(!isTrackMode)
        .opacity(isTrackMode ? 1 : 0)
        .accessibilityHidden(!isTrackMode)
    }

    private var prompterTint: Color? {
        guard appState.isPrompterActive else { return nil }
        return appState.isSecondDisplayConnected ? .green : .orange
    }

    private var prompterHelp: String {
        if !appState.isPrompterActive { return "Open Prompter window" }
        return appState.isSecondDisplayConnected
            ? "Prompter open on second display (Sidecar / AirPlay / external)"
            : "Prompter open on Mac only (no second display detected)"
    }
}

// MARK: - DJ Handoff Vinyl Button

/// Toolbar button au look "vinyle jaune". Pastille jaune au centre, anneau
/// noir autour, trou central. Quand armé : halo orange pulsant pour signaler
/// que l'app externe attend la fin du morceau.
private struct DjayVinylButton: View {
    let isArmed: Bool
    let isPlaying: Bool
    let action: () -> Void
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Halo armé pulsant
                if isArmed {
                    Circle()
                        .stroke(Color.orange.opacity(pulse ? 0.25 : 0.75), lineWidth: 3)
                        .frame(width: 38, height: 38)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                }
                // Disque vinyle
                Circle().fill(Color.black).frame(width: 30, height: 30)
                Circle().stroke(Color.white.opacity(0.22), lineWidth: 0.6).frame(width: 30, height: 30)
                Circle().stroke(Color.white.opacity(0.14), lineWidth: 0.5).frame(width: 24, height: 24)
                Circle().stroke(Color.white.opacity(0.10), lineWidth: 0.5).frame(width: 18, height: 18)
                // Pastille jaune (label vinyle)
                Circle().fill(Color.yellow).frame(width: 14, height: 14)
                // Trou central
                Circle().fill(Color.black).frame(width: 3, height: 3)
            }
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("DJ handoff")
        .onAppear { pulse = true }
    }
}

private struct ModeSelector: View {
    @Binding var selection: LibraryMode

    var body: some View {
        HStack(spacing: 6) {
            modeButton("Songs", mode: .trackLibrary, color: .red)
            modeButton("Shows", mode: .showLibrary, color: .green)
        }
        .fixedSize()
    }

    private func modeButton(_ title: String, mode: LibraryMode, color: Color) -> some View {
        let isSelected = selection == mode

        return Button {
            selection = mode
        } label: {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 62, height: 28)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(color.gradient)
                            .shadow(color: color.opacity(0.35), radius: 5, x: 0, y: 2)
                    } else {
                        Capsule()
                            .fill(.clear)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Capsule unifiée for toutes les pastilles d'état de la toolbar :
/// icône + libellé + teinte. Source de vérité visuelle unique, pour
/// que DiffusionStatusPill et SaveStatusPill restent strictement
/// alignées (même typo, même padding, même radius).
private struct ToolbarStatusCapsule: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption.bold())
            Text(text)
                .font(.caption.bold())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
    }
}

/// Pastille unique synthétisant l'état de diffusion en concert.
///
/// Priorité décroissante (la première condition remplie gagne) :
///   1. PANIC actif         — rouge, prio max, masque tout le reste
///   2. Prompter on second display — vert, état idéal concert
///   3. Prompter sur Mac    — orange, oubli de Sidecar / AirPlay probable
///   4. Prompter closed      — orange, 2e écran présent mais fenêtre pas ouverte
///   5. Mac seul            — gris, état édition normal
///
/// Au survol, le tooltip détaille les trois conditions sous-jacentes
/// (écran / Prompter / secours) for ne pas perdre l'info de debug.
private struct DiffusionStatusPill: View {
    let isPanic: Bool
    let isPrompterActive: Bool
    let isSecondDisplayConnected: Bool

    private enum State {
        case panic, idealConcert, prompterOnMac, prompterClosed, macAlone

        var label: String {
            switch self {
            case .panic:           return "PANIC Active"
            case .idealConcert:    return "Prompter on second display"
            case .prompterOnMac:   return "Prompter on Mac"
            case .prompterClosed:  return "Prompter closed"
            case .macAlone:        return "Mac only"
            }
        }

        var systemImage: String {
            switch self {
            case .panic:           return "exclamationmark.triangle.fill"
            case .idealConcert:    return "display.2"
            case .prompterOnMac:   return "display"
            case .prompterClosed:  return "eye.slash"
            case .macAlone:        return "display"
            }
        }

        var color: Color {
            switch self {
            case .panic:           return VSColor.danger
            case .idealConcert:    return VSColor.playActive
            case .prompterOnMac:   return VSColor.warning
            case .prompterClosed:  return VSColor.warning
            case .macAlone:        return .secondary
            }
        }
    }

    private var state: State {
        if isPanic { return .panic }
        switch (isPrompterActive, isSecondDisplayConnected) {
        case (true, true):   return .idealConcert
        case (true, false):  return .prompterOnMac
        case (false, true):  return .prompterClosed
        case (false, false): return .macAlone
        }
    }

    var body: some View {
        let s = state
        ToolbarStatusCapsule(text: s.label, systemImage: s.systemImage, color: s.color)
            .help(tooltip)
    }

    private var tooltip: String {
        let ecran = isSecondDisplayConnected ? "second display connected" : "no second display"
        let prompter = isPrompterActive ? "Prompter open" : "Prompter closed"
        let secours = isPanic ? "Backup ON" : "Backup OFF"
        return "Display: \(ecran)\nPrompter: \(prompter)\nBackup: \(secours)"
    }
}

/// Pastille discrète indiquant l'état du `VelvetShowStore` : prêt,
/// modification non sauvegardée, sauvegarde en cours, sauvegardé, erreur.
/// Visible en permanence dans la toolbar for rassurer en concert.
private struct SaveStatusPill: View {
    let status: VelvetShowSaveStatus
    /// Animation de pulsation for l'état non-sauvegardé.
    @State private var pulsing = false

    var body: some View {
        ToolbarStatusCapsule(text: label, systemImage: status.systemImage, color: color)
            .overlay {
                // Bord clignotant uniquement en état dirty : signal discret
                // mais impossible at manquer en concert.
                if case .dirty = status {
                    Capsule()
                        .strokeBorder(VSColor.warning.opacity(pulsing ? 0.9 : 0.3), lineWidth: 1.5)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                                   value: pulsing)
                }
            }
            .onAppear { pulsing = true }
            .help(detail)
    }

    private var label: String {
        switch status {
        case .saved:   return "Saved"
        case .idle:    return "Ready"
        default:       return status.label
        }
    }

    private var color: Color {
        switch status {
        case .idle:    return .secondary
        case .dirty:   return VSColor.warning
        case .saving:  return .accentColor
        case .saved:   return VSColor.playActive
        case .error:   return VSColor.danger
        }
    }

    private var detail: String {
        switch status {
        case .idle:
            return "No pending changes."
        case .dirty:
            return "Unsaved changes; writing in ≤ 0.4 s."
        case .saving:
            return "Writing to Application Support/VELVET SHOW/VelvetShowState.json..."
        case .saved(let date):
            return "Last saved: \(Self.timeFormatter.string(from: date))."
        case .error(let message):
            return "Save error: \(message)"
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

// MARK: - Avertissement MediaFiles

/// Pastille d'avertissement discrète visible uniquement quand le dossier
/// MediaFiles est inaccessible ou stale, ou que >10 % des fichiers manquent.
private struct MediaFolderWarningPill: View {
    let appState: AppState

    private var message: String? {
        switch appState.mediaFolderStatus {
        case .stale:
            return "Audio folder: access expired; reselect the folder in Settings."
        case .inaccessible:
            return "Audio folder: folder unavailable; reselect the folder in Settings."
        case .notSet where appState.isLoaded:
            return "Audio folder: not configured; set it up in Settings."
        default:
            if appState.missingAudioFraction > 0.1 {
                return "\(Int(appState.missingAudioFraction * 100))% files missing"
            }
            return nil
        }
    }

    var body: some View {
        if let msg = message {
            ToolbarStatusCapsule(text: msg, systemImage: "exclamationmark.triangle.fill", color: VSColor.warning)
                .help("Some songs will be silent. Go to MediaFiles to reselect the folder.")
        }
    }

}

// MARK: - Import ShowBuddy.db

/// Panneau macOS explicite for choisir la base ShowBuddy.
///
/// On évite ici `fileImport` parce qu'il peut rester silencieux selon
/// le type UTI réellement attribué au fichier `.db` par Endder. Le panneau
/// accepte n'importe quel fichier ; `ShowBuddyDatabase` reste la validation
/// réelle et ouvre toujours SQLite en lecture seule.
@MainActor
func presentDatabaseOpenPanel(appState: AppState) {
    let panel = NSOpenPanel()
    panel.title = "Import ShowBuddy.db"
    panel.message = "Select the ShowBuddy.db file to explore."
    panel.prompt = "Import"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = true

    guard panel.runModal() == .OK, let url = panel.url else { return }

    guard !url.hasDirectoryPath else {
        appState.lastError = "Select a ShowBuddy.db file, not a folder."
        return
    }

    appState.open(url: url)

    // Si l'import a réussi mais que `SbsBackup/MediaFiles` n'a pas été
    // détecté automatiquement, on donne immédiatement la main à
    // l'utilisateur for choisir le dossier. Le dispatch évite d'empiler
    // deux NSOpenPanel dans le même cycle modal.
    if appState.isLoaded, appState.mediaRootURL == nil {
        DispatchQueue.main.async {
            presentMediaFilesOpenPanel(appState: appState)
        }
    }
}

// MARK: - Import trims ShowBuddy (utilisateurs déjà migrés)

/// Ouvre un panneau de sélection for choisir ShowBuddy.db, lit uniquement
/// les LightShows (TrimStart/TrimEnd), et retourne le nombre de trims importeds.
/// En cas d'annulation retourne nil. Les erreurs sont posées dans `appState.lastError`.
@MainActor
func presentTrimImportPanel(appState: AppState) -> Int? {
    let panel = NSOpenPanel()
    panel.title = "Import ShowBuddy Trims"
    panel.message = "Select your ShowBuddy.db file to read song starts and endings."
    panel.prompt = "Import"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = true

    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    guard !url.hasDirectoryPath else {
        appState.lastError = "Select a ShowBuddy.db file, not a folder."
        return nil
    }

    do {
        return try appState.importShowBuddyTrimsFromURL(url)
    } catch {
        appState.lastError = "ShowBuddy trim import: \(error.localizedDescription)"
        return nil
    }
}

// MARK: - Correction sémantique trims ShowBuddy

/// Ouvre un panneau de sélection for choisir ShowBuddy.db, relit les
/// LightShows ET les AudioFiles (pour les durées), recalcule la conversion
/// TrimEnd tail-offset → position absolue, et réécrit tous les trims issus
/// de ShowBuddy. Les trims Velvet manuels (IDs absents de ShowBuddy) ne sont
/// pas touchés. Un backup `.fix.bak` est créé avant toute écriture.
///
/// Retourne (fixed, skipped) ou nil si annulé. Errors → `appState.lastError`.
@MainActor
func presentTrimFixPanel(appState: AppState) -> (fixed: Int, skipped: Int)? {
    let panel = NSOpenPanel()
    panel.title = "Fix ShowBuddy Trims"
    panel.message = "Select ShowBuddy.db to recalculate song endings (TrimEnd tail offset → absolute position)."
    panel.prompt = "Fix"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = true

    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    guard !url.hasDirectoryPath else {
        appState.lastError = "Select a ShowBuddy.db file, not a folder."
        return nil
    }

    do {
        return try appState.fixShowBuddyTrimsFromURL(url)
    } catch {
        appState.lastError = "ShowBuddy trim fix: \(error.localizedDescription)"
        return nil
    }
}

@MainActor func presentVelvetTrackImportPanel(appState: AppState) {
    let panel = NSOpenPanel()
    panel.title = "Import a Song"
    panel.message = "Select an audio file to copy into VELVET SHOW/Media."
    panel.prompt = "Import"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.audio]

    guard panel.runModal() == .OK, let url = panel.url else { return }
    let allowed = ["mp3", "wav", "aiff", "aif", "m4a"]
    guard allowed.contains(url.pathExtension.lowercased()) else {
        appState.lastError = "Unsupported format. Accepted formats: mp3, wav, aiff, m4a."
        return
    }
    appState.importVelvetTrack(from: url)
}

func presentMediaFilesOpenPanel(appState: AppState) {
    let panel = NSOpenPanel()
    panel.title = "Choose MediaFiles Folder"
    panel.message = "Select the MediaFiles folder from the ShowBuddy backup."
    panel.prompt = "Choose"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = true

    guard panel.runModal() == .OK, let url = panel.url else { return }
    appState.setMediaFolder(url)
}

// MARK: - Migration ShowBuddy → Velvet natif

struct MigrationSheet: View {
    let appState: AppState
    @Binding var result: AppState.MigrationResult?
    @Environment(\.dismiss) private var dismiss
    @State private var preview: AppState.MigrationConflictPreview?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Migrate to native Velvet Show", systemImage: "arrow.up.forward.app")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 10) {
                migrationPoint("Songs, shows, memos, and MIDI copied into Velvet Show")
                migrationPoint("Audio files stay in place; nothing is duplicated")
                migrationPoint("ShowBuddy.db is never modified or moved")
                migrationPoint("A dated backup is created automatically before migration")
            }
            .padding(14)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

            if let preview {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Songs to import").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(preview.tracksToConvert)").bold().monospacedDigit()
                    }
                    HStack {
                        Text("Shows to import").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(preview.showsToConvert)").bold().monospacedDigit()
                    }
                    if preview.hasConflicts {
                        Divider()
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Conflicts detected").font(.callout.bold())
                                if preview.tracksConflicted > 0 {
                                    Text("\(preview.tracksConflicted) song(s) already in your library; skipped.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                if preview.showsConflicted > 0 {
                                    Text("\(preview.showsConflicted) show(s) already in your library; skipped.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(10)
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                    }
                }
                .font(.callout)
                .padding(14)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }

            Text("After migration, Velvet Show works independently. You can open ShowBuddy at any time; nothing changed on its side.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Migrate Now") {
                    result = appState.migrateFromShowBuddy()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear { preview = appState.previewMigration() }
    }

    private func migrationPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(text).font(.callout)
        }
    }
}

struct MigrationResultSheet: View {
    let result: AppState.MigrationResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Migration Complete", systemImage: "checkmark.seal.fill")
                .font(.title2.bold())
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 8) {
                resultRow("Songs Imported",   "\(result.tracksConverted)")
                resultRow("Shows Imported",   "\(result.showsConverted)")
                resultRow("Memos Transferred",    "\(result.memosSeedées)")
                resultRow("MIDI Events Copied",  "\(result.midiEventsConverted)")
                if result.tracksConflicted > 0 || result.showsConflicted > 0 {
                    Divider()
                    if result.tracksConflicted > 0 {
                        resultRow("Songs Skipped (Already Present)", "\(result.tracksConflicted)")
                            .foregroundStyle(.orange)
                    }
                    if result.showsConflicted > 0 {
                        resultRow("Shows Skipped (Already Present)", "\(result.showsConflicted)")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(14)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

            if let backupURL = result.backupURL {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                    Text("Backup created: \(backupURL.lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Velvet Show now works independently. ShowBuddy.db is intact; you can open it in ShowBuddy at any time.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("OK") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func resultRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).bold().monospacedDigit()
        }
        .font(.callout)
    }
}

// MARK: - Empty state partagé entre les deux modes

private struct EmptyLibraryView: View {
    let appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No database loaded")
                .font(.title2)
            Text("Select your ShowBuddy.db file to explore its songs and sets.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Choose a File...") {
                presentDatabaseOpenPanel(appState: appState)
            }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("o", modifiers: .command)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: ───────────────────────────────────────────────────────────
// MARK: Track Library
// MARK: ───────────────────────────────────────────────────────────

private struct TrackLibraryRoot: View {
    @Bindable var appState: AppState

    private var isColumnsVisible: Bool {
        appState.trackLibraryVisibility != .detailOnly
    }

    var body: some View {
        if isColumnsVisible {
            HStack(spacing: 0) {
                CategoriesSidebar(appState: appState)
                    .frame(width: 270)
                Divider()

                CategoryTracksColumn(appState: appState)
                    .frame(width: 340)
                Divider()

                TrackDetailColumn(appState: appState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            TrackDetailColumn(appState: appState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Wrapper Identifiable for URL, nécessaire for .sheet(item:).
private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

private struct CategoriesSidebar: View {
    @Bindable var appState: AppState
    @State private var importSourceURL: IdentifiableURL?

    var body: some View {
        List(selection: $appState.selectedCategoryID) {
            ForEach(appState.categories) { category in
                Text(category.name)
                    .badge(category.tracks.count)
            }
        }
        .listStyle(.inset)
        .contentMargins(.vertical, 0, for: .scrollContent)
        .sheet(item: $importSourceURL) { item in
            AudioImportSheet(appState: appState, sourceURL: item.url)
        }
        .overlay {
            if appState.categories.isEmpty {
                ContentUnavailableView {
                    Label("No Songs", systemImage: "music.note")
                } description: {
                    Text("Import your first audio songs to get started.")
                } actions: {
                    Button("Import Songs") {
                        presentVelvetTrackImportPanel(appState: appState)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

private struct CategoryTracksColumn: View {
    @Bindable var appState: AppState
    @State private var trackSearchText: String = ""
    @State private var editingColorTrack: AudioFile?
    @State private var trashingVelvetTrack: VelvetTrack?
    @FocusState private var searchFocused: Bool

    private var tracks: [AudioFile] {
        let needle = trackSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !needle.isEmpty {
            return appState.audioFiles
                .filter { ($0.name ?? "").lowercased().contains(needle) }
                .sorted { ($0.name ?? "") < ($1.name ?? "") }
        }
        guard let id = appState.selectedCategoryID,
              let cat = appState.categories.first(where: { $0.id == id })
        else { return [] }
        return cat.tracks
    }

    private var selectedVelvetShow: ShowSet? {
        guard let setID = appState.selectedSetID,
              let set = appState.sets.first(where: { $0.setID == setID }),
              appState.isVelvetShow(set) else { return nil }
        return set
    }

    private var selectedVelvetShowName: String? {
        selectedVelvetShow?.name
    }

    var body: some View {
        VStack(spacing: 0) {
            // Champ de recherche — directement au-dessus de la liste qu'il filtre.
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(trackSearchText.isEmpty ? .secondary : .primary)
                    .font(.system(size: 12))
                TextField("Search for a song...", text: $trackSearchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($searchFocused)
                    .onSubmit { searchFocused = false }
                    .onKeyPress(.escape) {
                        trackSearchText = ""
                        searchFocused = false
                        return .handled
                    }
                if !trackSearchText.isEmpty {
                    Button {
                        trackSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Clear search (Esc)")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 0))
            .overlay(alignment: .bottom) {
                Divider()
            }
            // ⌘F — invisible button anchored to the search bar itself
            .background {
                Button("") { searchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .help("Search (⌘F)")
            }

            // Track Library classique : une ligne = une seule action, sélectionner.
            List {
                ForEach(tracks) { track in
                    ClassicTrackRow(
                        track: track,
                        tint: appState.color(for: track),
                        risk: appState.riskLevel(for: track),
                        isSelected: appState.selectedAudioFileID == track.audioFileID,
                        selectedVelvetShowName: selectedVelvetShowName,
                        addToSelectedVelvetShow: {
                            if let set = selectedVelvetShow {
                                appState.addTrack(track, to: set)
                            }
                        },
                        onChangeColor: { editingColorTrack = track },
                        onTrashTrack: track.audioFileID < 0 ? {
                            trashingVelvetTrack = appState.velvetTrack(for: track)
                        } : nil,
                        hasVideo: appState.video(for: track) != nil
                    ) {
                        appState.selectedAudioFileID = track.audioFileID
                        appState.selectedCategoryID = appState.categoryID(for: track)
                        appState.load(track: track)
                    }
                }
            }
            .listStyle(.inset)
            .contentMargins(.vertical, 0, for: .scrollContent)
            .overlay {
                if appState.selectedCategoryID == nil && trackSearchText.isEmpty {
                    ContentUnavailableView(
                        "Choose a Category",
                        systemImage: "folder",
                        description: Text("Select a category to see its songs.")
                    )
                } else if tracks.isEmpty {
                    ContentUnavailableView(
                        trackSearchText.isEmpty ? "Empty Category" : "No Results",
                        systemImage: "music.note",
                        description: Text(trackSearchText.isEmpty
                                          ? "No songs in this category."
                                          : "No song matches \"\(trackSearchText)\".")
                    )
                }
            }
        }
        .sheet(item: $editingColorTrack) { track in
            TrackColorSheet(track: track, appState: appState)
        }
        .sheet(item: $trashingVelvetTrack) { velvetTrack in
            TrackDeleteSheet(track: velvetTrack) {
                trashingVelvetTrack = nil
            }
            .environment(appState)
        }
    }
}

private struct ClassicTrackRow: View {
    let track: AudioFile
    let tint: Color
    let risk: TrackRiskLevel
    let isSelected: Bool
    let selectedVelvetShowName: String?
    let addToSelectedVelvetShow: (() -> Void)?
    var onChangeColor: (() -> Void)? = nil
    var onTrashTrack: (() -> Void)? = nil
    /// True quand un fichier vidéo est associé à ce morceau — affiche une
    /// petite icône 🎥 à droite du nom. Calculé par l'appelant via
    /// `appState.video(for:)` pour éviter une dépendance environnement ici.
    var hasVideo: Bool = false
    let select: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: select) {
                HStack(spacing: 10) {
                    // Barre verticale de couleur de style — porteur d'info
                    // sans aspect décoratif. La note de musique a été
                    // retirée : c'est une liste de songs, pas besoin de
                    // le redire ligne par ligne.
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(tint)
                        .frame(width: 3, height: 16)
                        .onDrag {
                            NSItemProvider(object: String(track.audioFileID) as NSString)
                        }
                    Text(track.name ?? "Untitled")
                        .font(.system(size: 15))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if hasVideo {
                        Image(systemName: "video.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .help("This song has a Prompter video attached")
                    }
                }
                .contentShape(Rectangle())
                .padding(.vertical, 1)
            }
            .buttonStyle(.plain)

            if let onTrashTrack {
                Button(role: .destructive) {
                    onTrashTrack()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .opacity(isHovering || isSelected ? 0.85 : 0)
                .help("Move to Velvet Trash")
                .accessibilityLabel("Move song to Velvet Trash")
            }
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            if let selectedVelvetShowName, let addToSelectedVelvetShow {
                Button("Add to \(selectedVelvetShowName)") {
                    addToSelectedVelvetShow()
                }
            }
            if let onChangeColor {
                Button("Change Color...") { onChangeColor() }
            }
            if let onTrashTrack {
                Divider()
                Button("Move to Velvet Trash...", role: .destructive) {
                    onTrashTrack()
                }
            }
        }
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
    }
}

struct RiskBadge: View {
    let risk: TrackRiskLevel
    var compact: Bool = false

    var body: some View {
        Text(compact ? compactLabel : risk.detail)
            .font(.caption2.bold())
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .help(risk.detail)
    }

    private var compactLabel: String {
        switch risk {
        case .unknown: return "Jamais"
        case .recent: return "✓ Recent"
        case .sixMonths: return "⚠️ 6m"
        case .oneYear: return "⚠️⚠️ 1 an"
        }
    }

    private var foreground: Color {
        switch risk {
        case .recent: return .green
        case .sixMonths: return VSColor.warning
        case .oneYear, .unknown: return .red
        }
    }

    private var background: Color { foreground.opacity(0.13) }
}

private struct VelvetTrackEditorSheet: View {
    let track: AudioFile
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var selectedGenre: ConcertGenre
    @State private var note: String
    @State private var usesCustomColor: Bool
    @State private var color: Color
    @State private var tempoText: String

    private static let editableGenres: [ConcertGenre] = ConcertGenre.allCases.filter { $0 != .all }

    init(track: AudioFile, appState: AppState) {
        self.track = track
        self.appState = appState
        let velvet = appState.velvetTrack(for: track)
        _title = State(initialValue: velvet?.title ?? track.name ?? "")
        let currentGenre = appState.concertGenre(for: track)
        _selectedGenre = State(initialValue: currentGenre == .all ? .other : currentGenre)
        _note = State(initialValue: velvet?.note ?? "")
        _usesCustomColor = State(initialValue: velvet?.colorHex != nil)
        _color = State(initialValue: Color(hex: velvet?.colorHex ?? 0x00C8FF))
        _tempoText = State(initialValue: velvet?.tempo.map { String(format: "%.1f", $0) } ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Velvet Song Metadata", systemImage: "music.note")
                .font(.title3.bold())
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
            HStack {
                Text("Genre")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Genre", selection: $selectedGenre) {
                    ForEach(Self.editableGenres) { genre in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(appState.color(for: genre))
                                .frame(width: 10, height: 10)
                            Text(genre.label)
                        }
                        .tag(genre)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }
            TextField("Tempo optionnel", text: $tempoText)
                .textFieldStyle(.roundedBorder)
            Toggle("Custom Color", isOn: $usesCustomColor)
            if usesCustomColor {
                ColorPicker("Color", selection: $color, supportsOpacity: false)
            }
            TextEditor(text: $note)
                .frame(minHeight: 90)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary, lineWidth: 1)
                }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    appState.updateVelvetTrack(
                        track,
                        title: title,
                        genre: selectedGenre.rawValue,
                        note: note,
                        color: usesCustomColor ? color : nil,
                        tempo: Double(tempoText.replacingOccurrences(of: ",", with: "."))
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 420)
    }
}

private struct TrackDetailColumn: View {
    let appState: AppState

    private var track: AudioFile? {
        guard let id = appState.selectedAudioFileID else { return nil }
        return appState.audioFilesByID[id]
    }

    var body: some View {
        if let track {
            TrackEditView(track: track, appState: appState)
        } else {
            ContentUnavailableView(
                "Select a Song",
                systemImage: "waveform",
                description: Text("The edit sheet will appear here.")
            )
        }
    }
}

/// Fiche d'édition d'un song (Phase 2 = lecture seule).
///
/// On affiche aujourd'hui : nom, chemin, note, durée, LightShows associés,
/// ShowMemos avec leurs MidiEvents start / end.
///
/// On y branchera plus tard : waveform / timeline, paroles éditables,
/// trim start / end, tempo, volume, déclenchement audio / MIDI.
private struct TrackEditView: View {
    let track: AudioFile
    let appState: AppState
    @State private var isShowingTimelineEditor = false
    @State private var isShowingLyricsImport = false
    @State private var isEditingVelvetTrack = false
    @State private var trashingVelvetTrack: VelvetTrack?
    @State private var replaceSourceURL: IdentifiableURL?

    var body: some View {
        TimelineEditorView(track: track, appState: appState, isEmbedded: true)
            .id(track.audioFileID)
        .sheet(isPresented: $isShowingTimelineEditor) {
            TimelineEditorView(track: track, appState: appState)
                .id(track.audioFileID)
        }
        .sheet(isPresented: $isShowingLyricsImport) {
            LyricsImportSheet(
                track: track,
                appState: appState,
                existingMemos: appState.editableMemos(for: track),
                initialImportMode: .replace,
                onImport: { importedMemos in
                    appState.saveEditableMemos(importedMemos, for: track)
                }
            )
        }
        .sheet(isPresented: $isEditingVelvetTrack) {
            VelvetTrackEditorSheet(track: track, appState: appState)
        }
        .sheet(item: $trashingVelvetTrack) { velvetTrack in
            TrackDeleteSheet(track: velvetTrack) {
                trashingVelvetTrack = nil
            }
            .environment(appState)
        }
        .sheet(item: $replaceSourceURL) { item in
            AudioReplaceSheet(appState: appState, track: track, newURL: item.url)
        }
    }

    // MARK: - Données dérivées

    private var lightShows: [LightShow] { appState.lightShows(for: track) }
    private var memos: [ShowMemo]       { appState.memos(for: track) }

    private var durationString: String {
        guard let secs = track.lengthSecs, secs > 0 else { return "—" }
        return Self.minutesSeconds(secs)
    }

    private var lastPlayedString: String {
        guard let date = appState.lastPlayedDate(for: track) else { return "Jamais" }
        return Self.dateFormatter.string(from: date)
    }

    // MARK: - En-tête

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name ?? "Untitled").font(.title).bold()
                if let cat = appState.selectedCategoryID {
                    Text(cat).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                isShowingTimelineEditor = true
            } label: {
                Label("Edit Timeline", systemImage: "timeline.selection")
            }
            .buttonStyle(.borderedProminent)
            Button {
                isShowingLyricsImport = true
            } label: {
                Label("Import Lyrics", systemImage: "text.quote")
            }
            .buttonStyle(.bordered)
            Button {
                if let url = pickAudioFile(
                    title: "Choose the New Audio File",
                    prompt: "Replace"
                ) {
                    replaceSourceURL = IdentifiableURL(url: url)
                }
            } label: {
                Label("Replace l'audio", systemImage: "arrow.2.circlepath")
            }
            .buttonStyle(.bordered)
            .help("Physically replaces this song’s audio file. All Velvet data (memos, cue points, trims...) is preserved.")
            Text(durationString)
                .font(.title3)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Carte "Informations"

    private var infoCard: some View {
        Card(title: "Informations", systemImage: "info.circle") {
            LabeledContent("Source", value: appState.isVelvetTrack(track) ? "Velvet" : "ShowBuddy")
            if let velvetTrack = appState.velvetTrack(for: track) {
                LabeledContent("Genre", value: velvetTrack.genre.isEmpty ? "—" : velvetTrack.genre)
                LabeledContent("Tempo", value: velvetTrack.tempo.map { String(format: "%.1f BPM", $0) } ?? "—")
                if !velvetTrack.note.isEmpty {
                    LabeledContent("Note") {
                        Text(velvetTrack.note).textSelection(.enabled)
                    }
                }
                HStack(spacing: 8) {
                    Button {
                        isEditingVelvetTrack = true
                    } label: {
                        Label("Edit", systemImage: "slider.horizontal.3")
                    }
                    .controlSize(.small)
                    Button {
                        trashingVelvetTrack = velvetTrack
                    } label: {
                        Label("Move to Trash", systemImage: "trash")
                    }
                    .controlSize(.small)
                    .tint(.red)
                }
            }
            LabeledContent("Duration", value: durationString)
            LabeledContent("Risque") {
                RiskBadge(risk: appState.riskLevel(for: track))
            }
            LabeledContent("Last Played", value: lastPlayedString)
            LabeledContent("Chemin") {
                Text(track.path ?? "—")
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            if let note = track.note, !note.isEmpty {
                LabeledContent("Note") {
                    Text(note).textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Carte "Associated Shows"

    private var lightShowsCard: some View {
        if lightShows.isEmpty { return AnyView(EmptyView()) }
        return AnyView(Card(
            title: "Associated Shows (\(lightShows.count))",
            systemImage: "wand.and.stars"
        ) {
            ForEach(Array(lightShows.enumerated()), id: \.element.id) { index, show in
                VStack(alignment: .leading, spacing: 2) {
                    Text(show.name ?? "(sans nom)").bold()
                    HStack(spacing: 16) {
                        if let tempo = show.tempo {
                            Text("Tempo : \(tempo, specifier: "%.1f")")
                        }
                        if let vol = show.audioVolume {
                            Text("Volume : \(vol, specifier: "%.2f")")
                        }
                        if let trimStart = show.trimStart {
                            Text("Trim start : \(trimStart, specifier: "%.2f")")
                        }
                        if let trimEnd = show.trimEnd {
                            Text("Trim end : \(trimEnd, specifier: "%.2f")")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if index < lightShows.count - 1 {
                    Divider().padding(.vertical, 4)
                }
            }
        })
    }

    // MARK: - Carte "Memos & MIDI"

    private var memosCard: some View {
        Card(
            title: "Memos & MIDI (\(memos.count))",
            systemImage: "note.text"
        ) {
            ForEach(Array(memos.enumerated()), id: \.element.id) { index, memo in
                memoRow(memo)
                if index < memos.count - 1 {
                    Divider().padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func memoRow(_ memo: ShowMemo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Ligne 1 : titre du mémo + timecode.
            HStack(alignment: .firstTextBaseline) {
                Text(memo.shortName ?? "Memo").bold()
                Spacer()
                if let t = memo.memoTime {
                    Text(Self.timecode(t))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            // Ligne 2 : texte du mémo (paroles, count-in, etc.).
            if let memoText = memo.memo, !memoText.isEmpty {
                Text(memoText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            // Ligne 3 : Start / End MIDI event — IDs visibles + détail
            //
            // L'utilisateur veut explicitement voir StartMidiEventID et
            // EndMidiEventID bruts (validation d'import), pas seulement
            // les noms d'event.
            midiSlot(label: "Start",
                     iconStart: "play.circle",
                     iconStartFilled: "play.circle.fill",
                     rawID: memo.startMidiEventID)
            midiSlot(label: "End",
                     iconStart: "stop.circle",
                     iconStartFilled: "stop.circle.fill",
                     rawID: memo.endMidiEventID)
        }
    }

    /// Affiche un "slot" MIDI (Start ou End) d'un mémo :
    ///   - l'ID brut StartMidiEventID / EndMidiEventID (ou "—" si NULL) ;
    ///   - le MidiEvent associé (nom + catégorie) ;
    ///   - les MidiMessages associés en clair (humanDescription) ;
    ///   - un bouton "Simuler l'envoi" qui n'envoie rien et écrit dans
    ///     le journal `appState.midiLog`.
    @ViewBuilder
    private func midiSlot(
        label: String,
        iconStart: String,
        iconStartFilled: String,
        rawID: Int64?
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: rawID != nil ? iconStartFilled : iconStart)
                Text(label).bold()
            }
            .font(.caption)

            if let event = appState.midiEvent(id: rawID) {
                let messages = appState.midiMessages(for: event)

                // Nom + catégorie + bouton de déclenchement.
                HStack(spacing: 8) {
                    Text(event.name ?? "(sans nom)").bold()
                    if let cat = event.category, !cat.isEmpty {
                        Text(cat)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                    Spacer()
                    Button {
                        appState.dispatch(event: event)
                    } label: {
                        Label("Send", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }

                // Détail des messages MIDI.
                if messages.isEmpty {
                    Text("No MidiMessage attached to this event.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(messages) { msg in
                        midiMessageDetail(msg)
                    }
                }
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: 6))
    }

    /// Ligne d'un MidiMessage : description lisible + intention MaestroDMX.
    @ViewBuilder
    private func midiMessageDetail(_ msg: MidiMessage) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(msg.humanDescription)
                .font(.callout)

            if let maestro = msg.maestroDescription {
                HStack(spacing: 4) {
                    Image(systemName: "wand.and.rays")
                    Text("MaestroDMX : \(maestro)")
                }
                .font(.callout)
                .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers de formatage

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy HH:mm"
        return formatter
    }()

    private static func minutesSeconds(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    private static func timecode(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Track Library Timeline Editor


/// Petite carte de section, factorisée for la fiche d'édition.
private struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}



// Remaining views extracted to dedicated files:
// - MidiSettingsView.swift
// - ShowLibraryViews.swift
// - ConcertViews.swift
// - TimelineEditor.swift
