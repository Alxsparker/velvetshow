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
    @Environment(\.openWindow) private var openWindow

    @State private var isShowingStylesPanel = false
    @State private var isShowingMigrationSheet = false
    @State private var migrationResult: AppState.MigrationResult?
    @State private var isShowingVelvetTrash = false
    @State private var isShowingMediaLibraryRemap = false

    var body: some View {
        // Pour binder dans la Picker, on a besoin d'une enveloppe Bindable
        // autour de l'observable injecté. C'est le pattern recommandé
        // depuis Swift 5.9 (`@Bindable var x = x` dans le body).
        @Bindable var appState = appState

        Group {
            switch appState.mode {
            case .trackLibrary:
                TrackLibraryRoot(appState: appState)
            case .showLibrary:
                ShowLibraryRoot(appState: appState)
            }
        }
        .toolbar {

            // ── Centre : sélecteur de mode ────────────────────────────────
            // Ancré au centre de la title bar — toujours visible quel que
            // soit le remplissage des deux côtés.
            ToolbarItem(placement: .principal) {
                ModeSelector(selection: $appState.mode)
                .fixedSize(horizontal: true, vertical: false)
                .help("Switch between Songs and Shows")
                .anchorPreference(key: TourAnchorsKey.self, value: .bounds) {
                    [TourAnchor.sidebarModeSwitcher: $0]
                }
            }


            // ── Navigation : focus colonnes Track Library ────────────────
            // Visible uniquement en Track Library. Masque/restaure les deux
            // colonnes gauches for que l'éditeur occupe toute la largeur.
            // Raccourci T (même touche que Quick Library en Show Library).
            if appState.mode == .trackLibrary {
                ToolbarItem(placement: .navigation) {
                    Button {
                        appState.toggleTrackLibraryColumns()
                    } label: {
                        Image(systemName: appState.trackLibraryVisibility == .detailOnly
                              ? "sidebar.left"           // colonnes masquées → cliquer = les afficher
                              : "rectangle.split.3x1")  // colonnes visibles → cliquer = focus éditeur
                    }
                    .help(appState.trackLibraryVisibility == .detailOnly
                          ? "Show columns (T)"
                          : "Editor focus: hide columns (T)")
                }
            }

            // ── Secondaire (gauche du principal) : admin uniquement ──────
            ToolbarItemGroup(placement: .secondaryAction) {

                // Alerte dossier audio (conditionnelle, lecture seule)
                MediaFolderWarningPill(appState: appState)

                // ── 4. Administration — relégué at gauche, hors zone fonctionnelle ─
                // Actions rarement utilisées pendant une prestation.
                Menu {
                    // — Apparence ——————————————————————————————————————————
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

                    // — Audio Library ————————————————————————————————
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

                    // — Gestion ———————————————————————————————————————————
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
                .help("Themes, MIDI, audio library, trash, and migration")
                .anchorPreference(key: TourAnchorsKey.self, value: .bounds) {
                    [TourAnchor.settingsButton: $0]
                }
                // Sheets rattachées au menu — s'ouvrent via les @State ci-dessus.
                .sheet(isPresented: $isShowingStylesPanel) {
                    StylesColorsPanel(appState: appState)
                }
                .sheet(isPresented: $isShowingMediaLibraryRemap) {
                    MediaLibraryRemapView {
                        isShowingMediaLibraryRemap = false
                    }
                    .environment(appState)
                }

            }

            // ── Droite : bloc système + PANIC ────────────────────────────
            // Tout en .primaryAction for que ces éléments apparaissent
            // at droite du principal (mode picker), adjacents at PANIC.
            // Déclaré avant PANIC → affiché at sa gauche immédiate.
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 6) {
                    // Prompter (gestion des fenêtres / écrans)
                    Button {
                        openWindow(id: PrompterView.windowID)
                    } label: {
                        Label("Prompter", systemImage: "rectangle.on.rectangle")
                    }
                    .help("Open the Prompter window on a second display or iPad (Sidecar / AirPlay)")

                    // Mac seul / état diffusion
                    DiffusionStatusPill(
                        isPanic: appState.isPanicPrompterVisible,
                        isPrompterActive: appState.isPrompterActive,
                        isSecondDisplayConnected: appState.isSecondDisplayConnected
                    )

                    // Sauvegarde
                    SaveStatusPill(status: appState.saveStatus)
                }
            }

            // ── Extrême droite : 🚨 PANIC ─────────────────────────────────
            ToolbarItem(placement: .primaryAction) {
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
        .sheet(isPresented: $isShowingMigrationSheet) {
            MigrationSheet(appState: appState, result: $migrationResult)
        }
        .sheet(item: $migrationResult) { result in
            MigrationResultSheet(result: result)
        }
        .sheet(isPresented: $isShowingVelvetTrash) {
            VelvetTrashSheet { isShowingVelvetTrash = false }
                .environment(appState)
        }
    }

}

