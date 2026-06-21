//
//  AudioFileOperations.swift
//  VELVET SHOW
//
//  Deux sheets for la gestion autonome des fichiers audio :
//
//   • AudioImportSheet  — importe un nouveau song dans MediaFiles/Catégorie/
//   • AudioReplaceSheet — remplace physiquement l'audio d'un song existant
//
//  Règles fondamentales :
//   - Ne jamais toucher ShowBuddy.db
//   - Ne jamais déplacer les fichiers de MediaFiles sans accord utilisateur
//   - Toute écriture dans MediaFiles passe par le security-scoped bookmark
//     déjà géré par AppState.mediaRootURL
//

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

// MARK: ─────────────────────────────────────────────────────────────
// MARK: AudioImportSheet
// MARK: ─────────────────────────────────────────────────────────────

/// Sheet d'import d'un nouveau song.
///
/// Flux :
///   1. Le parent ouvre NSOpenPanel et passe l'URL sélectionnée.
///   2. Cette sheet affiche infos fichier + picker de catégorie.
///   3. Sur confirmation : copie dans MediaFiles/Catégorie/ + création VelvetTrack.
struct AudioImportSheet: View {
    let appState: AppState
    let sourceURL: URL
    @Environment(\.dismiss) private var dismiss

    @State private var categories:           [String] = []
    @State private var selectedCategory:     String   = ""
    @State private var isCreatingNew:        Bool     = false
    @State private var newCategoryName:      String   = ""
    @State private var conflictResolution:   AppState.AudioImportConflict = .keepBoth
    @State private var destinationExists:    Bool     = false
    @State private var sourceInfo:           AudioFileInfo?
    @State private var isImporting:          Bool     = false
    @State private var importError:          String?

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── En-tête ──────────────────────────────────────────────
            header
            Divider()

