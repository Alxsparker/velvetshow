//
//  GuideTourOverlay.swift
//  VELVET SHOW
//
//  Overlay plein-écran du guide interactif.
//  Reçoit les ancres collectées via TourAnchorsKey.overlayPreferenceValue.
//

import SwiftUI

// MARK: - Overlay principal

struct GuideTourOverlay: View {
    let tourState: GuideTourState
    let appState: AppState
    var anchors: [TourAnchor: Anchor<CGRect>] = [:]

    /// Dernier nom de cue affiché dans la bannière éphémère.
    @State private var cueBannerText: String? = nil
    @State private var cueBannerVisible: Bool = false
    /// Bannière PANIC — visible dès que PANIC est déclenché sur l'étape PANIC.
    @State private var panicBannerVisible: Bool = false

    var body: some View {
        if tourState.isActive, let step = tourState.currentStep {
            GeometryReader { geo in
                let highlightRect: CGRect? = resolveAnchor(step: step, geo: geo)
                let stepDone: Bool         = evaluateStepDone(step: step)

                ZStack {
                    // ── Couche 0 : fond sombre avec trou spotlight ────────────
                    if let rect = highlightRect {
                        SpotlightDimView(highlightRect: rect)
                    } else {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }

                    // ── Couche 1 : halo de surbrillance ──────────────────────
                    if let rect = highlightRect {
                        GlowHighlightView(rect: rect)
                            .zIndex(10)
                    }

                    // ── Couche 2 : bulle de guide ─────────────────────────────
                    GuideTourBubble(
                        tourState:       tourState,
                        step:            step,
                        appState:        appState,
                        anchorFound:     highlightRect != nil,
                        stepDone:        stepDone,
                        onImportMySongs: { importMySongs() }
                    )
                    .frame(maxWidth: 440)
                    .shadow(color: .black.opacity(0.3), radius: 28, x: 0, y: 12)
                    .zIndex(20)

                    // ── Couche 3 : bannière PANIC spectaculaire ───────────────
                    if step.id == 4 && appState.isPanicPrompterVisible {
                        PanicActiveBanner()
                            .zIndex(25)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.92).combined(with: .opacity),
                                removal:   .opacity
                            ))
                    }

                    // ── Couche 4 : bannière cue MIDI éphémère (bottom) ───────
                    if cueBannerVisible, let text = cueBannerText {
                        CueMidiBanner(text: text)
                            .zIndex(30)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal:   .opacity
                            ))
                    }
                }
            }
            .ignoresSafeArea()
            .transition(.asymmetric(
                insertion: .scale(scale: 0.97).combined(with: .opacity),
                removal:   .opacity
            ))
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: tourState.isActive)
            .animation(.easeInOut(duration: 0.28), value: cueBannerVisible)
            .onAppear {
                logAnchor(step: tourState.currentStep)
                applySidebarVisibility(for: tourState.currentStep)
            }
            .onChange(of: tourState.currentStepIndex) { _, _ in
                logAnchor(step: tourState.currentStep)
                applySidebarVisibility(for: tourState.currentStep)
            }
            // Auto-avance audio + logs diagnostic
            .onChange(of: appState.audioEngine.state) { _, newState in
                if let step = tourState.currentStep, step.condition == .audioStopped {
                    let done = TourStepCondition.audioStopped.evaluate(appState)
                    print("[TOUR] StopPlayback validator — audioEngine.state = \(newState)")
                    print("[TOUR] StopPlayback validator — stepDone = \(done)")
                }
                triggerAutoAdvanceIfNeeded()
            }
            .onChange(of: tourState.currentStepIndex) { _, _ in
                triggerAutoAdvanceIfNeeded()
            }
            // Observation PANIC for recalcul stepDone
            .onChange(of: appState.isPanicPrompterVisible) { _, _ in }
            // Détection cue MIDI
            .onChange(of: appState.midiLog.count) { _, _ in
                handleMidiCue()
            }
        }
    }

    // MARK: - Helpers

    private func resolveAnchor(step: GuideTourStep, geo: GeometryProxy) -> CGRect? {
        guard let tourAnchor = step.anchor,
              let anchor = anchors[tourAnchor] else { return nil }
        let r = geo[anchor].insetBy(dx: -10, dy: -10)
        return CGRect(origin: .zero, size: geo.size).intersects(r) ? r : nil
    }

    private func evaluateStepDone(step: GuideTourStep) -> Bool {
        guard let condition = step.condition else { return true }
        if condition == .midiCueSent { return tourState.midiCueSentDuringTour }
        return condition.evaluate(appState)
    }

    private func triggerAutoAdvanceIfNeeded() {
        guard tourState.isActive,
              let step = tourState.currentStep,
              step.autoAdvance,
              evaluateStepDone(step: step) else { return }

        let targetIndex = tourState.currentStepIndex
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard tourState.isActive,
                  tourState.currentStepIndex == targetIndex,
                  evaluateStepDone(step: tourState.currentStep ?? step) else { return }
            tourState.next()
        }
    }

    private func handleMidiCue() {
        guard tourState.isActive else { return }
        // Rest cues fire after stop — only count/show cues while audio is playing.
        guard appState.audioEngine.state == .playing else { return }
        tourState.midiCueSentDuringTour = true
        let name = appState.lastDispatchedEventName ?? "MIDI Cue"
        showCueBanner(name: name)
    }

    private func showCueBanner(name: String) {
        cueBannerText    = name
        cueBannerVisible = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            cueBannerVisible = false
        }
    }

    /// Gère la visibilité de la sidebar Shows pendant le guide.
    /// Étape "Open Your Show" (id 1) : sidebar ouverte for que l'utilisateur
    /// puisse sélectionner le show. Toutes les étapes suivantes : sidebar fermée
    /// for maximiser l'espace de travail. Guide-only — aucun impact sur le comportement
    /// normal : la sidebar n'est pas restaurée at la sortie du guide.
    private func applySidebarVisibility(for step: GuideTourStep?) {
        guard let step, appState.mode == .showLibrary else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            if step.id == 1 {
                appState.showsSidebarVisibility = .all
            } else if step.id > 1 {
                appState.showsSidebarVisibility = .detailOnly
            }
        }
    }

    /// Termine le guide, bascule en Track Library, ouvre le panneau d'import.
    private func importMySongs() {
        tourState.complete()
        appState.mode = .trackLibrary
        // Small delay so the overlay teardown animates before the panel opens.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            presentVelvetTrackImportPanel(appState: appState)
        }
    }

    private func logAnchor(step: GuideTourStep?) {
        guard let step, let tourAnchor = step.anchor else { return }
        if anchors[tourAnchor] != nil {
            print("[TOUR] anchor found: \(tourAnchor.rawValue)")
        } else {
            print("[TOUR] anchor missing: \(tourAnchor.rawValue)")
        }
    }
}

