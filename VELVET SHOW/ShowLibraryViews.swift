//
//  ShowLibraryViews.swift
//  VELVET SHOW
//

import SwiftUI

// MARK: ───────────────────────────────────────────────────────────
// MARK: Show Library
// MARK: ───────────────────────────────────────────────────────────

struct ShowLibraryRoot: View {
    @Bindable var appState: AppState

    private var isFocusMode: Bool {
        appState.showsSidebarVisibility == .detailOnly
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $appState.showsSidebarVisibility) {
            SetsSidebar(appState: appState)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        } detail: {
            ShowDetailColumn(
                appState: appState,
                isFocusMode: isFocusMode,
                toggleFocusMode: toggleFocusMode
            )
        }
        .toolbar(removing: .sidebarToggle)
    }

    /// Le triangle "focus concert" collapse simultanément les deux
    /// colonnes (Shows + Quick Library). Les raccourcis S et T, eux,
    /// les togglent indépendamment.
    private func toggleFocusMode() {
        withAnimation(.easeInOut(duration: 0.22)) {
            if isFocusMode {
                appState.showsSidebarVisibility = .all
                appState.isQuickLibraryVisible = appState.quickLibraryWasVisibleBeforeFocus
            } else {
                appState.quickLibraryWasVisibleBeforeFocus = appState.isQuickLibraryVisible
                appState.showsSidebarVisibility = .detailOnly
                appState.isQuickLibraryVisible = false
            }
        }
    }
}

struct SetsSidebar: View {
    @Bindable var appState: AppState
    @State private var isCreatingVelvetShow = false
    @State private var editingSet: ShowSet?
    @State private var deletingSet: ShowSet?
    @State private var isConfirmingResetAll = false

    private var showBuddySets: [ShowSet] { appState.showBuddySets }

    /// Shows Velvet dans l'ordre d'affichage manuel persisté.
    private var velvetSets: [ShowSet] {
        appState.orderedVelvetShows.map { show in
            ShowSet(setID: show.id, name: show.name, note: show.note, folder: "VELVET SHOWS", setType: "Velvet")
        }
    }

    private var isVelvetSet: Set<ShowSet.ID> {
        Set(velvetSets.map(\.id))
    }

