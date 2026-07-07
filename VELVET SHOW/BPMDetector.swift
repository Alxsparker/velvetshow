import AVFoundation
import Foundation

// MARK: - Détection automatique de BPM

/// Détecteur de tempo léger : enveloppe d'énergie (hop 512 samples) →
/// flux d'onsets (différences positives) → autocorrélation sur la plage
/// 60-190 BPM, avec correction d'octave vers la plage usuelle 90-180.
/// Lecture par blocs de 64k frames, sans charger tout le fichier en mémoire.
enum BPMDetector {
    static func detect(url: URL) async -> Double? {
        await Task.detached(priority: .utility) { () -> Double? in
            guard let file = try? AVAudioFile(forReading: url) else { return nil }
            let format = file.processingFormat
            let sampleRate = format.sampleRate
            guard sampleRate > 0, file.length > 0 else { return nil }

            let hop = 512
            let envRate = sampleRate / Double(hop)
            var envelope: [Float] = []
            envelope.reserveCapacity(Int(file.length) / hop + 1)

            let chunkFrames: AVAudioFrameCount = 65536
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else { return nil }

            var carry: [Float] = []
            while file.framePosition < file.length {
                buffer.frameLength = 0
                guard (try? file.read(into: buffer, frameCount: chunkFrames)) != nil,
                      buffer.frameLength > 0,
                      let channels = buffer.floatChannelData else { break }
                let frames = Int(buffer.frameLength)
                let channelCount = Int(format.channelCount)
                var mono = carry
                mono.reserveCapacity(carry.count + frames)
                for i in 0..<frames {
                    var s: Float = 0
                    for c in 0..<channelCount { s += channels[c][i] }
                    mono.append(s / Float(channelCount))
                }
                var idx = 0
                while idx + hop <= mono.count {
                    var sum: Float = 0
                    for j in idx..<(idx + hop) { sum += mono[j] * mono[j] }
                    envelope.append(sqrt(sum / Float(hop)))
                    idx += hop
                }
                carry = Array(mono[idx...])
            }

            guard envelope.count > Int(envRate * 10) else { return nil }

            var flux = [Float](repeating: 0, count: envelope.count)
            for i in 1..<envelope.count {
                flux[i] = max(0, envelope[i] - envelope[i - 1])
            }

            func score(forBPM bpm: Double) -> Double {
                let lag = Int((60.0 / bpm) * envRate)
                guard lag > 1, lag < flux.count / 2 else { return 0 }
                var s: Double = 0
                for i in 0..<(flux.count - lag) {
                    s += Double(flux[i] * flux[i + lag])
                }
                return s / Double(flux.count - lag)
            }

            var bestBPM: Double = 0
            var bestScore: Double = 0
            var bpm = 60.0
            while bpm <= 190.0 {
                let s = score(forBPM: bpm)
                if s > bestScore { bestScore = s; bestBPM = bpm }
                bpm += 0.5
            }
            guard bestBPM > 0 else { return nil }

            if bestBPM < 90 {
                let doubled = bestBPM * 2
                if doubled <= 190, score(forBPM: doubled) >= bestScore * 0.7 {
                    bestBPM = doubled
                }
            } else if bestBPM > 180 {
                let halved = bestBPM / 2
                if score(forBPM: halved) >= bestScore * 0.7 {
                    bestBPM = halved
                }
            }
            return bestBPM
        }.value
    }
}
