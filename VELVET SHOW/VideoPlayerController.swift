//
//  VideoPlayerController.swift
//  VELVET SHOW
//
//  Minimal AVPlayer wrapper used by the Prompter when a track has a video
//  attached. Sync is at the *command* level (play / pause / stop / seek) —
//  Velvet Show issues the same call to `audioEngine` and `videoController` at
//  the same point in the transport. No frame-level sync, no audio fade for the
//  video itself.
//
//  Out of scope:
//    • streaming or remote URLs (only local files in the Velvet Media folder),
//    • audio extraction (the video file's own audio track is muted — the
//      backtrack lives in `AudioEngine`),
//    • timeline synchronisation finer than the seek granularity (CMTime 600).
//

import Foundation
import AVFoundation

@MainActor
@Observable
final class VideoPlayerController {

    /// AVPlayer exposé pour la SwiftUI `VideoPlayer(player:)`. Toujours le
    /// même objet — on remplace son `currentItem` plutôt que de re-créer un
    /// player à chaque morceau, pour éviter les sauts visuels dans la vue.
    let player: AVPlayer

    /// URL actuellement chargée (ou nil si pas de vidéo). Observable.
    private(set) var currentURL: URL?

    init() {
        self.player = AVPlayer()
        // Geler sur la dernière frame plutôt que rembobiner — comportement
        // attendu par un score défilant qui se termine sur une cadence.
        self.player.actionAtItemEnd = .pause
        // Couper le son de la vidéo : le backtrack vient de l'AudioEngine.
        self.player.isMuted = true
    }

    /// Charge un nouveau fichier (ou décharge si url == nil). No-op si l'URL
    /// est déjà active. Repositionne automatiquement à 0 sur changement.
    func load(url: URL?) {
        if currentURL == url { return }
        currentURL = url
        if let url {
            let item = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: item)
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            player.replaceCurrentItem(with: nil)
        }
    }

    /// Lance la lecture vidéo. No-op s'il n'y a pas d'item chargé — protège
    /// les morceaux sans vidéo associée.
    func play() {
        guard player.currentItem != nil else { return }
        player.play()
    }

    func pause() {
        guard player.currentItem != nil else { return }
        player.pause()
    }

    /// Stop ≡ pause + retour à 0. Symétrique au `audioEngine.stop()` côté
    /// audio (qui ramène la position à effectiveStart).
    func stop() {
        guard player.currentItem != nil else { return }
        player.pause()
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Repositionnement absolu dans la vidéo (clamp à >= 0).
    func seek(toSeconds seconds: Double) {
        guard player.currentItem != nil else { return }
        let t = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
