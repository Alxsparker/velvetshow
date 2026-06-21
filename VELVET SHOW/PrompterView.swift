//
//  PrompterView.swift
//  VELVET SHOW
//
//  Window Prompter — conçue for être déplacée sur un second écran
//  (Sidecar iPad, AirPlay, écran physique secondaire) et lue depuis
//  le pupitre ou les loges.
//
//  Principes :
//  - couleurs pilotees par PrompterTheme for etre lisibles en plein
//    jour, en soiree, ou en contraste maximum,
//  - 3 zones verticales :
//      1) bandeau supérieur : titre du song, temps restant et
//         indicateur d'état Play/Pause/Stop ;
//      2) zone centrale : mémo actif (paroles, count-in...) en très
//         grande police lisible at plusieurs mètres ;
//      3) bandeau inférieur : aperçu du prochain mémo, dimmé.
//  - pas d'interaction (lecture seule), volontairement minimaliste.
//
//  La vue n'a aucun timer : elle observe directement
//  `appState.audioEngine.currentPosition` qui est mis at jour at 30 Hz
//  par le moteur. Grâce at @Observable, SwiftUI ré-évalue le body
//  automatiquement at chaque variation.
//

import SwiftUI

#if os(macOS)
struct PrompterView: View {

    /// ID utilisé par `openWindow(id:)` for cibler cette scène depuis
    /// la fenêtre principale.
    static let windowID = "prompter"

    @Environment(AppState.self) private var appState

    var body: some View {
        PrompterPreviewView(
            title: appState.currentlyLoadedTrack?.name ?? "No song loaded",
            currentMemoTitle: appState.currentMemo()?.shortName,
            currentMemoText: Self.memoDisplayText(appState.currentMemo()),
            nextMemoText: Self.memoDisplayText(appState.nextMemo()),
            remainingTime: formatTime(appState.audioEngine.effectiveRemaining),
            playbackState: RemotePlaybackState(appState.audioEngine.state),
            audioURL: appState.currentlyLoadedTrack.flatMap { appState.resolvedAudioURL(for: $0) },
            duration: appState.audioEngine.effectiveDuration,
            currentPosition: appState.audioEngine.effectivePosition,
            timelineMemos: timelineMemos,
            palette: appState.prompterTheme.palette,
            upcomingTitle: appState.upcomingTrack?.name
        )
        .frame(minWidth: 800, minHeight: 500)
        .background {
            PrompterWindowAccessor { window in
                PrompterWindowController.configure(window)
                appState.refreshPrompterEnvironment()
            }
        }
        .onAppear {
            appState.setPrompterActive(true)
            appState.refreshPrompterEnvironment()
        }
        .onDisappear {
            appState.setPrompterActive(false)
            appState.refreshPrompterEnvironment()
        }
    }

    // MARK: - Helpers

    /// "m:ss" for rester lisible depuis 3+ mètres.
    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
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

    private static func memoDisplayText(_ memo: EditableMemo?) -> String? {
        guard let memo else { return nil }
        let text = memo.memo.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
        let title = memo.shortName.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }
}
#endif // os(macOS)

// MARK: - Preview themable Prompter

/// Vue de base du Prompter. Elle sert deja a la fenetre reelle et donnera
/// aux prochaines vues scene les memes tokens de theme.
struct PrompterPreviewView: View {
    let title: String
    let currentMemoTitle: String?
    let currentMemoText: String?
    let nextMemoText: String?
    let remainingTime: String
    let playbackState: RemotePlaybackState
    let audioURL: URL?
    let duration: TimeInterval
    let currentPosition: TimeInterval
    let timelineMemos: [WaveformTimelineMemo]
    let palette: PrompterPalette
    /// Title du song qui sera réellement joué ensuite (queue prioritaire,
    /// puis prochain naturel). nil = fin de setlist ou hors contexte show.
    var upcomingTitle: String? = nil
    /// iOS uniquement : false masque le header (titre, timer, next song) quand
    /// RemotePrompterView affiche son propre bandeau compact à la place.
    var showHeader: Bool = true

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()

