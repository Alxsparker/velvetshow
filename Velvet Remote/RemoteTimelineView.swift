//
//  RemoteTimelineView.swift
//  Velvet Remote
//
//  Timeline iOS pure SwiftUI — zéro dépendance macOS/AVFoundation.
//  Affiche : barre de progression, playhead, grille temporelle, blocs mémos.
//

import SwiftUI

struct RemoteTimelineView: View {
    let duration: Double
    let currentPosition: Double
    let memos: [RemoteTimelineMemo]
    let palette: PrompterPalette

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let h = max(1, geo.size.height)
            ZStack(alignment: .leading) {
                background
                progressFill(width: w)
                timeGrid(width: w, height: h)
                memoBlocks(width: w, height: h)
                playhead(width: w, height: h)
                durationLabel(width: w, height: h)
            }
        }
    }

    // MARK: - Couches

    private var background: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.black.opacity(0.72))
    }

    private func progressFill(width: CGFloat) -> some View {
        let ratio = duration > 0 ? min(1, currentPosition / duration) : 0
        return Rectangle()
            .fill(palette.accent.opacity(0.18))
            .frame(width: width * ratio)
            .frame(maxHeight: .infinity, alignment: .leading)
            .clipped()
    }

    private func timeGrid(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach(0..<5, id: \.self) { i in
                Rectangle()
                    .fill(palette.secondaryText.opacity(0.2))
                    .frame(width: 1, height: height)
                    .offset(x: width * CGFloat(i) / 4)
            }
        }
    }

    private func memoBlocks(width: CGFloat, height: CGFloat) -> some View {
        let blockHeight = height - 8
        let currentID = currentMemoID
        return ZStack(alignment: .leading) {
            ForEach(memos) { memo in
                let x = xPos(memo.startTime, width: width)
                let blockW = max(4, CGFloat(memo.duration / max(1, duration)) * width)
                let isCurrent = memo.id == currentID
                let isPast = memo.startTime + memo.duration < currentPosition

                RoundedRectangle(cornerRadius: 4)
                    .fill(blockFill(isCurrent: isCurrent, isPast: isPast, hasMidi: memo.hasMidi))
                    .frame(width: blockW, height: blockHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(isCurrent ? palette.accent : .clear, lineWidth: 1.5)
                    )
                    .overlay(alignment: .leading) {
                        Text(memo.title)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(isCurrent ? palette.primaryText : palette.secondaryText)
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                    }
                    .offset(x: x, y: 4)
            }
        }
    }

    private func playhead(width: CGFloat, height: CGFloat) -> some View {
        let x = xPos(currentPosition, width: width)
        return Rectangle()
            .fill(palette.accent)
            .frame(width: 2, height: height)
            .offset(x: x)
    }

    private func durationLabel(width: CGFloat, height: CGFloat) -> some View {
        Text(timecode(duration))
            .font(.system(size: 10, weight: .regular).monospacedDigit())
            .foregroundStyle(palette.secondaryText)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(palette.background.opacity(0.75), in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 6)
            .padding(.bottom, 3)
    }

    // MARK: - Helpers

    private func xPos(_ t: Double, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(max(0, min(t, duration)) / duration) * width
    }

    private var currentMemoID: String? {
        memos
            .filter { $0.startTime <= currentPosition && $0.startTime + $0.duration > currentPosition }
            .sorted { $0.startTime > $1.startTime }
            .first?.id
    }

    private func blockFill(isCurrent: Bool, isPast: Bool, hasMidi: Bool) -> Color {
        if isCurrent { return palette.accent.opacity(0.45) }
        if isPast    { return palette.secondaryText.opacity(0.15) }
        if hasMidi   { return palette.accent.opacity(0.22) }
        return palette.primaryText.opacity(0.20)
    }

    private func timecode(_ t: Double) -> String {
        let total = max(0, Int(t.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
