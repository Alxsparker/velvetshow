//
//  WaveformTimelineView.swift
//  VELVET SHOW
//
//  Timeline audio reutilisable : waveform simplifiee, playhead et blocs
//  de memos lisibles. L'analyse est volontairement legere (peak + RMS),
//  suffisante for une lecture scene sans spectrogramme ni FFT.
//

import SwiftUI
import AVFoundation

// WaveformTimelineMemo est défini dans PrompterShared.swift (partagé Mac + iOS)

enum WaveformTimelineDisplayMode: String, CaseIterable, Identifiable {
    case waveformOnly
    case waveformAndMemos
    case memosOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .waveformOnly:     return "Waveform"
        case .waveformAndMemos: return "Waveform + Memos"
        case .memosOnly:        return "Memos"
        }
    }
}

struct WaveformTimelineView: View {
    let audioURL: URL?
    let duration: TimeInterval
    let currentPosition: TimeInterval
    let memos: [WaveformTimelineMemo]
    let displayMode: WaveformTimelineDisplayMode
    let showsModePicker: Bool
    let palette: WaveformTimelinePalette

    @State private var selectedMode: WaveformTimelineDisplayMode
    @State private var analysis: [WaveformPeak] = []
    @State private var analyzedURL: URL?

    init(
        audioURL: URL?,
        duration: TimeInterval,
        currentPosition: TimeInterval,
        memos: [WaveformTimelineMemo],
        displayMode: WaveformTimelineDisplayMode = .waveformAndMemos,
        showsModePicker: Bool = false,
        palette: WaveformTimelinePalette = .standard
    ) {
        self.audioURL = audioURL
        self.duration = max(1, duration)
        self.currentPosition = currentPosition
        self.memos = memos
        self.displayMode = displayMode
        self.showsModePicker = showsModePicker
        self.palette = palette
        self._selectedMode = State(initialValue: displayMode)
    }

