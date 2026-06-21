//
//  RemotePrompterView.swift
//  Velvet Remote
//
//  Écran principal :
//  - bandeau compact en haut (1 ligne : badge · titre · timer · next · commandes)
//  - prompteur au centre (header PrompterPreviewView masqué)
//  - timeline en bas (96 pt fixes, espace réservé via VStack)
//

import SwiftUI

struct RemotePrompterView: View {
    @Environment(VelvetRemoteClient.self) private var client

    private let palette = PrompterPalette(
        background: Color(hex: 0x14101A),
        primaryText: Color(hex: 0xE6CC93),
        secondaryText: Color(hex: 0xC9A769),
        accent: Color(hex: 0xC9A769)
    )

    var body: some View {
        ZStack {
            if let state = client.latestState {
                contentView(state: state)
            } else {
                waitingView
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Contenu principal

    @ViewBuilder
    private func contentView(state: RemoteStateUpdate) -> some View {
        VStack(spacing: 0) {
            // Bandeau compact : toutes les infos en une ligne
            compactBand(state: state)

            // Prompter : occupe tout l'espace restant, header masqué
            PrompterPreviewView(
                title: state.songTitle ?? "—",
                currentMemoTitle: nil,
                currentMemoText: state.memoText,
                nextMemoText: nil,
                remainingTime: "",
                playbackState: state.playbackState,
                audioURL: nil,
                duration: state.durationSeconds,
                currentPosition: state.positionSeconds,
                timelineMemos: [],
                palette: palette,
                upcomingTitle: nil,
                showHeader: false
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Timeline : espace réservé, jamais chevauchée par le prompteur
            RemoteTimelineView(
                duration: state.durationSeconds,
                currentPosition: state.positionSeconds,
                memos: state.timelineMemos,
                palette: palette
            )
            .frame(height: 96)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(palette.background)
        }
        .background(palette.background.ignoresSafeArea())
    }

    // MARK: - Bandeau compact

    private func compactBand(state: RemoteStateUpdate) -> some View {
        HStack(spacing: 8) {
            // Badge réseau
            RemoteConnectionBadge(transport: client.transport)

            // Titre courant
            Text(state.songTitle ?? "—")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 4)

            // Timer
            Text(formatRemaining(position: state.positionSeconds, duration: state.durationSeconds))
                .font(.system(size: 15, weight: .black).monospacedDigit())
                .foregroundStyle(palette.primaryText)
                .fixedSize()

            // Morceau suivant
            if let next = state.nextSongTitle, !next.isEmpty {
                Text("▶ \(next.uppercased())")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(palette.accent)
                    .lineLimit(1)
                    .layoutPriority(2)
            }

            // Commandes
            iconButton(systemImage: "playpause.fill", enabled: client.transport != .disconnected) {
                client.sendCommand("playPause")
            }
            iconButton(systemImage: "forward.end.fill", enabled: client.transport != .disconnected) {
                client.sendCommand("nextTrack")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.78))
    }

    private func iconButton(
        systemImage: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(enabled ? palette.primaryText.opacity(0.85) : palette.secondaryText.opacity(0.3))
                .frame(width: 36, height: 30)
                .contentShape(Rectangle())
        }
        .disabled(!enabled)
    }

    // MARK: - Waiting

    private var waitingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Waiting for data…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background.ignoresSafeArea())
    }

    // MARK: - Helpers

    private func formatRemaining(position: Double, duration: Double) -> String {
        let remaining = max(0, duration - position)
        let total = Int(remaining.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
