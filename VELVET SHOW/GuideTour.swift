//
//  GuideTour.swift
//  VELVET SHOW
//
//  Guide interactif "Jouer son premier concert".
//  Philosophy : coach actif — le bouton Suivant se débloque quand l'action est détectée.
//

import Foundation
import SwiftUI

// MARK: - Ancres de surbrillance

enum TourAnchor: String {
    // Phase 2 — actives
    case sidebarModeSwitcher
    case playPauseButton
    case settingsButton
    // Phase 3+ — actives
    case demoShowRow      // highlight de la ligne "Velvet Demo Show" dans le sidebar
    // Phase 3+ — at brancher
    case trackList
    case timeline
    case memoList
    case midiCueTimeline
    case contextMenu
    case showLibrarySidebar
    case showQueue
    case midiLibrary
    case restCue
    case importSection
}

// MARK: - PreferenceKey

struct TourAnchorsKey: PreferenceKey {
    typealias Value = [TourAnchor: Anchor<CGRect>]
    static var defaultValue: Value = [:]
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Conditions de validation automatique

enum TourStepCondition: Equatable {
    /// La démo est installée (manifest présent).
    case demoInstalled
    /// Un show démo est sélectionné dans la sidebar Show Library.
    case demoConcertSelected
    /// Un song démo est chargé dans l'engine.
    case demoTrackLoaded
    /// L'engine est en lecture.
    case audioPlaying
    /// L'engine est arrêté.
    case audioStopped
    /// L'écran PANIC a été déclenché au moins une fois.
    case panicTriggered
    /// Un cue MIDI a été envoyé pendant le tour (évalué via GuideTourState.midiCueSentDuringTour).
    case midiCueSent

    @MainActor
    func evaluate(_ appState: AppState) -> Bool {
        switch self {
        case .demoInstalled:
            return appState.demoManifest != nil

        case .demoConcertSelected:
            guard let setID = appState.selectedSetID else { return false }
            return DemoIDRange.shows.contains(setID)

        case .demoTrackLoaded:
            guard let track = appState.currentlyLoadedTrack else { return false }
            return DemoIDRange.tracks.contains(track.audioFileID)

        case .audioPlaying:
            return appState.audioEngine.state == .playing

        case .audioStopped:
            // Space bar → .paused ; ⌘. / Stop button → .stopped.
            // Both mean "no longer playing" for the guide purpose.
            let s = appState.audioEngine.state
            return s == .stopped || s == .paused

        case .panicTriggered:
            return appState.isPanicPrompterVisible

        case .midiCueSent:
            // Évalué dans l'overlay via GuideTourState.midiCueSentDuringTour.
            // Cette branche n'est jamais appelée directement depuis evaluate().
            return false
        }
    }
}

// MARK: - Étape du guide

struct GuideTourStep: Identifiable {
    let id: Int
    let title: String
    let body: String
    /// Ancre de surbrillance (nil = bulle centrale sans surbrillance).
    let anchor: TourAnchor?
    /// Aide contextuelle quand l'ancre est hors-écran.
    let anchorHint: String?
    /// Mode requis for que l'ancre soit visible.
    let requiresMode: LibraryMode?
    /// Condition de validation. nil = Suivant toujours actif.
    let condition: TourStepCondition?
    /// Aide affichée quand la condition n'est pas encore remplie.
    let conditionHint: String?
    /// Libellé du bouton Suivant. nil = "Suivant →".
    let nextButtonLabel: String?
    /// Si true, avance automatiquement 1,5 s après que la condition devient vraie.
    let autoAdvance: Bool

