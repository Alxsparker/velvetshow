//
//  RemoteSearchView.swift
//  Velvet Remote
//
//  Recherche fullscreen dans la bibliothèque complète.
//  Résultats filtrés localement, sans accent ni casse.
//  Starts-with classé avant contains.
//  Tap → enqueueTrack:<id> → fermeture immédiate.
//

import SwiftUI

struct RemoteSearchView: View {
    @Environment(VelvetRemoteClient.self) private var client
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var focused: Bool

    private let palette = PrompterPalette(
        background: Color(hex: 0x14101A),
        primaryText: Color(hex: 0xE6CC93),
        secondaryText: Color(hex: 0xC9A769),
        accent: Color(hex: 0xC9A769)
    )

    private var filteredTracks: [RemoteTrackInfo] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return client.libraryTracks }
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let matched = client.libraryTracks.filter { $0.title.range(of: q, options: opts) != nil }
        let startsWith = matched.filter { $0.title.range(of: q, options: opts)?.lowerBound == $0.title.startIndex }
        let contains   = matched.filter { $0.title.range(of: q, options: opts)?.lowerBound != $0.title.startIndex }
        return startsWith + contains
    }

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                searchBar
                Divider().overlay(palette.secondaryText.opacity(0.2))
                resultsList
            }
        }
        .onAppear { focused = true }
    }

    // MARK: - Barre de recherche

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.secondaryText)

            TextField("Search…", text: $query)
                .focused($focused)
                .foregroundStyle(palette.primaryText)
                .tint(palette.accent)
                .submitLabel(.search)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.secondaryText)
                }
                .buttonStyle(.plain)
            }

            Button("Cancel") {
                dismiss()
            }
            .foregroundStyle(palette.accent)
            .font(.system(size: 15))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Liste de résultats

    private var resultsList: some View {
        let queuedIDs = Set(client.latestState?.queuedAudioFileIDs ?? [])
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredTracks) { track in
                    resultRow(track: track, isQueued: queuedIDs.contains(track.id))
                        .onTapGesture {
                            client.sendCommand("enqueueTrack:\(track.id)")
                            dismiss()
                        }
                    Divider().overlay(palette.secondaryText.opacity(0.12))
                }
            }
        }
    }

    private func resultRow(track: RemoteTrackInfo, isQueued: Bool) -> some View {
        HStack {
            Text(track.title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
            Spacer()
            if isQueued {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.accent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