private struct ModeSelector: View {
    @Binding var selection: LibraryMode
    @Namespace private var highlightNamespace

    var body: some View {
        HStack(spacing: 8) {
            modeButton(.trackLibrary)
            modeButton(.showLibrary)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
    }

    private func modeButton(_ mode: LibraryMode) -> some View {
        let isSelected = selection == mode
        let title = modeSelectorTitle(for: mode)

        return Button {
            withAnimation(.snappy(duration: 0.20)) {
                selection = mode
            }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .lineLimit(1)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Capsule()
                                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.10), radius: 5, x: 0, y: 2)
                            .matchedGeometryEffect(id: "mode-selector-highlight", in: highlightNamespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func modeSelectorTitle(for mode: LibraryMode) -> String {
        switch mode {
        case .trackLibrary: return "Songs"
        case .showLibrary: return "Shows"
        }
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
private func presentDatabaseOpenPanel(appState: AppState) {
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

private struct MigrationSheet: View {
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

private struct MigrationResultSheet: View {
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

    var body: some View {
        // Mode focus (bouton ↙ Columns) : fiche seule, pleine largeur.
        // NavigationSplitView ne répond pas de façon fiable aux changements
        // programmatiques de columnVisibility sur macOS — on gère le switch
        // manuellement for garantir un comportement prévisible.
        if appState.trackLibraryVisibility == .detailOnly {
            TrackDetailColumn(appState: appState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Mode normal : 3 colonnes via NavigationSplitView.
            // `.prominentDetail` = la fiche domine, les colonnes gauches
            // démarrent compactes. `navigationSplitViewColumnWidth` est
            // l'API native — respectée et persistée correctement par macOS.
            NavigationSplitView(columnVisibility: $appState.trackLibraryVisibility) {
                CategoriesSidebar(appState: appState)
                    .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 280)
            } content: {
                CategoryTracksColumn(appState: appState)
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
            } detail: {
                TrackDetailColumn(appState: appState)
            }
            .navigationSplitViewStyle(.prominentDetail)
            .toolbar(removing: .sidebarToggle)
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
        .navigationTitle("Categories")
        .toolbar {
            Button {
                // Si MediaFiles est configuré, utilise le nouveau flux d'import
                // avec sélection de catégorie. Sinon, fallback to l'ancien
                // import dans AppSupport/Media.
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
            } label: {
                Label("Import a Song", systemImage: "square.and.arrow.down")
            }
        }
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
                        } : nil
                    ) {
                        appState.selectedAudioFileID = track.audioFileID
                        appState.selectedCategoryID = appState.categoryID(for: track)
                        appState.load(track: track)
                    }
                }
            }
            .listStyle(.inset)
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
        .navigationTitle(trackSearchText.isEmpty ? (appState.selectedCategoryID ?? "Songs") : "Results")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.toggleTrackLibraryColumns()
                } label: {
                    Label(
                        appState.trackLibraryVisibility == .detailOnly ? "Columns" : "Full Screen",
                        systemImage: appState.trackLibraryVisibility == .detailOnly
                            ? "sidebar.left"
                            : "arrow.up.left.and.arrow.down.right"
                    )
                }
                .help(appState.trackLibraryVisibility == .detailOnly
                      ? "Show columns (T)"
                      : "Editor focus: hide columns (T)")
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
    let select: () -> Void

    var body: some View {
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
            }
            .contentShape(Rectangle())
            .padding(.vertical, 1)
        }
        .buttonStyle(.plain)
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
    @State private var isConfirmingVelvetTrackDeletion = false
    @State private var replaceSourceURL: IdentifiableURL?

    var body: some View {
        TimelineEditorView(track: track, appState: appState, isEmbedded: true)
            .id(track.audioFileID)
        .navigationTitle(track.name ?? "Untitled")
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
        .sheet(item: $replaceSourceURL) { item in
            AudioReplaceSheet(appState: appState, track: track, newURL: item.url)
        }
        .confirmationDialog(
            "Delete this Velvet song?",
            isPresented: $isConfirmingVelvetTrackDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                appState.deleteVelvetTrack(track)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The Velvet entry and the copy in VELVET SHOW/Media will be deleted. The original file and ShowBuddy.db will never be touched.")
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
                    Button(role: .destructive) {
                        isConfirmingVelvetTrackDeletion = true
                    } label: {
                        Label("Delete this song from the library", systemImage: "trash")
                    }
                    .controlSize(.small)
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