    @ViewBuilder
    private func showRow(_ set: ShowSet) -> some View {
        let isVelvet = isVelvetSet.contains(set.id)
        // Jaune = ce show contient le song en cours.
        // Même couleur que la tuile du song en cours : le langage visuel
        // est identique, l'utilisateur n'a rien at apprendre.
        let isNowPlaying = appState.currentlyLoadedSetID == set.setID
        let isSelected = appState.selectedSetID == set.id
        HStack(spacing: 8) {
            Circle()
                .fill(isVelvet ? appState.color(for: set) : Color.clear)
                .frame(width: isNowPlaying ? 9 : 7, height: isNowPlaying ? 9 : 7)
                .opacity(isNowPlaying || isSelected ? 1 : 0.55)
            Text(set.name ?? "Show")
                .font(.callout.weight(isNowPlaying || isSelected ? .semibold : .regular))
                .foregroundStyle(isNowPlaying ? VelvetPalette.nowPlayingYellow : (isSelected ? Color.primary : Color.secondary))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .opacity(isNowPlaying || isSelected ? 1 : 0.78)
        .contextMenu {
            if isVelvet {
                Button("Rename / Options") { editingSet = set }
            }
            if appState.customOrderBySetID[set.setID] != nil {
                if isVelvet {
                    Divider()
                }
                Button {
                    appState.resetCustomOrder(for: set)
                } label: {
                    Label("Reset Show Order", systemImage: "arrow.uturn.backward")
                }
            }
            if isVelvet || appState.customOrderBySetID[set.setID] != nil {
                Divider()
            }
            Button {
                appState.duplicateAsVelvetShow(set)
            } label: {
                Label("Duplicate Show", systemImage: "doc.on.doc")
            }
            if isVelvet {
                Button("Delete", role: .destructive) { deletingSet = set }
            }
        }
    }

    var body: some View {
        List(selection: $appState.selectedSetID) {
            // Shows ShowBuddy — ordre alphabétique, pas de drag-and-drop.
            if !showBuddySets.isEmpty {
                Section("Imported") {
                    ForEach(showBuddySets) { set in
                        showRow(set)
                    }
                }
            }
            // Shows Velvet — ordre manuel, drag-and-drop activé.
            Section(showBuddySets.isEmpty ? "" : "My Shows") {
                ForEach(velvetSets) { set in
                    showRow(set)
                        .anchorPreference(key: TourAnchorsKey.self, value: .bounds) { anchor in
                            DemoIDRange.shows.contains(set.id) ? [TourAnchor.demoShowRow: anchor] : [:]
                        }
                }
                .onMove { from, to in
                    appState.moveVelvetShows(fromOffsets: from, toOffset: to)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(.ultraThinMaterial)
        .navigationTitle("Shows")
        .toolbar {
            // Réinitialiser tous les concerts (bouton destructif discret)
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
        .sheet(isPresented: $isCreatingVelvetShow) {
            VelvetShowEditorSheet(mode: .create, appState: appState)
        }
        .sheet(item: $editingSet) { set in
            VelvetShowEditorSheet(mode: .edit(set), appState: appState)
        }
        .confirmationDialog(
            "Delete this show?",
            isPresented: Binding(
                get: { deletingSet != nil },
                set: { if !$0 { deletingSet = nil } }
            ),
            titleVisibility: .visible
        ) {
            // Lecture directe du @State — évite le bug macOS de presenting:
            // où la valeur du closure peut être obsolète ou mal initialisée.
            if let set = deletingSet {
                Button("Delete", role: .destructive) {
                    appState.deleteVelvetShow(set)
                    deletingSet = nil
                }
            }
            Button("Cancel", role: .cancel) { deletingSet = nil }
        } message: {
            if let set = deletingSet {
                Text("\"\(set.name ?? "Show")\" will be removed from Velvet Show only. Songs and audio files will not be deleted.")
            }
        }
        .overlay {
            if appState.sets.isEmpty {
                ContentUnavailableView {
                    Label("No Shows", systemImage: "music.note.list")
                } description: {
                    Text("Create your first show to organize your setlist.")
                } actions: {
                    Button("New Show") { isCreatingVelvetShow = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

enum VelvetShowEditorMode {
    case create
    case edit(ShowSet)
}

struct VelvetShowEditorSheet: View {
    let mode: VelvetShowEditorMode
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var note: String
    @State private var color: Color

    init(mode: VelvetShowEditorMode, appState: AppState) {
        self.mode = mode
        self.appState = appState
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _note = State(initialValue: "")
            _color = State(initialValue: Color(hex: 0x00C8FF))
        case .edit(let set):
            let show = appState.velvetShow(for: set)
            _name = State(initialValue: show?.name ?? set.name ?? "My Show")
            _note = State(initialValue: show?.note ?? set.note ?? "")
            _color = State(initialValue: Color(hex: show?.colorHex ?? 0x00C8FF))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: "sparkles")
                .font(.title3.bold())
            TextField("Show name", text: $name)
                .textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 5) {
                Text("Notes")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                TextEditor(text: $note)
                    .frame(minHeight: 90)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.quaternary, lineWidth: 1)
                    }
            }
            ColorPicker("Color", selection: $color, supportsOpacity: false)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(primaryButtonTitle) {
                    save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 420)
    }

    private var title: String {
        switch mode {
        case .create: return "New Show"
        case .edit: return "Edit Show"
        }
    }

    private var primaryButtonTitle: String {
        switch mode {
        case .create: return "Create"
        case .edit: return "Save"
        }
    }

    private func save() {
        switch mode {
        case .create:
            appState.createVelvetShow(name: name, note: note, color: color)
        case .edit(let set):
            appState.updateVelvetShow(set, name: name, note: note, color: color)
        }
    }
}

struct ShowDetailColumn: View {
    let appState: AppState
    var isFocusMode: Bool = false
    var toggleFocusMode: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let id = appState.selectedSetID,
               let set = appState.sets.first(where: { $0.id == id }) {
                HStack(spacing: 0) {
                    if appState.isQuickLibraryVisible {
                        QuickLibraryColumn(appState: appState, set: set)
                            .frame(minWidth: 240, idealWidth: 300, maxWidth: 360)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        Divider()
                    }
                    SetSongsView(
                        appState: appState,
                        set: set,
                        songs: appState.songs(in: set),
                        isFocusMode: isFocusMode,
                        toggleFocusMode: toggleFocusMode
                    )
                        .frame(minWidth: 460)
                        // Garde-fou : si le contenu (en-tête rigide, grille)
                        // dépasse la largeur allouée, il est rogné au lieu de
                        // se dessiner PAR-DESSUS la Quick Library.
                        .clipped()
                    if appState.isPanicPrompterVisible {
                        Divider()
                        EmergencyPrompterPanel(appState: appState)
                            .frame(minWidth: 390, idealWidth: 470, maxWidth: 560)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: appState.isPanicPrompterVisible)
                .animation(.easeInOut(duration: 0.18), value: appState.isQuickLibraryVisible)
            } else {
                VelvetWelcomeView(appState: appState)
            }
        }
    }

}

/// Écran d'accueil affiché quand aucun concert n'est sélectionné.
/// — Premier lancement (aucun song) : guide en 3 étapes + bouton import.
/// — Bibliothèque peuplée mais rien de sélectionné : invitation simple.
struct VelvetWelcomeView: View {
    let appState: AppState

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    VelvetPalette.velvetBlack.opacity(0.25),
                    Color.clear,
                    VelvetPalette.burgundyDeep.opacity(0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if appState.velvetTracks.isEmpty {
                firstLaunchContent
            } else {
                selectConcertContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Premier lancement

    private var firstLaunchContent: some View {
        VStack(spacing: 28) {
            Spacer()

            Rectangle()
                .fill(VelvetPalette.gold)
                .frame(width: 60, height: 1)

            Text("VELVET SHOW")
                .font(.system(size: 48, weight: .thin, design: .serif))
                .tracking(8)
                .foregroundStyle(VelvetPalette.goldLight)

            Text("The live musician's stage companion")
                .font(.system(size: 13, weight: .regular))
                .tracking(1)
                .foregroundStyle(VelvetPalette.gold.opacity(0.75))

            Rectangle()
                .fill(VelvetPalette.gold)
                .frame(width: 60, height: 1)

            VStack(alignment: .leading, spacing: 14) {
                onboardingStep(number: "1", title: "Import your songs",
                    detail: "Add your audio files (MP3, WAV, AIFF...) to your library.")
                onboardingStep(number: "2", title: "Create a show",
                    detail: "In the sidebar, click + to organize your setlist.")
                onboardingStep(number: "3", title: "Start playback",
                    detail: "Select a song and press Space or ▶.")
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .frame(maxWidth: 400)

            Button {
                presentVelvetTrackImportPanel(appState: appState)
            } label: {
                Label("Import My Songs", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .padding(.horizontal, 48)
    }

    @ViewBuilder
    private func onboardingStep(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.system(size: 18, weight: .thin, design: .serif))
                .foregroundStyle(VelvetPalette.gold)
                .frame(width: 22, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.bold())
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Bibliothèque peuplée, aucun concert sélectionné

    private var selectConcertContent: some View {
        VStack(spacing: 16) {
            Spacer()

            Rectangle()
                .fill(VelvetPalette.gold)
                .frame(width: 60, height: 1)

            Text("VELVET SHOW")
                .font(.system(size: 48, weight: .thin, design: .serif))
                .tracking(8)
                .foregroundStyle(VelvetPalette.goldLight)

            Rectangle()
                .fill(VelvetPalette.gold)
                .frame(width: 60, height: 1)

            Text("Select a show from the sidebar\nto prepare or start your set.")
                .font(.system(size: 15, weight: .light))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.top, 10)

            Spacer()
        }
        .padding(.horizontal, 40)
    }
}

// MARK: ───────────────────────────────────────────────────────────
// MARK: Styles & Colors (gestionnaire centralisé)
// MARK: ───────────────────────────────────────────────────────────

/// Panneau "Styles & Colors" : source unique for personnaliser les
/// couleurs de chaque genre. Toutes les vues qui affichent un genre lisent
/// `appState.color(for:)` — modifier ici met at jour toute l'app en direct.
struct StylesColorsPanel: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingReset = false

    /// Tous les genres sauf `.all` (qui est un filtre, pas un style).
    private var genres: [ConcertGenre] {
        ConcertGenre.allCases.filter { $0 != .all }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(genres) { genre in
                        styleRow(genre)
                    }
                }
                .padding(.horizontal, 4)
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(minWidth: 460, minHeight: 480)
        .confirmationDialog(
            "Reset all colors?",
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button("Reset All", role: .destructive) {
                appState.resetAllColors()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("All custom colors will be removed and Velvet Show defaults will be restored.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("Styles & Colors", systemImage: "paintbrush.pointed.fill")
                .font(.title3.bold())
            Spacer()
            Text("Single source for all views")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func styleRow(_ genre: ConcertGenre) -> some View {
        let count = appState.trackCount(for: genre)
        let isOverride = appState.genreColors[genre] != nil

        HStack(spacing: 12) {
            // Pastille couleur + nom du style.
            RoundedRectangle(cornerRadius: 6)
                .fill(appState.color(for: genre))
                .frame(width: 36, height: 24)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.primary.opacity(0.18), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(genre.label)
                    .font(.callout.bold())
                Text("\(count) song\(count > 1 ? "s" : "")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isOverride {
                Text("Custom")
                    .font(.caption2.bold())
                    .foregroundStyle(VSColor.warning)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(VSColor.warning.opacity(0.12), in: Capsule())
            }

            // Palette fixe : seules les 7 couleurs scène sont proposées.
            TilePalettePicker(
                selection: Binding(
                    get: { appState.color(for: genre) },
                    set: { newColor in appState.setColor(newColor, for: genre) }
                )
            )

            Button {
                appState.resetColor(for: genre)
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .disabled(!isOverride)
            .help("Restore default color for this style")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack {
            Button(role: .destructive) {
                isConfirmingReset = true
            } label: {
                Label("Reset All", systemImage: "arrow.counterclockwise")
            }
            .disabled(appState.genreColors.isEmpty)

            Spacer()

            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
    }
}

// MARK: ───────────────────────────────────────────────────────────
// MARK: Track Library rapide (colonne gauche du Show)
// MARK: ───────────────────────────────────────────────────────────

/// Bibliothèque rapide affichée at gauche du Show pendant la performance.
/// Permet de trouver et placer un song non prévu sans quitter la vue
/// du show ni interrompre la lecture en cours. Toutes les actions sont
/// inline (3 boutons visibles at droite du titre) for minimiser les clics.
struct QuickLibraryColumn: View {
    let appState: AppState
    let set: ShowSet
    @State private var searchText: String = ""
    @State private var expandedCategories: Set<String> = []

    private var filteredCategories: [TrackCategory] {
        let needle = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !needle.isEmpty else { return appState.categories }

        return appState.categories.compactMap { category in
            let matched = category.tracks.filter { track in
                (track.name ?? "").lowercased().contains(needle)
            }
            guard !matched.isEmpty else { return nil }
            return TrackCategory(name: category.name, tracks: matched)
        }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredCategories) { category in
                        categorySection(category)
                    }
                    if filteredCategories.isEmpty {
                        Text("No songs found.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 16)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(.regularMaterial)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "books.vertical")
                .font(.caption.bold())
            Text("Quick Songs")
                .font(.caption.bold())
            Spacer()
            Text("\(appState.audioFiles.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button {
                appState.isQuickLibraryVisible = false
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Hide Quick Songs (⌘B)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: Search

    private var searchBar: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Search songs...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.caption)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    // MARK: Categories repliables

    @ViewBuilder
    private func categorySection(_ category: TrackCategory) -> some View {
        let isOpen = isSearching || expandedCategories.contains(category.id)
        VStack(alignment: .leading, spacing: 1) {
            Button {
                if expandedCategories.contains(category.id) {
                    expandedCategories.remove(category.id)
                } else {
                    expandedCategories.insert(category.id)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.caption2.bold())
                        .frame(width: 10)
                    Text(category.name)
                        .font(.system(size: 15))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(category.tracks.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .disabled(isSearching)

            if isOpen {
                ForEach(category.tracks) { track in
                    QuickLibraryRow(appState: appState, set: set, track: track)
                }
            }
        }
    }
}

/// Une ligne song de la Track Library rapide. Affiche le titre suivi
/// de trois actions accessibles d'un seul clic : insérer en tête de file,
/// ajouter en fin de file, ajouter comme étiquette "Added live" dans le
/// show. Drag source : la ligne expose `track.audioFileID` en plain-text,
/// compatible avec `handleTrackDrop` côté setlist.
struct QuickLibraryRow: View {
    let appState: AppState
    let set: ShowSet
    let track: AudioFile

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(appState.color(for: track))
                .frame(width: 3, height: 16)

            Text(track.name ?? "Untitled")
                .font(.system(size: 15))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onDrag {
            NSItemProvider(object: String(track.audioFileID) as NSString)
        } preview: {
            quickSongDragPreview
        }
    }

    private var quickSongDragPreview: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(appState.color(for: track))
                .frame(width: 4, height: 20)
            Text(track.name ?? "Untitled")
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .frame(width: 190, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(appState.color(for: track).opacity(0.72), lineWidth: 1)
        }
        .scaleEffect(1.02)
        .opacity(0.84)
        .shadow(color: .black.opacity(0.32), radius: 14, x: 0, y: 8)
    }
}

struct EmergencyPrompterPanel: View {
    let appState: AppState

    var body: some View {
        PrompterPreviewView(
            title: appState.currentlyLoadedTrack?.name ?? "No song loaded",
            currentMemoTitle: appState.currentMemo()?.shortName,
            currentMemoText: memoDisplayText(appState.currentMemo()),
            nextMemoText: memoDisplayText(appState.nextMemo()),
            remainingTime: formatTime(appState.audioEngine.effectiveRemaining),
            playbackState: RemotePlaybackState(appState.audioEngine.state),
            audioURL: appState.currentlyLoadedTrack.flatMap { appState.resolvedAudioURL(for: $0) },
            duration: appState.audioEngine.effectiveDuration,
            currentPosition: appState.audioEngine.effectivePosition,
            timelineMemos: timelineMemos,
            palette: appState.prompterTheme.palette
        )
        .overlay(alignment: .topLeading) {
            Text("BACKUP PROMPTER")
                .font(.caption.bold())
                .foregroundStyle(appState.prompterTheme.palette.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(appState.prompterTheme.palette.background.opacity(0.82), in: Capsule())
                .padding(12)
        }
    }

    private var timelineMemos: [WaveformTimelineMemo] {
        guard let track = appState.currentlyLoadedTrack else { return [] }
        return appState.prompterMemos(for: track).map { memo in
            let title = memo.shortName.isEmpty ? String(memo.memo.prefix(28)) : memo.shortName
            return WaveformTimelineMemo(
                id: memo.id.uuidString,
                title: title,
                startTime: memo.memoTime,
                duration: max(1, memo.memoLength),
                hasMidi: memo.hasMidi
            )
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private func memoDisplayText(_ memo: EditableMemo?) -> String? {
        guard let memo else { return nil }
        let text = memo.memo.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
        let title = memo.shortName.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }
}

/// Bandeau "Diagnostic import" — replié par défaut for ne pas voler de
/// place verticale at la grille des songs restants. Cliquer sur la ligne
/// déplie les compteurs détaillés (Songs, Shows, Sets, ...).
struct DiagnosticBar: View {
    let stats: LibraryStats
    let fileName: String
    @State private var isExpanded: Bool = false

    private var summary: String {
        "\(fileName) — \(stats.audioFiles) songs · \(stats.sets) sets · \(stats.showMemos) memos"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "internaldrive")
                        .font(.caption.bold())
                    Text(summary)
                        .font(.caption.bold())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text("Diagnostic")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                HStack(spacing: 6) {
                    statTile("Songs",     stats.audioFiles,   "music.note")
                    statTile("Shows",     stats.lightShows,   "wand.and.stars")
                    statTile("Sets",      stats.sets,         "music.note.list")
                    statTile("Items",     stats.setElements,  "list.bullet")
                    statTile("Events",    stats.midiEvents,   "light.cylindrical.ceiling.fill")
                    statTile("Msgs",      stats.midiMessages, "envelope")
                    statTile("Memos",     stats.showMemos,    "note.text")
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(.thinMaterial)
    }

    private func statTile(_ title: String, _ count: Int, _ symbol: String) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 3) {
                Image(systemName: symbol).font(.caption2)
                Text("\(count)").font(.callout.bold().monospacedDigit())
            }
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 56)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Bandeau concert : compact quand la Queue est vide, prioritaire dès
/// qu'elle contient des songs at lancer at la volée.
