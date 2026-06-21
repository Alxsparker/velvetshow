import AVFoundation
import Accelerate
import Foundation

// MARK: - Résultat d'analyse

struct LoudnessResult {
    /// Loudness intégré EBU R128 / ITU-R BS.1770-4 (LUFS-I).
    let integratedLUFS: Double
    /// True Peak via sur-échantillonnage ×4 AVAudioConverter (dBTP).
    let truePeakDB: Double
    /// Peak PCM brut (max absolu des échantillons avant sur-échantillonnage, dBFS).
    let pcmPeakDB: Double
    /// Gain de normalisation recommandé for atteindre la cible (dB).
    let normGainDB: Double
}

enum LoudnessError: LocalizedError {
    case invalidFile
    case emptySignal
    var errorDescription: String? {
        switch self {
        case .invalidFile: return "Invalid or empty audio file."
        case .emptySignal: return "Signal too weak to measure."
        }
    }
}

// MARK: - Analyseur

/// Mesure LUFS-I (EBU R128 / ITU-R BS.1770-4) et True Peak sur un fichier audio.
/// L'analyse est asynchrone et non destructive — aucun fichier n'est modifié.
final class LoudnessAnalyzer {

    // MARK: K-weighting filter

    struct BiquadCoeffs {
        var b0, b1, b2, a1, a2: Double
    }

    /// Calcule les coefficients du filtre de pondération K (deux étages biquad)
    /// for un taux d'échantillonnage arbitraire.
    static func kWeightingCoeffs(sampleRate fs: Double) -> (shelf: BiquadCoeffs, hp: BiquadCoeffs) {
        // Étage 1 : filtre plateau haute fréquence (+4 dB, pré-filtre tête)
        let dbGain  = 3.999843853973347
        let f0Shelf = 1681.974450955533
        let qShelf  = 0.7071752369554196

        let A     = pow(10.0, dbGain / 40.0)
        let w0    = 2.0 * Double.pi * f0Shelf / fs
        let cosW0 = cos(w0), sinW0 = sin(w0)
        let alpha = sinW0 / (2.0 * qShelf)
        let sqrtA = sqrt(A)

        let b0s = A * ((A+1) + (A-1)*cosW0 + 2*sqrtA*alpha)
        let b1s = -2 * A * ((A-1) + (A+1)*cosW0)
        let b2s = A * ((A+1) + (A-1)*cosW0 - 2*sqrtA*alpha)
        let a0s =     (A+1) - (A-1)*cosW0 + 2*sqrtA*alpha
        let a1s = 2 * ((A-1) - (A+1)*cosW0)
        let a2s =     (A+1) - (A-1)*cosW0 - 2*sqrtA*alpha
        let shelf = BiquadCoeffs(b0: b0s/a0s, b1: b1s/a0s, b2: b2s/a0s, a1: a1s/a0s, a2: a2s/a0s)

        // Étage 2 : passe-haut RLB (~38 Hz, élimine les basses)
        let f0HP = 38.13547087602444
        let qHP  = 0.5003270373238773

        let w0h    = 2.0 * Double.pi * f0HP / fs
        let cosW0h = cos(w0h), sinW0h = sin(w0h)
        let alphah = sinW0h / (2.0 * qHP)

        let b0h = (1 + cosW0h) / 2
        let b1h = -(1 + cosW0h)
        let b2h = (1 + cosW0h) / 2
        let a0h = 1 + alphah
        let a1h = -2 * cosW0h
        let a2h = 1 - alphah
        let hp = BiquadCoeffs(b0: b0h/a0h, b1: b1h/a0h, b2: b2h/a0h, a1: a1h/a0h, a2: a2h/a0h)

        return (shelf, hp)
    }