    init(
        id: Int,
        title: String,
        body: String,
        anchor: TourAnchor? = nil,
        anchorHint: String? = nil,
        requiresMode: LibraryMode? = nil,
        condition: TourStepCondition? = nil,
        conditionHint: String? = nil,
        nextButtonLabel: String? = nil,
        autoAdvance: Bool = false
    ) {
        self.id              = id
        self.title           = title
        self.body            = body
        self.anchor          = anchor
        self.anchorHint      = anchorHint
        self.requiresMode    = requiresMode
        self.condition       = condition
        self.conditionHint   = conditionHint
        self.nextButtonLabel = nextButtonLabel
        self.autoAdvance     = autoAdvance
    }
}

// MARK: - Contenu du guide

// 12 steps — "Play Your First Show" walkthrough (pedagogical order, ids 0–11).
// To add future steps: insert here, validators chain automatically.
let guideTourSteps: [GuideTourStep] = [

    // ── 0. Welcome ────────────────────────────────────────────────────────
    GuideTourStep(
        id: 0,
        title: "Welcome to Velvet Show",
        body: "You're about to run your first mini show with Velvet Show.\n\nIn a few steps, you'll discover how to control your songs, stage notes, and lighting cues — exactly like on a real gig.",
        condition: .demoInstalled,
        conditionHint: "This guide uses the demo project. Install it in Settings › Demo / Get Started, then come back here."
    ),

    // ── 1. Open the show ──────────────────────────────────────────────────
    GuideTourStep(
        id: 1,
        title: "Open Your Show",
        body: "Switch to Shows mode, then click \"Velvet Demo Show\" in the sidebar.\n\nIn Velvet Show, every show is an independent setlist — with its own songs, notes, and MIDI cues.",
        anchor: .demoShowRow,
        anchorHint: "Switch to Shows mode first — the sidebar will show your demo show.",
        condition: .demoConcertSelected,
        conditionHint: "Select \"Velvet Demo Show\" from the shows list to continue."
    ),

    // ── 2. Stage screen ───────────────────────────────────────────────────
    // Adaptive status line based on appState.isSecondDisplayConnected — handled in GuideTourOverlay.
    // Always informational — no blocking condition.
    GuideTourStep(
        id: 2,
        title: "Stage Screen",
        body: "ipad_adaptive"   // sentinel: replaced dynamically in the overlay
    ),

    // ── 3. Full Screen ────────────────────────────────────────────────────
    // Placed after Stage Screen so users first understand what they'll see.
    GuideTourStep(
        id: 3,
        title: "Full Screen Recommended",
        body: "For the best experience, switch Velvet Show to Full Screen.\n\nThe demo uses a stage display, MIDI cues, PANIC mode, and live notes — everything is easier to see in Full Screen."
    ),

    // ── 4. PANIC ──────────────────────────────────────────────────────────
    GuideTourStep(
        id: 4,
        title: "Safety Net — PANIC",
        body: "If something goes wrong on stage, PANIC instantly switches the stage display to an emergency screen. It's your safety net during a live show.\n\nTry it now: press ⌘⇧P.",
        condition: .panicTriggered,
        conditionHint: "Press ⌘⇧P to trigger the emergency screen."
    ),

    // ── 5. Choose a song and start playback ───────────────────────────────
    GuideTourStep(
        id: 5,
        title: "Choose a Song",
        body: "Double-click \"Opening Act\" to start playback immediately.\n\nYou can also load a song first, then press Space.",
        anchor: .playPauseButton,
        anchorHint: "The Play button appears in the header of the open show.",
        requiresMode: .showLibrary,
        condition: .audioPlaying,
        conditionHint: "Double-click a song in the setlist to start playback.",
        autoAdvance: true
    ),

    // ── 6. Live Notes & Lyrics ────────────────────────────────────────────
    GuideTourStep(
        id: 6,
        title: "Live Notes & Lyrics",
        body: "Notes, lyrics, reminders and stage directions can appear automatically during playback. Everything stays synchronized with your music.\n\nExample of what your stage display shows:\n\n🎸  CAPO 2\n🎤  Seve starts first verse\n🎷  Sax solo after chorus",
        nextButtonLabel: "Got it — I see the notes"
    ),

    // ── 7. MIDI Events ────────────────────────────────────────────────────
    // Auto-validation: a MIDI cue is detected via midiCueSentDuringTour in GuideTourState.
    GuideTourStep(
        id: 7,
        title: "Automatic MIDI Events",
        body: "During playback, MIDI events fire automatically at the moments you've defined — triggering lights, video, or any other software.\n\nWait for a cue to fire to continue.",
        condition: .midiCueSent,
        conditionHint: "A MIDI cue will fire automatically during playback."
    ),

    // ── 8. Stop playback ──────────────────────────────────────────────────
    GuideTourStep(
        id: 8,
        title: "Stop Playback",
        body: "Click the Stop button to stop cleanly.\n\nVelvet Show returns to standby — ready for the next song.",
        condition: .audioStopped,
        conditionHint: "Click the Stop button to continue."
    ),

    // ── 9. Auto transitions ───────────────────────────────────────────────
    GuideTourStep(
        id: 9,
        title: "Smooth Transitions",
        body: "Velvet Show can chain songs automatically with configurable crossfades.\n\nPerfect for cocktail hours, lounge sets, or uninterrupted playlists — and you can take back control at any moment.",
        anchor: .settingsButton,
        anchorHint: "Configure auto-play and crossfades in Settings."
    ),

    // ── 10. Rest cue ──────────────────────────────────────────────────────
    GuideTourStep(
        id: 10,
        title: "Ambience Between Songs",
        body: "When you stop playback or a song ends, Velvet Show can automatically send a rest cue to restore a calm lighting scene.\n\nNo more dead blackouts or an overpowering stage between two tracks.",
        anchor: .settingsButton,
        anchorHint: "Configure the rest cue in Settings › Rest Cue."
    ),

    // ── 11. Ready ─────────────────────────────────────────────────────────
    GuideTourStep(
        id: 11,
        title: "You're Ready",
        body: "You have just run your first show with:\n\n• Stage Notes & Lyrics\n• Automatic MIDI Cues\n• PANIC Safety Screen\n• External Stage Display\n• Smooth Song Transitions\n\nWhat's next?\n\n• Import your own songs\n• Create your first real show\n• Add notes and MIDI cues\n• Start building your live set"
    ),
]

// MARK: - État du guide

@MainActor
@Observable
final class GuideTourState {

    private static let completedKey = "guideTourCompleted"

    var isActive: Bool        = false
    var currentStepIndex: Int = 0
    /// Mis at true par GuideTourOverlay dès qu'un cue MIDI est dispatché pendant le tour.
    var midiCueSentDuringTour: Bool = false

    var hasCompletedTour: Bool {
        get { UserDefaults.standard.bool(forKey: Self.completedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.completedKey) }
    }

    let steps: [GuideTourStep] = guideTourSteps

    var currentStep: GuideTourStep? {
        guard steps.indices.contains(currentStepIndex) else { return nil }
        return steps[currentStepIndex]
    }

    var isFirstStep: Bool { currentStepIndex == 0 }
    var isLastStep:  Bool { currentStepIndex == steps.count - 1 }

    func start() {
        currentStepIndex      = 0
        midiCueSentDuringTour = false
        isActive              = true
    }

    func next() {
        if isLastStep { complete() }
        else { currentStepIndex += 1 }
    }

    func previous() {
        guard !isFirstStep else { return }
        currentStepIndex -= 1
    }

    func quit() {
        isActive = false
    }

    func complete() {
        hasCompletedTour = true
        isActive         = false
    }
}