// MARK: - Bannière PANIC spectaculaire (step 3)

private struct PanicActiveBanner: View {
    @State private var glowing = false

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    Text("🚨")
                        .font(.system(size: 28))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PANIC MODE ENABLED")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(.red)
                        Text("The stage display has switched to the emergency screen.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 22)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.red.opacity(glowing ? 0.85 : 0.35), lineWidth: 2)
                )
                .shadow(color: .red.opacity(glowing ? 0.45 : 0.15), radius: 18, x: 0, y: 0)
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
            }
            .padding(.bottom, 36)
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                glowing = true
            }
        }
    }
}

// MARK: - Bannière cue MIDI éphémère (deux lignes, positionnée en bas)

private struct CueMidiBanner: View {
    let text: String

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 3) {
                HStack(spacing: 6) {
                    Text("💡")
                        .font(.system(size: 13))
                    Text("LIGHTING CUE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(.yellow)
                }
                Text(text)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Works with MaestroDMX, myDMX, Zero 88, Wolfmix and other MIDI-compatible systems.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .opacity(0.75)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.yellow.opacity(0.45), lineWidth: 1.5)
            )
            .shadow(color: .yellow.opacity(0.25), radius: 12, x: 0, y: 0)
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        }
        .padding(.bottom, 44)
        .frame(maxWidth: .infinity, alignment: .center)
        .allowsHitTesting(false)
    }
}

// MARK: - Fond sombre avec trou spotlight