            // ── Contenu scrollable ───────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sourceInfoSection
                    categorySection
                    if destinationExists { conflictSection }
                    if let err = importError { errorBanner(err) }
                }
                .padding(20)
            }

            Divider()
            // ── Actions ──────────────────────────────────────────────
            footerActions
        }
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: loadData)
        .onChange(of: effectiveCategory) { _, _ in checkConflict() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Label("Import Song", systemImage: "square.and.arrow.down")
                .font(.headline)
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var sourceInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VSSectionHeader(title: "Selected File")
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "music.note")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(sourceURL.lastPathComponent)
                        .font(.headline)
                    if let info = sourceInfo {
                        HStack(spacing: 12) {
                            Text(info.formattedDuration)
                                .font(VSFont.timecode)
                                .foregroundStyle(.secondary)
                            Text(info.format.uppercased())
                                .font(VSFont.badge)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.secondary.opacity(0.2), in: Capsule())
                            if info.sampleRate > 0 {
                                Text("\(Int(info.sampleRate / 1000)) kHz")
                                    .font(VSFont.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Analyzing...")
                            .font(VSFont.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: VSRadius.medium))
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VSSectionHeader(title: "Destination Category")

            if !isCreatingNew {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Category", selection: $selectedCategory) {
                        if categories.isEmpty {
                            Text("No categories found").tag("")
                        } else {
                            ForEach(categories, id: \.self) { cat in
                                Text(cat).tag(cat)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()

                    Button {
                        isCreatingNew = true
                        newCategoryName = ""
                    } label: {
                        Label("Create new category...", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.blue)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("New category name", text: $newCategoryName)
                            .textFieldStyle(.roundedBorder)
                        Button("Cancel") {
                            isCreatingNew = false
                            newCategoryName = ""
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                    Text("A subfolder will be created in MediaFiles.")
                        .font(VSFont.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !effectiveCategory.isEmpty {
                destinationPreview
            }
        }
    }

    private var destinationPreview: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("MediaFiles/\(effectiveCategory)/\(sourceURL.lastPathComponent)")
                .font(VSFont.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var conflictSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(VSColor.warning)
                Text("A file with the same name already exists in this category.")
                    .font(VSFont.label)
            }
            Picker("Conflict", selection: $conflictResolution) {
                Text("Keep both (rename)")
                    .tag(AppState.AudioImportConflict.keepBoth)
                Text("Replace existing file")
                    .tag(AppState.AudioImportConflict.replace)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
        }
        .padding(12)
        .background(VSColor.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: VSRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: VSRadius.medium)
                .stroke(VSColor.warning.opacity(0.4), lineWidth: 1)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(VSColor.danger)
            Text(message)
                .font(VSFont.label)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VSColor.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: VSRadius.medium))
    }

    private var footerActions: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button {
                performImport()
            } label: {
                if isImporting {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Importing...")
                    }
                } else {
                    Text("Import")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(effectiveCategory.isEmpty || isImporting)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Helpers

    private var effectiveCategory: String {
        isCreatingNew
            ? newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
            : selectedCategory
    }

    private func loadData() {
        // Analyse audio
        if let av = try? AVAudioFile(forReading: sourceURL) {
            let dur = Double(av.length) / av.fileFormat.sampleRate
            sourceInfo = AudioFileInfo(
                duration: dur.isFinite && dur > 0 ? dur : 0,
                format: sourceURL.pathExtension.lowercased(),
                sampleRate: av.fileFormat.sampleRate
            )
        }

        // Categories MediaFiles
        let cats = appState.mediaCategories()
        categories = cats
        if let first = cats.first { selectedCategory = first }

        checkConflict()
    }

    private func checkConflict() {
        guard let root = appState.mediaRootURL else { destinationExists = false; return }
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        let cat = effectiveCategory
        guard !cat.isEmpty else { destinationExists = false; return }
        let dest = root
            .appendingPathComponent(cat)
            .appendingPathComponent(sourceURL.lastPathComponent)
        destinationExists = FileManager.default.fileExists(atPath: dest.path)
    }

    private func performImport() {
        let cat = effectiveCategory
        guard !cat.isEmpty else { return }
        isImporting = true
        importError = nil
        Task { @MainActor in
            do {
                try appState.importAudioToMediaFiles(
                    from: sourceURL,
                    category: cat,
                    conflict: conflictResolution
                )
                dismiss()
            } catch {
                importError = error.localizedDescription
            }
            isImporting = false
        }
    }
}

// MARK: ─────────────────────────────────────────────────────────────
// MARK: AudioReplaceSheet
// MARK: ─────────────────────────────────────────────────────────────

/// Sheet de remplacement sécurisé d'un fichier audio.
///
/// Flux :
///   1. Le parent ouvre NSOpenPanel et passe l'URL du nouveau fichier.
///   2. Cette sheet compare ancienne/nouvelle durée et liste les items hors-plage.
///   3. Sur confirmation : backup horodaté + copie physique + rechargement.
struct AudioReplaceSheet: View {
    let appState: AppState
    let track: AudioFile
    let newURL: URL
    @Environment(\.dismiss) private var dismiss

    @State private var oldInfo:        AudioFileInfo?
    @State private var newInfo:        AudioFileInfo?
    @State private var outOfRange:     [String] = []
    @State private var isReplacing:    Bool     = false
    @State private var replaceError:   String?
    @State private var backupURL:      URL?

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    comparisonSection
                    if !outOfRange.isEmpty { warningSection }
                    backupInfoSection
                    if let err = replaceError { errorBanner(err) }
                }
                .padding(20)
            }
            Divider()
            footerActions
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: loadData)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Label("Replace Audio File", systemImage: "arrow.2.circlepath")
                .font(.headline)
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var comparisonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VSSectionHeader(title: "Song: \(track.name ?? "Untitled")")

            HStack(spacing: 16) {
                // Ancien
                audioCard(
                    label: "Current file",
                    filename: (track.path as? NSString)?.lastPathComponent
                        ?? (track.path?.split(separator: "/").last.map(String.init))
                        ?? "—",
                    info: oldInfo,
                    accent: .secondary
                )

                Image(systemName: "arrow.right")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                // Nouveau
                audioCard(
                    label: "New file",
                    filename: newURL.lastPathComponent,
                    info: newInfo,
                    accent: .blue
                )
            }

            // Delta durée
            if let old = oldInfo, let nw = newInfo, old.duration > 0, nw.duration > 0 {
                let delta = nw.duration - old.duration
                let sign  = delta >= 0 ? "+" : ""
                let color: Color = abs(delta) < 1 ? .green : (delta < 0 ? VSColor.warning : .blue)
                HStack(spacing: 4) {
                    Image(systemName: delta == 0 ? "equal" : (delta > 0 ? "arrow.up" : "arrow.down"))
                    Text("Duration difference: \(sign)\(formatDelta(delta))")
                }
                .font(VSFont.label.bold())
                .foregroundStyle(color)
            }
        }
    }

    private func audioCard(
        label: String,
        filename: String,
        info: AudioFileInfo?,
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(VSFont.caption)
                .foregroundStyle(.secondary)
            Text(filename)
                .font(VSFont.label.bold())
                .lineLimit(2)
                .truncationMode(.middle)
            if let info {
                Text(info.formattedDuration)
                    .font(VSFont.timecodeBold)
                    .foregroundStyle(accent)
                HStack(spacing: 6) {
                    Text(info.format.uppercased())
                        .font(VSFont.badge)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(accent.opacity(0.15), in: Capsule())
                    if info.sampleRate > 0 {
                        Text("\(Int(info.sampleRate / 1000)) kHz")
                            .font(VSFont.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Analyzing...")
                    .font(VSFont.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: VSRadius.medium))
    }

    private var warningSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(VSColor.warning)
                Text("Some markers exceed the new duration")
                    .font(VSFont.label.bold())
            }
            Text("These items will not be deleted. You can fix them after replacing.")
                .font(VSFont.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(outOfRange, id: \.self) { item in
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(VSColor.warning)
                        Text(item)
                            .font(VSFont.caption)
                    }
                }
            }
        }
        .padding(12)
        .background(VSColor.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: VSRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: VSRadius.medium)
                .stroke(VSColor.warning.opacity(0.4), lineWidth: 1)
        }
    }

    private var backupInfoSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Automatic backup")
                    .font(VSFont.label.bold())
                Text("The original file will be backed up to ApplicationSupport/VELVET SHOW/AudioBackups/ before replacing.")
                    .font(VSFont.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: VSRadius.medium))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(VSColor.danger)
            Text(message)
                .font(VSFont.label)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VSColor.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: VSRadius.medium))
    }

    private var footerActions: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button {
                performReplace()
            } label: {
                if isReplacing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Replacing...")
                    }
                } else {
                    Text("Replace File")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(VSColor.warning)
            .disabled(isReplacing)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Helpers

    private func loadData() {
        // Ancien fichier
        if let oldURL = appState.resolvedAudioURL(for: track),
           let av = try? AVAudioFile(forReading: oldURL) {
            let dur = Double(av.length) / av.fileFormat.sampleRate
            oldInfo = AudioFileInfo(
                duration: dur.isFinite && dur > 0 ? dur : (track.lengthSecs ?? 0),
                format: oldURL.pathExtension.lowercased(),
                sampleRate: av.fileFormat.sampleRate
            )
        } else if let secs = track.lengthSecs {
            oldInfo = AudioFileInfo(duration: secs, format: "—", sampleRate: 0)
        }

        // Nouveau fichier
        let scopedNew = newURL.startAccessingSecurityScopedResource()
        defer { if scopedNew { newURL.stopAccessingSecurityScopedResource() } }
        if let av = try? AVAudioFile(forReading: newURL) {
            let dur = Double(av.length) / av.fileFormat.sampleRate
            newInfo = AudioFileInfo(
                duration: dur.isFinite && dur > 0 ? dur : 0,
                format: newURL.pathExtension.lowercased(),
                sampleRate: av.fileFormat.sampleRate
            )

            // Items hors-plage
            if dur > 0 {
                outOfRange = appState.outOfRangeVelvetItems(for: track, newDuration: dur)
            }
        }
    }

    private func performReplace() {
        isReplacing = true
        replaceError = nil
        Task { @MainActor in
            do {
                try appState.replaceAudioFile(for: track, with: newURL)
                dismiss()
            } catch {
                replaceError = error.localizedDescription
            }
            isReplacing = false
        }
    }

    private func formatDelta(_ delta: Double) -> String {
        let abs = Swift.abs(delta)
        let m   = Int(abs) / 60
        let s   = Int(abs) % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }
}

