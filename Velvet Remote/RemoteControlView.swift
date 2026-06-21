//
//  RemoteControlView.swift
//  Velvet Remote — iPhone
//
//  Télécommande de spectacle compacte :
//  - haut fixe  : morceau courant, timer, next, +2
//  - centre      : setlist scrollable — toucher = prochain morceau (pas de lancement)
//  - bas fixe    : Play/Pause + Next
//

import SwiftUI

struct RemoteControlView: View {
    @Environment(VelvetRemoteClient.self) private var client

    private let palette = PrompterPalette(
        background: Color(hex: 0x14101A),
        primaryText: Color(hex: 0xE6CC93),
        secondaryText: Color(hex: 0xC9A769),
        accent: Color(hex: 0xC9A769)
    )

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()

            if let state = client.latestState {
                VStack(spacing: 0) {
                    headerPanel(state: state)
                    Divider().overlay(palette.secondaryText.opacity(0.2))
                    setlistPanel(state: state)
                    Divider().overlay(palette.secondaryText.opacity(0.2))
                    commandBar(state: state)
                }
            } else {
                waitingView
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Header fixe

    private func headerPanel(state: RemoteStateUpdate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Ligne 1 : badge réseau + titre courant + timer
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                RemoteConnectionBadge(transport: client.transport)

                Text(state.songTitle ?? "—")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)

                Spacer()

                Text(formatRemaining(position: state.positionSeconds, duration: state.durationSeconds))
                    .font(.system(size: 28, weight: .black).monospacedDigit())
                    .foregroundStyle(palette.primaryText)
            }

            // Ligne 2 : morceau suivant
            if let next = state.nextSongTitle, !next.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.accent)
                    Text(next)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .lineLimit(1)
                }
            }

            // Ligne 3 : morceau +2
            if let after = state.afterNextSongTitle, !after.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(palette.secondaryText.opacity(0.55))
                    Text(after)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(palette.secondaryText.opacity(0.55))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.30))
    }

    // MARK: - Setlist scrollable

    private func setlistPanel(state: RemoteStateUpdate) -> some View {
        Group {
            if state.upcomingSetlist.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 28))
                        .foregroundStyle(palette.secondaryText.opacity(0.3))
                    Text("No upcoming songs")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.secondaryText.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        sectionHeader("UPCOMING SONGS")
                        ForEach(Array(state.upcomingSetlist.enumerated()), id: \.element.id) { index, song in
                            setlistRow(song: song, index: index, nextTitle: state.nextSongTitle)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(palette.secondaryText.opacity(0.5))
            .tracking(1.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private func setlistRow(song: RemoteSetlistSong, index: Int, nextTitle: String?) -> some View {
        let isNext = song.title == nextTitle
        return Button {
            client.sendCommand("prioritizeNext:\(song.id)")
        } label: {
            HStack(spacing: 14) {
                // Indicateur position
                Text("\(index + 1)")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(palette.secondaryText.opacity(0.35))
                    .frame(width: 20, alignment: .trailing)

                Text(song.title)
                    .font(.system(size: 15, weight: isNext ? .semibold : .regular))
                    .foregroundStyle(isNext ? palette.accent : palette.primaryText.opacity(0.85))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isNext {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.accent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isNext ? palette.accent.opacity(0.08) : Color.clear
        )
    }

    // MARK: - Barre de commandes fixe

    private func commandBar(state: RemoteStateUpdate) -> some View {
        let connected = client.transport != .disconnected
        return HStack(spacing: 12) {
            commandButton(systemImage: "playpause.fill", label: "Play / Pause", enabled: connected) {
                client.sendCommand("playPause")
            }
            commandButton(systemImage: "forward.end.fill", label: "Next", enabled: connected) {
                client.sendCommand("nextTrack")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.40))
    }

    private func commandButton(
        systemImage: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(enabled ? palette.primaryText : palette.secondaryText.opacity(0.3))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(enabled ? 0.07 : 0.02))
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Waiting

    private var waitingView: some View {
        VStack(spacing: 16) {
            ProgressView().tint(palette.secondaryText)
            Text("Waiting for Velvet Show…")
                .font(.system(size: 15))
                .foregroundStyle(palette.secondaryText)
        }
    }

    // MARK: - Helpers

    private func formatRemaining(position: Double, duration: Double) -> String {
        let remaining = max(0, duration - position)
        let total = Int(remaining.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