    private static func applyBiquad(_ c: BiquadCoeffs, input: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: input.count)
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for i in 0..<input.count {
            let x = Double(input[i])
            let y = c.b0*x + c.b1*x1 + c.b2*x2 - c.a1*y1 - c.a2*y2
            out[i] = Float(y)
            x2 = x1; x1 = x; y2 = y1; y1 = y
        }
        return out
    }

    // MARK: True Peak via AVAudioConverter

    /// Sur-échantillonne le signal ×4 via AVAudioConverter et retourne
    /// le maximum absolu en dBTP. Traite les canaux séparément for limiter
    /// la mémoire peak, puis retourne le max global.
    static func truePeakDB(
        from _: AVAudioPCMBuffer,
        sourceFormat: AVAudioFormat,
        nCh: Int,
        chSamples: [[Float]],
        totalFrames: Int
    ) -> Double {
        let fs4 = sourceFormat.sampleRate * 4.0

        guard let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: fs4,
            channels: 1,           // on convertit canal par canal
            interleaved: false
        ) else { return -144.0 }

        var peak: Float = 0

        for ch in 0..<nCh {
            guard let inFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sourceFormat.sampleRate,
                channels: 1,
                interleaved: false
            ),
            let converter = AVAudioConverter(from: inFormat, to: outFormat) else { continue }

            let samples = chSamples[ch]
            let inFrames = AVAudioFrameCount(samples.count)
            let outFrames = AVAudioFrameCount(Double(inFrames) * 4.0) + 8

            guard let inBuf  = AVAudioPCMBuffer(pcmFormat: inFormat,  frameCapacity: inFrames),
                  let outBuf = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outFrames)
            else { continue }

            inBuf.frameLength = inFrames
            samples.withUnsafeBufferPointer { ptr in
                inBuf.floatChannelData![0].update(from: ptr.baseAddress!, count: samples.count)
            }

            var inputConsumed = false
            let status = converter.convert(to: outBuf, error: nil) { _, outStatus in
                if inputConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                outStatus.pointee = .haveData
                inputConsumed = true
                return inBuf
            }

            if status == .error { continue }

            let count = Int(outBuf.frameLength)
            guard count > 0, let ptr = outBuf.floatChannelData?[0] else { continue }
            var chPeak: Float = 0
            vDSP_maxmgv(ptr, 1, &chPeak, vDSP_Length(count))
            peak = max(peak, chPeak)
        }

        return peak > 1e-10 ? 20.0 * log10(Double(peak)) : -144.0
    }

    // MARK: Analyse principale

    func analyze(url: URL, targetLUFS: Double) async throws -> LoudnessResult {
        let file = try AVAudioFile(forReading: url)
        let format   = file.processingFormat
        let fs       = format.sampleRate
        let nCh      = Int(format.channelCount)
        let totalFr  = Int(file.length)

        guard totalFr > 0, nCh > 0 else { throw LoudnessError.invalidFile }

        // Poids par canal (BS.1770 tableau 1 : L/R/C = 1.0 ; LFE = 0 ; Ls/Rs = 1.41)
        let weights: [Double] = {
            if nCh == 1 { return [1.0] }
            if nCh == 2 { return [1.0, 1.0] }
            if nCh == 3 { return [1.0, 1.0, 1.0] }
            if nCh == 4 { return [1.0, 1.0, 1.0, 1.0] }
            if nCh == 5 { return [1.0, 1.0, 1.0, 0.0, 1.41] }
            return [1.0, 1.0, 1.0, 0.0, 1.41, 1.41]
        }()

        // Lecture complète en mémoire par blocs
        let chunkSize = 65536
        var chSamples: [[Float]] = Array(repeating: [], count: nCh)
        for i in 0..<nCh { chSamples[i].reserveCapacity(totalFr) }

        file.framePosition = 0
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunkSize))!
        while file.framePosition < file.length {
            let toRead = AVAudioFrameCount(min(Int64(chunkSize), file.length - file.framePosition))
            buf.frameLength = toRead
            try file.read(into: buf, frameCount: toRead)
            guard let data = buf.floatChannelData else { break }
            for ch in 0..<nCh {
                chSamples[ch].append(contentsOf:
                    UnsafeBufferPointer(start: data[ch], count: Int(buf.frameLength)))
            }
        }

        let n = chSamples[0].count
        guard n > 0 else { throw LoudnessError.emptySignal }

        // Filtre K-weighting
        let (shelf, hp) = Self.kWeightingCoeffs(sampleRate: fs)
        var kw: [[Float]] = chSamples.map { Self.applyBiquad(hp, input: Self.applyBiquad(shelf, input: $0)) }

        // Peak PCM brut — max absolu sur tous les canaux, avant sur-échantillonnage.
        var rawPeak: Float = 0
        for ch in 0..<nCh {
            var chPeak: Float = 0
            chSamples[ch].withUnsafeBufferPointer {
                vDSP_maxmgv($0.baseAddress!, 1, &chPeak, vDSP_Length($0.count))
            }
            rawPeak = max(rawPeak, chPeak)
        }
        let pcmPeakDB = rawPeak > 1e-10 ? 20.0 * log10(Double(rawPeak)) : -144.0

        // True Peak : sur-échantillonnage ×4 via AVAudioConverter (BS.1770-4 §2.9)
        let truePeakDB = Self.truePeakDB(from: buf, sourceFormat: format, nCh: nCh,
                                         chSamples: chSamples, totalFrames: totalFr)

        // Loudness intégrée : blocs 400 ms / hop 100 ms
        let blockSize = max(1, Int(round(0.4 * fs)))
        let hopSize   = max(1, Int(round(0.1 * fs)))
        var blockL: [Double] = []

        var start = 0
        while start + hopSize <= n {
            let end   = min(start + blockSize, n)
            let count = end - start
            if count < blockSize / 2 { break }

            var wms = 0.0
            for ch in 0..<nCh {
                let w = ch < weights.count ? weights[ch] : 1.0
                guard w > 0 else { continue }
                var sumSq: Float = 0
                kw[ch].withUnsafeBufferPointer {
                    vDSP_svesq($0.baseAddress! + start, 1, &sumSq, vDSP_Length(count))
                }
                wms += w * Double(sumSq) / Double(count)
            }
            if wms > 1e-17 { blockL.append(-0.691 + 10.0 * log10(wms)) }
            start += hopSize
        }

        guard !blockL.isEmpty else {
            return LoudnessResult(integratedLUFS: -144, truePeakDB: truePeakDB,
                                  pcmPeakDB: pcmPeakDB, normGainDB: targetLUFS + 144)
        }

        // Porte absolue : −70 LUFS
        let absGated = blockL.filter { $0 >= -70.0 }
        guard !absGated.isEmpty else {
            return LoudnessResult(integratedLUFS: -144, truePeakDB: truePeakDB,
                                  pcmPeakDB: pcmPeakDB, normGainDB: targetLUFS + 144)
        }

        let mean1 = meanLoudness(absGated)

        // Porte relative : moyenne non-gatée − 10 LU
        let relGated = absGated.filter { $0 >= mean1 - 10.0 }
        let intLUFS  = relGated.isEmpty ? mean1 : meanLoudness(relGated)

        return LoudnessResult(integratedLUFS: intLUFS, truePeakDB: truePeakDB,
                              pcmPeakDB: pcmPeakDB, normGainDB: targetLUFS - intLUFS)
    }

    // Moyenne énergétique d'une liste de valeurs en LUFS
    private func meanLoudness(_ blocks: [Double]) -> Double {
        let sum = blocks.reduce(0.0) { $0 + pow(10.0, ($1 + 0.691) / 10.0) }
        return -0.691 + 10.0 * log10(sum / Double(blocks.count))
    }
}
