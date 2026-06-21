//
//  VELVET_SHOWApp.swift
//  VELVET SHOW
//
//  Created by Alexandre CHALON on 06/06/2026.
//

import SwiftUI
import AppKit

@main
struct VELVET_SHOWApp: App {

    // L'état global vit au niveau de l'app for pouvoir être partagé
    // entre la fenêtre principale (édition / contrôle) et le Prompter
    // (affichage scène).
    @State private var appState       = AppState()
    @State private var tourState      = GuideTourState()
    @State private var showOnboarding = false
    @State private var betaManager    = BetaManager()
    @State private var licenseManager = LicenseManager()

    var body: some Scene {

        // ── Window principale ────────────────────────────────────────────
        // WindowGroup (multi-instance autorisé par macOS) : on garde ce
        // comportement standard for que le Dock + ⌘N fonctionnent.
        WindowGroup {
            if betaManager.isExpired && !licenseManager.isActivated {
                BetaExpiredView()
                    .environment(licenseManager)
            } else {
            ContentView()
                .environment(appState)
                .environment(tourState)
                .overlayPreferenceValue(TourAnchorsKey.self) { anchors in
                    GuideTourOverlay(tourState: tourState, appState: appState, anchors: anchors)
                }
                .preferredColorScheme(appState.appTheme.colorScheme)
                .tint(VSColor.interactive)
                .onAppear {
                    ConcertKeyboardShortcuts.install(appState: appState)
                    if appState.isFirstLaunch {
                        // Léger délai for laisser la fenêtre principale s'afficher
                        // complètement avant d'ouvrir la sheet.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            showOnboarding = true
                        }
                    }
                }
                .sheet(isPresented: $showOnboarding) {
                    FirstLaunchOnboardingSheet(
                        appState:       appState,
                        tourState:      tourState,
                        isPresented:    $showOnboarding
                    )
                }
            } // end beta check
        }
        .defaultSize(width: 1400, height: 860)
        .windowResizability(.contentMinSize)
        .commands { TourCommands(tourState: tourState) }

        // ── Settings (instance unique, déplaçable, scrollable) ──────────────
        Window("Settings", id: "midiSettings") {
            MidiSettingsView(appState: appState)
                .preferredColorScheme(appState.appTheme.colorScheme)
                .tint(VSColor.interactive)
        }
        .defaultSize(width: 440, height: 680)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)

        // ── Window Prompter (instance unique) ───────────────────────────
        // `Window` (et non `WindowGroup`) garantit une seule instance :
        //   · openWindow(id:) ramène la fenêtre existante au premier plan,
        //     elle n'en crée pas une seconde.
        //   · Pas d'entrée "Nouvelle fenêtre Prompter" dans le menu Fichier.
        // Le Prompter a sa propre palette, indépendante du thème principal.
        Window("Prompter", id: PrompterView.windowID) {
            PrompterView()
                .environment(appState)
                .preferredColorScheme(appState.prompterTheme.colorScheme)
                .onAppear {
                    ConcertKeyboardShortcuts.install(appState: appState)
                }
        }
        .defaultSize(width: 1280, height: 720)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)

        // ── Queue flottante (instance unique) ────────────────────────────
        // `Window` : même raison que le Prompter.
        // Position par défaut : coin supérieur droit — pratique en concert
        // for rester at côté de la setlist sans la couvrir.
        // Le style `.hiddenTitleBar` supprime la barre de titre pour
        // économiser l'espace dans cette petite fenêtre (280 × 320).
        // La fenêtre reste déplaçable grâce au `.windowDraggingEnabled`
        // mis en place dans QueueFloatingWindowController.configure().
        Window("Floating Queue", id: QueueFloatingView.windowID) {
            QueueFloatingView()
                .environment(appState)
                .preferredColorScheme(appState.appTheme.colorScheme)
                .tint(VSColor.interactive)
                .onAppear {
                    ConcertKeyboardShortcuts.install(appState: appState)
                }
        }
        .defaultSize(width: 300, height: 340)
        .defaultPosition(.topTrailing)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
    }
}