    private var activeMode: WaveformTimelineDisplayMode {
        showsModePicker ? selectedMode : displayMode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsModePicker {
                Picker("Affichage timeline", selection: $selectedMode) {
                    ForEach(WaveformTimelineDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
            }

            GeometryReader { geo in
                let width = max(1, geo.size.width)
                let height = max(1, geo.size.height)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(palette.background)

                    // Sous-vues Equatable : leurs bodies ne sont réévalués
                    // que si fichier/taille/états mémos changent — pas à
                    // chaque tick de position (30 Hz). Le Path (900 rects)
                    // et l'assignation des lanes ne sont donc recalculés
                    // qu'au changement de fichier ou de taille.
                    if activeMode != .memosOnly {
                        let vPad = height * 0.12
                        WaveformShapeView(
                            peaks: analysis,
                            cacheKey: analyzedURL,
                            width: width,
                            height: max(1, height - vPad * 2),
                            fill: palette.waveform.opacity(0.96)
                        )
                        .equatable()
                        .padding(.vertical, vPad)
                    }

                    WaveformGridView(width: width, height: height, color: palette.grid.opacity(0.45))
                        .equatable()

                    if activeMode != .waveformOnly {
                        let current = currentMemoID
                        let next = nextMemoID
                        MemoBlocksView(
                            memos: memos,
                            width: width,
                            height: height,
                            duration: duration,
                            palette: palette,
                            currentID: current,
                            nextID: next,
                            pastIDs: pastMemoIDs
                        )
                        .equatable()
                    }

                    playhead(width: width, height: height)

                    Text(timecode(duration))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(palette.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(palette.background.opacity(0.75), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.trailing, 6)
                        .padding(.bottom, 4)
                }
            }
        }
        .task(id: audioURL) {
            await analyzeIfNeeded()
        }
    }

    private func playhead(width: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(palette.playhead)
            .frame(width: 3, height: height)
            .shadow(color: palette.playhead.opacity(0.4), radius: 4)
            .offset(x: xPosition(currentPosition, width: width) - 1.5)
            .animation(.linear(duration: 1.0 / 30.0), value: currentPosition)
    }

    private var currentMemoID: String? {
        memos.last { memo in
            memo.startTime <= currentPosition && currentPosition <= memo.startTime + memo.duration
        }?.id
    }

    private var nextMemoID: String? {
        memos.first { $0.startTime > currentPosition }?.id
    }

    /// Mémos entièrement passés — ne change qu'aux franchissements de
    /// bornes, pas à chaque tick : clé d'équivalence de MemoBlocksView.
    private var pastMemoIDs: Set<String> {
        var past: Set<String> = []
        for memo in memos where memo.startTime + memo.duration < currentPosition {
            past.insert(memo.id)
        }
        return past
    }

    private func xPosition(_ seconds: TimeInterval, width: CGFloat) -> CGFloat {
        CGFloat(min(1, max(0, seconds / duration))) * width
    }

    private func analyzeIfNeeded() async {
        guard let audioURL else {
            analysis = []
            analyzedURL = nil
            return
        }
        guard analyzedURL != audioURL else { return }
        let result = await WaveformAnalyzer.analyze(url: audioURL, targetSampleCount: 900)
        analyzedURL = audioURL
        analysis = result
    }

    private func timecode(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct WaveformTimelinePalette {
    let background: Color
    let waveform: Color
    let grid: Color
    let playhead: Color
    let memo: Color
    let pastMemo: Color
    let currentMemo: Color
    let nextMemo: Color
    let nextMemoBorder: Color
    let midiMemo: Color
    let memoText: Color
    let secondaryText: Color

    static let standard = WaveformTimelinePalette(
        background: Color.black.opacity(0.12),
        waveform: Color(red: 0.82, green: 0.80, blue: 0.74).opacity(0.78),
        grid: Color.secondary.opacity(0.28),
        playhead: Color(red: 1.0, green: 0.68, blue: 0.24),
        memo: Color(red: 0.96, green: 0.82, blue: 0.55),
        pastMemo: Color(red: 0.76, green: 0.70, blue: 0.58),
        currentMemo: Color(red: 1.0, green: 0.68, blue: 0.24),
        nextMemo: Color(red: 0.98, green: 0.88, blue: 0.66),
        nextMemoBorder: Color(red: 0.88, green: 0.58, blue: 0.12),
        midiMemo: Color(red: 1.0, green: 0.76, blue: 0.42),
        memoText: Color.black,
        secondaryText: Color.secondary
    )

    static func prompter(_ palette: PrompterPalette) -> WaveformTimelinePalette {
        WaveformTimelinePalette(
            background: palette.primaryText.opacity(0.08),
            waveform: palette.accent.opacity(0.78),
            grid: palette.secondaryText.opacity(0.35),
            playhead: palette.accent,
            memo: Color(red: 0.96, green: 0.82, blue: 0.55),
            pastMemo: Color(red: 0.76, green: 0.70, blue: 0.58),
            currentMemo: Color(red: 1.0, green: 0.68, blue: 0.24),
            nextMemo: Color(red: 0.98, green: 0.88, blue: 0.66),
            nextMemoBorder: palette.accent,
            midiMemo: Color(red: 1.0, green: 0.76, blue: 0.42),
            memoText: .black,
            secondaryText: palette.secondaryText
        )
    }
}

private struct WaveformPeak: Hashable {
    let peak: Float
    let rms: Float

    static func placeholder(count: Int) -> [WaveformPeak] {
        let safeCount = max(80, count)
        return (0..<safeCount).map { index in
            let value = Float(0.22 + 0.18 * sin(Double(index) * 0.19) + 0.10 * sin(Double(index) * 0.043))
            return WaveformPeak(peak: max(0.08, value), rms: max(0.04, value * 0.55))
        }
    }
}

private enum WaveformAnalyzer {
    static func analyze(url: URL, targetSampleCount: Int) async -> [WaveformPeak] {
        await Task.detached(priority: .utility) {
            do {
                let file = try AVAudioFile(forReading: url)
                let frameCount = AVAudioFrameCount(file.length)
                guard frameCount > 0,
                      let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
                    return []
                }
                try file.read(into: buffer)
                guard let channels = buffer.floatChannelData else { return [] }

                let frames = Int(buffer.frameLength)
                let channelCount = Int(buffer.format.channelCount)
                let bucketCount = max(80, min(targetSampleCount, frames))
                let framesPerBucket = max(1, frames / bucketCount)
                var result: [WaveformPeak] = []
                result.reserveCapacity(bucketCount)

                var frame = 0
                while frame < frames {
                    let end = min(frames, frame + framesPerBucket)
                    var peak: Float = 0
                    var sumSquares: Float = 0
                    var count: Float = 0

                    for sampleIndex in frame..<end {
                        var mixed: Float = 0
                        for channel in 0..<channelCount {
                            mixed += channels[channel][sampleIndex]
                        }
                        let sample = mixed / Float(max(1, channelCount))
                        let absSample = abs(sample)
                        peak = max(peak, absSample)
                        sumSquares += sample * sample
                        count += 1
                    }

                    let rms = count > 0 ? sqrt(sumSquares / count) : 0
                    result.append(WaveformPeak(peak: min(1, peak), rms: min(1, rms)))
                    frame = end
                }
                return result
            } catch {
                return []
            }
        }.value
    }
}

// MARK: - Sous-vues Equatable (phase 2 perfs)
//
// La vue parente est reconstruite à 30 Hz (elle reçoit currentPosition).
// Ces sous-vues, marquées .equatable(), ne réévaluent leur body que si
// leurs entrées changent réellement : le Path de la waveform (900 rects)
// et l'assignation gloutonne des lanes ne sont plus recalculés qu'au
// changement de fichier, de taille ou d'état des mémos — plus jamais à
// chaque tick de position.

/// Forme de la waveform — recalculée uniquement si (fichier, taille) change.
fileprivate struct WaveformShapeView: View, Equatable {
    let peaks: [WaveformPeak]
    let cacheKey: URL?
    let width: CGFloat
    let height: CGFloat
    let fill: Color

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.cacheKey == rhs.cacheKey
            && lhs.peaks.count == rhs.peaks.count
            && lhs.width == rhs.width
            && lhs.height == rhs.height
    }

    var body: some View {
        waveformPath(size: CGSize(width: width, height: height))
            .fill(fill)
    }

    private func waveformPath(size: CGSize) -> Path {
        var path = Path()
        let peaks = self.peaks.isEmpty ? WaveformPeak.placeholder(count: Int(size.width / 3)) : self.peaks
        guard !peaks.isEmpty else { return path }

        let midY = size.height / 2
        let step = size.width / CGFloat(max(1, peaks.count - 1))

        path.move(to: CGPoint(x: 0, y: midY))
        for index in peaks.indices {
            let peak = CGFloat(peaks[index].peak)
            let rms = CGFloat(peaks[index].rms)
            let x = CGFloat(index) * step
            let amplitude = max(2, (peak * 0.72 + rms * 0.28) * size.height * 0.42)
            path.addRect(CGRect(x: x, y: midY - amplitude, width: max(1.5, step * 0.65), height: amplitude * 2))
        }
        return path
    }
}

/// Grille temporelle fixe — dépend uniquement de la taille.
fileprivate struct WaveformGridView: View, Equatable {
    let width: CGFloat
    let height: CGFloat
    let color: Color

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.width == rhs.width && lhs.height == rhs.height
    }

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(0..<5, id: \.self) { index in
                let x = width * CGFloat(index) / 4
                Rectangle()
                    .fill(color)
                    .frame(width: 1, height: height)
                    .offset(x: x)
            }
        }
    }
}

