import SwiftUI
import AVFoundation

// MARK: - TrackDeleteSheet

/// Fiche de confirmation avant suppression d'un song de la bibliothèque Velvet.
/// Présente les shows impactés et propose deux niveaux :
///   - Delete de ce show uniquement (niveau 1)
///   - Move to Velvet Trash (tous les shows + bibliothèque) (niveau 2)
struct TrackDeleteSheet: View {
    @Environment(AppState.self) private var appState
    let track: VelvetTrack
    /// Show source (contexte Show Library). Nil si vient de Track Library.
    var sourceShow: VelvetShow? = nil
    var onDismiss: () -> Void

    @State private var impactedShows: [VelvetShow] = []
    @State private var isConfirmingTrash = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "trash.circle.fill")
                    .font(.title)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Delete \"\(trackTitle)\"")
                        .font(.headline)
                    Text("Choose the deletion level")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Niveau 1 : retirer du show courant seulement
            if let sourceShow {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Retirer de ce show", systemImage: "rectangle.badge.minus")
                        .font(.subheadline.bold())
                    Text("Retire \"\(trackTitle)\" du show \"\(sourceShow.name)\" only. The song stays in the library and the other shows.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        appState.removeTrack(track, from: sourceShow)
                        onDismiss()
                    } label: {
                        Label("Retirer de \"\(sourceShow.name)\"", systemImage: "minus.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
            }

            // Niveau 2 : Velvet Trash
            VStack(alignment: .leading, spacing: 6) {
                Label("Move to Velvet Trash", systemImage: "trash")
                    .font(.subheadline.bold())

                if impactedShows.isEmpty {
                    Text("This song does not appear in any Velvet show. It will be removed from the library only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("This song will be removed from the library and from \(impactedShows.count) show\(impactedShows.count > 1 ? "s" : "") :")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(impactedShows) { show in
                        Label(show.name, systemImage: "music.note.list")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Text("Memos, cue points, trim, and volume are saved; restoration is possible from the Trash. The audio file is not touched.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                Button {
                    isConfirmingTrash = true
                } label: {
                    Label("Move to Velvet Trash", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            impactedShows = appState.showsContaining(track)
        }
        .confirmationDialog(
            "Mettre \"\(trackTitle)\" to Velvet Trash?",
            isPresented: $isConfirmingTrash,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                appState.trashVelvetTrack(track)
                onDismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The song and all its Velvet data will be moved to Trash. You can restore it at any time.")
        }
    }

    private var trackTitle: String {
        track.title.isEmpty ? "Unnamed Song" : track.title
    }
}

// MARK: - VelvetTrashSheet

/// Window Velvet Trash : liste les songs supprimés avec date,
/// permet de restaurer ou de supprimer définitivement.
struct VelvetTrashSheet: View {
    @Environment(AppState.self) private var appState
    var onDismiss: () -> Void

    @State private var selectedTrashedID: TrashedVelvetTrack.ID? = nil
    @State private var isConfirmingEmptyTrash = false
    @State private var isConfirmingPermanentDelete = false
    @State private var pendingPermanentDelete: TrashedVelvetTrack? = nil

    private var trashed: [TrashedVelvetTrack] { appState.trashedTracks }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
                Text("Velvet Trash")
                    .font(.headline)
                Spacer()
                if !trashed.isEmpty {
                    Button {
                        isConfirmingEmptyTrash = true
                    } label: {
                        Label("Empty Trash", systemImage: "trash.slash")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if trashed.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.system(size: 48))
                        .foregroundStyle(.quaternary)
                    Text("Trash is Empty")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Songs deleted from the library appear here with all their Velvet data. You can restore them at any time before permanent deletion.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
                Spacer()
            } else {
                List(trashed, selection: $selectedTrashedID) { item in
                    TrashedTrackRow(item: item) {
                        appState.restoreFromTrash(item)
                    } onPermanentDelete: {
                        pendingPermanentDelete = item
                        isConfirmingPermanentDelete = true
                    }
                    .tag(item.id)
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 560, height: 480)
        .confirmationDialog(
            "Empty Velvet Trash?",
            isPresented: $isConfirmingEmptyTrash,
            titleVisibility: .visible
        ) {
            Button("Empty Trash (\(trashed.count) song\(trashed.count > 1 ? "x" : ""))", role: .destructive) {
                appState.emptyVelvetTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. Audio files will not be deleted.")
        }
        .confirmationDialog(
            "Delete Permanently?",
            isPresented: $isConfirmingPermanentDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                if let item = pendingPermanentDelete {
                    appState.permanentlyDeleteTrashedTrack(item)
                    pendingPermanentDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let item = pendingPermanentDelete {
                let title = item.track.title.isEmpty ? "ce song" : item.track.title
                Text("The Velvet data for \"\(title)\" will be permanently erased. The audio file remains intact.")
            }
        }
    }
}

// MARK: - TrashedTrackRow

private struct TrashedTrackRow: View {
    let item: TrashedVelvetTrack
    var onRestore: () -> Void
    var onPermanentDelete: () -> Void

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note")
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.track.title.isEmpty ? "Sans nom" : item.track.title)
                    .font(.body)
                HStack(spacing: 8) {
                    if !item.track.genre.isEmpty {
                        Text(item.track.genre)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Deleted \(Self.relativeFormatter.localizedString(for: item.trashedAt, relativeTo: .now))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                // Indicateurs des données sauvegardées
                HStack(spacing: 4) {
                    if !item.memos.isEmpty {
                        badge("\(item.memos.count) memo\(item.memos.count > 1 ? "s" : "")", icon: "text.bubble")
                    }
                    if !item.cuePoints.isEmpty {
                        badge("\(item.cuePoints.count) cue", icon: "flag")
                    }
                    if item.trim != nil {
                        badge("trim", icon: "scissors")
                    }
                    if item.volume != nil {
                        badge("volume", icon: "speaker.wave.2")
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    onRestore()
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .help("Restore to library")

                Button {
                    onPermanentDelete()
                } label: {
                    Label("Delete", systemImage: "xmark.bin")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .help("Delete Permanently")
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func badge(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .foregroundStyle(.secondary)
    }
}