private struct SpotlightDimView: View {
    let highlightRect: CGRect

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color.black.opacity(0.45))
            )
            var cut = context
            cut.blendMode = .destinationOut
            cut.fill(
                RoundedRectangle(cornerRadius: 10).path(in: highlightRect),
                with: .color(Color.white)
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Halo de surbrillance

private struct GlowHighlightView: View {
    let rect: CGRect
    @State private var pulsing = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(pulsing ? 0.18 : 0.38), lineWidth: 8)
                .frame(width: rect.width + 8, height: rect.height + 8)
                .blur(radius: 7)

            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor.opacity(pulsing ? 0.55 : 0.85), lineWidth: 1.5)
                .frame(width: rect.width, height: rect.height)
                .shadow(color: Color.accentColor.opacity(0.5), radius: 6,  x: 0, y: 0)
                .shadow(color: Color.accentColor.opacity(0.2), radius: 14, x: 0, y: 0)
        }
        .position(x: rect.midX, y: rect.midY)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}

// MARK: - Bulle

private struct GuideTourBubble: View {
    let tourState: GuideTourState
    let step: GuideTourStep
    let appState: AppState
    let anchorFound: Bool
    let stepDone: Bool
    var onImportMySongs: (() -> Void)? = nil

    private var showAnchorHint: Bool {
        step.anchor != nil && !anchorFound
    }

    private var showConditionHint: Bool {
        !stepDone && step.conditionHint != nil
    }

    private var nextLabel: String {
        step.nextButtonLabel ?? "Next →"
    }

    /// Body text for the step — replaces the "ipad_adaptive" sentinel if needed.
    private var bodyText: String {
        guard step.body == "ipad_adaptive" else { return step.body }
        let status = appState.isSecondDisplayConnected
            ? "✓  A stage display is currently connected."
            : "No stage display is currently connected."
        return "Velvet Show can send notes and lyrics to a stage screen during your show:\n\n• An iPad using Apple Continuity\n• An external monitor\n• A confidence screen\n\n\(status)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── En-tête ───────────────────────────────────────────────────────
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.tint)
                Text(step.title)
                    .font(.headline)
                Spacer()
                Text("\(tourState.currentStepIndex + 1) / \(tourState.steps.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.bottom, 12)

            Divider()
                .padding(.bottom, 14)

            // ── Corps ─────────────────────────────────────────────────────────
            Text(bodyText)
                .font(.body)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, (showConditionHint || showAnchorHint) ? 10 : 18)

            // ── Aide : condition non remplie ──────────────────────────────────
            if showConditionHint, let hint = step.conditionHint {
                Label(hint, systemImage: "clock.badge.checkmark")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.orange.opacity(0.25), lineWidth: 1)
                    )
                    .padding(.bottom, showAnchorHint ? 8 : 18)
            }

            // ── Aide : ancre hors-écran ───────────────────────────────────────
            if showAnchorHint {
                let hint = step.anchorHint ?? "This element is not visible in the current view."
                Label(hint, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 18)
            }

            // ── Barre de progression ──────────────────────────────────────────
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.secondary.opacity(0.18))
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(
                            width: max(8, geo.size.width
                                * CGFloat(tourState.currentStepIndex + 1)
                                / CGFloat(max(1, tourState.steps.count))),
                            height: 4
                        )
                        .animation(.easeInOut(duration: 0.22), value: tourState.currentStepIndex)
                }
            }
            .frame(height: 4)
            .padding(.bottom, 20)

            // ── Boutons ───────────────────────────────────────────────────────
            HStack(spacing: 8) {
                Button("Exit") { tourState.quit() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.callout)

                Spacer()

                if !tourState.isFirstStep {
                    Button("← Back") { tourState.previous() }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                }

                if tourState.isLastStep {
                    // TODO: future "Open Button & Icon Guide" button here
                    if let importAction = onImportMySongs {
                        Button {
                            importAction()
                        } label: {
                            Label("Import My Songs", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                    Button("Done") { tourState.complete() }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                } else {
                    Button(nextLabel) { tourState.next() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(!stepDone)
                        .keyboardShortcut(.return, modifiers: [])
                }
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .id(step.id)
    }
}