// MARK: ─────────────────────────────────────────────────────────────
// MARK: Modèle partagé
// MARK: ─────────────────────────────────────────────────────────────

/// Informations extraites d'un fichier audio for affichage.
struct AudioFileInfo {
    let duration:   Double
    let format:     String
    let sampleRate: Double

    var formattedDuration: String {
        guard duration > 0 else { return "—" }
        let m = Int(duration) / 60
        let s = Int(duration) % 60
        let ms = Int((duration - Double(Int(duration))) * 10)
        return ms > 0
            ? String(format: "%d:%02d.%d", m, s, ms)
            : String(format: "%d:%02d", m, s)
    }
}

// MARK: ─────────────────────────────────────────────────────────────
// MARK: NSOpenPanel helpers (à appeler depuis ContentView)
// MARK: ─────────────────────────────────────────────────────────────

/// Ouvre un NSOpenPanel audio et retourne l'URL choisie.
/// Retourne nil si l'utilisateur annule ou choisit un format non supporté.
func pickAudioFile(title: String, prompt: String) -> URL? {
    let panel = NSOpenPanel()
    panel.title = title
    panel.prompt = prompt
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [
        UTType(filenameExtension: "mp3")  ?? .audio,
        UTType(filenameExtension: "wav")  ?? .audio,
        UTType(filenameExtension: "aiff") ?? .audio,
        UTType(filenameExtension: "aif")  ?? .audio,
        UTType(filenameExtension: "m4a")  ?? .audio,
    ]
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    let allowed = ["mp3", "wav", "aiff", "aif", "m4a"]
    guard allowed.contains(url.pathExtension.lowercased()) else { return nil }
    return url
}
