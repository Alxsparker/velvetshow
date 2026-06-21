//
//  MediaLibraryRemapView.swift
//  VELVET SHOW
//
//  Permet de changer la racine des fichiers audio de tous les velvetTracks.
//  Cas d'usage principal : passer de SBS_TEST/SbsBackup/MediaFiles vers
//  /Library/Application Support/db audioware/Show Buddy/Media Files (ou tout
//  autre dossier MediaFiles).
//
//  Règles :
//  - aucune copie, aucun déplacement de fichier audio ;
//  - sauvegarde VelvetShowState.json.bak avant réécriture ;
//  - seuls les tracks dont le fichier existe dans le nouveau dossier sont
//    rebasés ; les more conservent leur ancienne URL.
//

import SwiftUI
import AppKit

// MARK: - Feuille principale

struct MediaLibraryRemapView: View {
    @Environment(AppState.self) private var appState
    var onDismiss: () -> Void

    @State private var phase: Phase = .idle
    @State private var isPickingFolder = false

    enum Phase {
        case idle
        case previewing(AppState.MediaRemapPreview)
        case applying
        case done(AppState.MediaRemapResult)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            Group {
                switch phase {
                case .idle:
                    idleBody
                case .previewing(let preview):
                    previewBody(preview)
                case .applying:
                    applyingBody
                case .done(let result):
                    doneBody(result)
                }
            }
            .padding(20)
        }
        .frame(width: 520)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Image(systemName: "folder.badge.gearshape")
                .font(.title2)
                .foregroundStyle(VSColor.interactive)
            VStack(alignment: .leading, spacing: 2) {
                Text("Change Audio Library")
                    .font(.headline)
                Text("Rebase all Velvet song paths to a new Media Files folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { onDismiss() } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Phase idle

    private var idleBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Current Library
            infoRow(
                label: "Current Library",
                value: currentRootDisplay,
                icon: "folder.fill",
                color: .secondary
            )

            Text("Select the new Media Files folder. Velvet Show will verify that every song exists there before making the change.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Choose a Folder...") {
                    pickFolder()
                }
                .buttonStyle(.borderedProminent)
                .tint(VSColor.interactive)
            }
        }
    }

    // MARK: Phase preview

    @ViewBuilder
    private func previewBody(_ preview: AppState.MediaRemapPreview) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // New Folder
            infoRow(
                label: "New Folder",
                value: preview.newRoot.path,
                icon: "folder.fill",
                color: .primary
            )

            // Verification Result
            VStack(alignment: .leading, spacing: 8) {
                Label("Verification Result", systemImage: "checkmark.seal")
                    .font(.subheadline.bold())

                HStack(spacing: 20) {
                    statBadge(
                        count: preview.remappableCount,
                        label: "ready to rebase",
                        icon: "checkmark.circle.fill",
                        color: .green
                    )
                    statBadge(
                        count: preview.notFoundCount,
                        label: "conservent l'ancien chemin",
                        icon: "exclamationmark.triangle.fill",
                        color: preview.notFoundCount > 0 ? .orange : .secondary
                    )
                }
                .padding(.vertical, 4)

                if !preview.notFound.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Files not found (path kept):")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        ForEach(preview.notFound.prefix(5), id: \.id) { track in
                            Label(track.title, systemImage: "music.note")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        if preview.notFound.count > 5 {
                            Text("... +\(preview.notFound.count - 5) more")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(8)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            Divider()

            Text("A VelvetShowState.json.bak backup will be created before rewriting.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            HStack {
                Button("Choose Another Folder") {
                    pickFolder()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Rebase \(preview.remappableCount) songs") {
                    apply(preview)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(preview.remappableCount == 0)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: Phase applying

    private var applyingBody: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Rewriting paths...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: Phase done

    @ViewBuilder
    private func doneBody(_ result: AppState.MediaRemapResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Rebase Complete", systemImage: "checkmark.circle.fill")
                .font(.title3.bold())
                .foregroundStyle(.green)

            infoRow(
                label: "New Root",
                value: result.newRootPath,
                icon: "folder.fill",
                color: .primary
            )

            HStack(spacing: 20) {
                statBadge(
                    count: result.remapped,
                    label: "songs rebased",
                    icon: "checkmark.circle.fill",
                    color: .green
                )
                statBadge(
                    count: result.kept,
                    label: "paths kept",
                    icon: "exclamationmark.triangle.fill",
                    color: result.kept > 0 ? .orange : .secondary
                )
            }

            if !result.notFoundTitles.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Paths not found (unchanged):")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    ForEach(result.notFoundTitles.prefix(5), id: \.self) { title in
                        Label(title, systemImage: "music.note")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if result.notFoundTitles.count > 5 {
                        Text("... +\(result.notFoundTitles.count - 5) more")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(8)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }

            Text("VelvetShowState.json.bak was created before rewriting.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            HStack {
                Spacer()
                Button("Close") { onDismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(VSColor.interactive)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: Sub-views

    private func infoRow(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Label(value, systemImage: icon)
                .font(.caption.monospaced())
                .foregroundStyle(color)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }

    private func statBadge(count: Int, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Label("\(count)", systemImage: icon)
                .font(.title2.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(minWidth: 110)
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Helpers

    private var currentRootDisplay: String {
        guard let first = appState.velvetTracks.first else { return "—" }
        // Affiche le préfixe commun (remonte jusqu'au répertoire parent du premier sous-dossier)
        let path = first.fileURL.path
        let components = path.components(separatedBy: "/").filter { !$0.isEmpty }
        // On cherche le composant "MediaFiles" ou "Media Files" for couper là
        if let idx = components.firstIndex(where: { $0.contains("Media") }) {
            return "/" + components.prefix(idx + 1).joined(separator: "/")
        }
        // Fallback : parent du parent du fichier
        return first.fileURL.deletingLastPathComponent().deletingLastPathComponent().path
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles            = false
        panel.canChooseDirectories      = true
        panel.allowsMultipleSelection   = false
        panel.message  = "Select the Media Files folder to use"
        panel.prompt   = "Choose"
        panel.directoryURL = URL(fileURLWithPath:
            "/Library/Application Support/db audioware/Show Buddy/Media Files")
        if panel.runModal() == .OK, let url = panel.url {
            let preview = appState.previewMediaRemap(to: url)
            phase = .previewing(preview)
        }
    }

    private func apply(_ preview: AppState.MediaRemapPreview) {
        phase = .applying
        Task { @MainActor in
            let result = appState.applyMediaRemap(preview)
            phase = .done(result)
        }
    }
}