            VStack(spacing: 20) {
                if showHeader { header }
                currentMemoView
                    .frame(maxHeight: .infinity)
                    .layoutPriority(3)
                #if os(macOS)
                // Le mémo suivant est annoncé par la timeline (bloc mis en
                // évidence — bordure, halo, titre agrandi). Les titres de
                // mémos portant la première ligne de chaque paragraphe, le
                // panneau texte dédié était redondant : supprimé for rendre
                // ~150 pt aux paroles.
                waveformTimeline
                    .frame(height: 72)
                    .padding(.bottom, 22)
                    .layoutPriority(1)
                #endif
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 28)
        }
    }

    // MARK: - Sous-vues

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            // État de lecture (pastille discrète).
            Circle()
                .fill(stateColor)
                .frame(width: playbackState == .playing ? 13 : 11, height: playbackState == .playing ? 13 : 11)
                .shadow(color: playbackState == .playing ? stateColor.opacity(0.65) : .clear, radius: 9, x: 0, y: 0)

            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            // Colonne droite : temps restant (l'info la plus regardée) avec,
            // juste en dessous, le song qui suivra réellement — lisible
            // d'un seul mouvement de regard, sans cadre ni label.
            VStack(alignment: .trailing, spacing: 2) {
                Text(remainingTime)
                    .font(.system(size: 34, weight: .black).monospacedDigit())
                    .foregroundStyle(palette.primaryText)
                if let upcomingTitle, !upcomingTitle.isEmpty {
                    Text("▶ \(upcomingTitle.uppercased())")
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(palette.accent)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }

    private var currentMemoView: some View {
        Group {
            if let text = currentMemoText, !text.isEmpty {
                memoTextView(text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("—")
                    .font(.system(size: 76, weight: .light))
                    .foregroundStyle(palette.secondaryText.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// Paliers relevés après la suppression du panneau "PROCHAIN" (+150 pt
    /// for les paroles). Le minimumScaleFactor (0.4/0.45) garantit que le
    /// texte entier reste visible quelle que soit la taille de fenêtre.
    private func currentMemoFontSize(for text: String) -> CGFloat {
        let lineCount = text.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
        #if os(iOS)
        // iPad : paliers plus larges pour exploiter la surface disponible.
        if text.count > 200 || lineCount >= 9 { return 42 }
        if text.count > 120 || lineCount >= 5 { return 60 }
        return 96
        #else
        if text.count > 180 || lineCount >= 7 { return 42 }
        if text.count > 100 || lineCount >= 4 { return 56 }
        return 72
        #endif
    }

    @ViewBuilder
    private func memoTextView(_ text: String) -> some View {
        if ChordLineDetector.containsChordLines(in: text) {
            let fontSize = currentMemoFontSize(for: text)
            VStack(alignment: .center, spacing: 5) {
                ForEach(Array(text.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                    let isChordLine = ChordLineDetector.isChordLine(line)
                    Text(line.isEmpty ? " " : line)
                        .font(.system(
                            size: isChordLine ? fontSize * 0.72 : fontSize * 0.82,
                            weight: isChordLine ? .bold : .semibold,
                            design: isChordLine ? .monospaced : .default
                        ))
                        .foregroundStyle(isChordLine ? palette.accent : palette.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
            Text(text)
                .font(.system(size: currentMemoFontSize(for: text), weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.primaryText)
                .minimumScaleFactor(0.4)
        }
    }

    #if os(macOS)
    private var waveformTimeline: some View {
        WaveformTimelineView(
            audioURL: audioURL,
            duration: duration,
            currentPosition: currentPosition,
            memos: timelineMemos,
            displayMode: .waveformAndMemos,
            showsModePicker: false,
            palette: .prompter(palette)
        )
    }
    #endif

    // MARK: - Helpers

    private var stateColor: Color {
        switch playbackState {
        case .playing:  return .green
        case .stopping: return .orange
        case .paused:   return .yellow
        case .stopped:  return palette.secondaryText.opacity(0.45)
        }
    }
}

// ChordLineDetector est défini dans PrompterShared.swift (partagé Mac + iOS)