/// Blocs mémos — réévalués uniquement quand un état de mémo change
/// (courant/suivant/passés), c'est-à-dire aux franchissements de bornes,
/// pas à chaque tick de position.
fileprivate struct MemoBlocksView: View, Equatable {
    let memos: [WaveformTimelineMemo]
    let width: CGFloat
    let height: CGFloat
    let duration: TimeInterval
    let palette: WaveformTimelinePalette
    let currentID: String?
    let nextID: String?
    let pastIDs: Set<String>

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.width == rhs.width
            && lhs.height == rhs.height
            && lhs.duration == rhs.duration
            && lhs.currentID == rhs.currentID
            && lhs.nextID == rhs.nextID
            && lhs.pastIDs == rhs.pastIDs
            && lhs.memos == rhs.memos
    }

    /// Position et largeur d'un bloc, calculées par l'assignation gloutonne.
    private struct MemoBlockLayout {
        var x: CGFloat
        var width: CGFloat
        var lane: Int
    }

    var body: some View {
        let layouts = memoBlockLayouts(width: width, height: height)
        ZStack(alignment: .leading) {
            ForEach(memos) { memo in
                let layout = layouts[memo.id] ?? MemoBlockLayout(
                    x: xPosition(memo.startTime, width: width), width: 96, lane: 0
                )
                memoBlockView(
                    memo, layout: layout,
                    isCurrent: memo.id == currentID,
                    isNext: memo.id == nextID,
                    isPast: pastIDs.contains(memo.id),
                    next: nextID
                )
            }
        }
    }

    /// Assignation séquentielle gloutonne anti-collision : mémos triés par
    /// startTime, chacun placé dans la première lane libre (en pixels réels,
    /// largeur minimale 96 pt incluse). Si toutes les lanes sont occupées —
    /// cas du prompteur at une seule lane — le dernier bloc de la lane qui se
    /// libère le plus tôt est TRONQUÉ au début du nouveau bloc : dégradation
    /// propre, jamais de superposition. Les timestamps ne sont pas modifiés.
    private func memoBlockLayouts(width: CGFloat, height: CGFloat) -> [String: MemoBlockLayout] {
        let laneCount = max(1, Int((height - 58) / 38))
        let sorted = memos.sorted { $0.startTime < $1.startTime }
        var laneEnds = [CGFloat](repeating: -.greatestFiniteMagnitude, count: laneCount)
        var laneLastID = [String?](repeating: nil, count: laneCount)
        var result: [String: MemoBlockLayout] = [:]

        for memo in sorted {
            let x = xPosition(memo.startTime, width: width)
            let natural = max(96, CGFloat(max(1, memo.duration) / duration) * width)
            let w = min(natural, max(96, width - x))

            if let free = laneEnds.indices.first(where: { laneEnds[$0] <= x + 0.5 }) {
                result[memo.id] = MemoBlockLayout(x: x, width: w, lane: free)
                laneEnds[free] = x + w
                laneLastID[free] = memo.id
            } else {
                let lane = laneEnds.indices.min(by: { laneEnds[$0] < laneEnds[$1] })!
                if let prevID = laneLastID[lane], var prev = result[prevID] {
                    prev.width = max(4, x - prev.x)
                    result[prevID] = prev
                }
                result[memo.id] = MemoBlockLayout(x: x, width: w, lane: lane)
                laneEnds[lane] = x + w
                laneLastID[lane] = memo.id
            }
        }
        return result
    }

    /// Bloc individuel de mémo, avec emphase "loupe" sur le SUIVANT :
    /// - largeur élargie at la phrase entière (fixedSize) ;
    /// - zoom 160 % via scaleEffect ;
    /// - expansion et zoom ancrés sur le bord DROIT : le débordement part
    ///   to la gauche (mémos déjà joués, atténués) et ne cache jamais les
    ///   mémos at venir ni le bord droit de la timeline.
    /// Purement visuel — le layout anti-collision reste sur layout.width.
    @ViewBuilder
    private func memoBlockView(
        _ memo: WaveformTimelineMemo,
        layout: MemoBlockLayout,
        isCurrent: Bool,
        isNext: Bool,
        isPast: Bool,
        next: String?
    ) -> some View {
        let strokeColor: Color = isNext ? palette.nextMemoBorder : (isCurrent ? palette.playhead : .clear)
        let fill = memoFill(isCurrent: isCurrent, isNext: isNext, isPast: isPast, hasMidi: memo.hasMidi)

        // Largeur de la pilule du SUIVANT : assez large for la phrase
        // entière (mesure NSFont, même fonte que le Text), mais plafonnée
        // for que la version zoomée ×1.6 — ancrée sur le bord droit du
        // bloc — ne sorte jamais de l'écran at gauche. Si le plafond mord,
        // le minimumScaleFactor/troncature du Text reprend la main.
        let pillWidth: CGFloat = {
            guard isNext else { return layout.width }
            let font = NSFont.systemFont(ofSize: 15, weight: .bold)
            let textWidth = (memo.title as NSString)
                .size(withAttributes: [.font: font]).width + 22
            let maxAllowed = (layout.x + layout.width) / 1.6
            return max(layout.width, min(textWidth, maxAllowed))
        }()

        Text(memo.title)
            .font(.system(size: 15, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(palette.memoText)
            .padding(.horizontal, 10)
            .frame(width: pillWidth, height: 34, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(strokeColor, lineWidth: isNext ? 3 : 2)
            }
            .shadow(
                color: isNext ? palette.nextMemoBorder.opacity(0.55) : .clear,
                radius: isNext ? 5 : 0
            )
            .opacity(isPast && !isCurrent ? 0.72 : 1)
            .frame(width: layout.width, height: 34, alignment: isNext ? .trailing : .leading)
            .scaleEffect(isNext ? 1.6 : 1.0, anchor: isNext ? .trailing : .leading)
            .zIndex(isNext ? 1 : 0)
            // Pas d'animation sur le passage de loupe : la largeur de la
            // pilule (frames) s'animerait alors que celle du texte (fixedSize)
            // change instantanément → le texte sortait de la pilule pendant
            // la transition. En instantané, texte et pilule restent synchrones.
            .offset(x: layout.x, y: 12 + CGFloat(layout.lane * 38))
    }

    private func memoFill(isCurrent: Bool, isNext: Bool, isPast: Bool, hasMidi: Bool) -> Color {
        if isCurrent { return palette.currentMemo }
        if isPast { return palette.pastMemo }
        if hasMidi { return palette.midiMemo }
        if isNext { return palette.nextMemo }
        return palette.memo
    }

    private func xPosition(_ seconds: TimeInterval, width: CGFloat) -> CGFloat {
        CGFloat(min(1, max(0, seconds / duration))) * width
    }
}