@MainActor
private enum ConcertKeyboardShortcuts {
    private static var monitor: Any?

    static func install(appState: AppState) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !isEditingText(event: event) else { return event }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let commandOnly = flags == .command
            let commandShift = flags == [.command, .shift]
            let noEdits = flags.isEmpty

            switch (event.keyCode, noEdits, commandOnly, commandShift) {
            case (49, true, _, _): // Space
                appState.handlePlayPauseShortcut()
                return nil
            case (124, _, true, _): // Command + Right Arrow
                appState.handleNextSongShortcut()
                return nil
            case (123, _, true, _): // Command + Left Arrow
                appState.handlePreviousSongShortcut()
                return nil
            case (47, _, true, _): // Command + Period
                appState.handleStopShortcut()
                return nil
            case (35, _, _, true): // Command + Shift + P
                appState.triggerPrompterPanic()
                return nil
            case (1, true, _, _): // S (sans modifier) → toggle sidebar Shows
                appState.toggleShowsSidebar()
                return nil
            case (17, true, _, _): // T (sans modifier)
                // Show Library → toggle Quick Library
                // Track Library → toggle colonnes (focus éditeur)
                if appState.mode == .showLibrary {
                    appState.toggleQuickLibrary()
                } else {
                    appState.toggleTrackLibraryColumns()
                }
                return nil
            default:
                return event
            }
        }
    }

    private static func isEditingText(event: NSEvent) -> Bool {
        guard let responder = event.window?.firstResponder else { return false }
        if responder is NSTextView { return true }
        if responder is NSTextField { return true }
        return false
    }
}

// MARK: - Onboarding premier lancement

private struct FirstLaunchOnboardingSheet: View {
    let appState:    AppState
    let tourState:   GuideTourState
    @Binding var isPresented: Bool

    private let features = [
        "Stage Notes & Lyrics",
        "Automatic MIDI Events",
        "PANIC Safety Screen",
        "Stage Display Support",
        "Smooth Song Transitions",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── En-tête ──────────────────────────────────────────────────
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Velvet Show")
                        .font(.title2.bold())
                    Text("Your live performance companion")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 20)

            Text("Would you like to explore Velvet Show with a guided demo?")
                .font(.body)
                .padding(.bottom, 16)

            // ── Feature list ─────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                Text("The demo includes:")
                    .font(.subheadline.weight(.medium))
                    .padding(.bottom, 2)
                ForEach(features, id: \.self) { feature in
                    Label(feature, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.primary)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.accentColor, .primary)
                        .font(.callout)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 14)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            .padding(.bottom, 24)

            // ── Boutons ──────────────────────────────────────────────────
            HStack(spacing: 10) {
                Button("Skip for now") {
                    skip()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Spacer()

                Button {
                    startTour()
                } label: {
                    Label("Start Guided Tour", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(28)
        .frame(width: 420)
    }

    private func skip() {
        appState.markFirstLaunchHandled()
        isPresented = false
    }

    private func startTour() {
        // Installe la démo si elle n'est pas encore présente.
        if appState.demoManifest == nil {
            try? appState.installDemoContent()
        }
        // Bascule en Show Library et sélectionne le show démo.
        appState.mode = .showLibrary
        if let demoShow = appState.sets.first(where: { DemoIDRange.shows.contains($0.id) }) {
            appState.selectedSetID = demoShow.id
        }
        // Lance le guide.
        tourState.start()
        appState.markFirstLaunchHandled()
        isPresented = false
    }
}

// MARK: - Commandes menu Aide

struct TourCommands: Commands {
    var tourState: GuideTourState

    var body: some Commands {
        CommandGroup(after: .help) {
            Divider()
            Button("Start Guided Tour") {
                tourState.start()
            }
        }
    }
}
