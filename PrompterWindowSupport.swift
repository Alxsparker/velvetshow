//
//  PrompterWindowSupport.swift
//  VELVET SHOW
//
//  Pont AppKit minimal for le mode PANIC Prompter et la Queue flottante.
//  SwiftUI affiche le contenu ; AppKit sert uniquement at retrouver les
//  fenêtres existantes, les configurer une seule fois et les piloter
//  (niveau, position, plein écran).
//

import SwiftUI
import AppKit

// MARK: - Queue flottante

@MainActor
enum QueueFloatingWindowController {
    private static let windowIdentifier = NSUserInterfaceItemIdentifier(QueueFloatingView.windowID)
    private static var shouldReopenWhenFilled = false

    static var queueWindow: NSWindow? {
        NSApp.windows.first { window in
            window.identifier == windowIdentifier || window.title == "Floating Queue"
        }
    }

    static var shouldAutoReopen: Bool { shouldReopenWhenFilled }

    /// Configure la fenêtre une seule fois après son apparition.
    /// Appelé depuis `QueueWindowAccessor.makeNSView` uniquement —
    /// pas depuis `updateNSView` for éviter les reconfiguration en boucle.
    static func configure(_ window: NSWindow) {
        window.title           = "Floating Queue"
        window.identifier      = windowIdentifier
        window.level           = .floating
        window.isMovableByWindowBackground = true   // drag depuis n'importe où
        window.titlebarAppearsTransparent  = true
        window.backgroundColor = .clear
        window.isOpaque        = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        shouldReopenWhenFilled = false
    }

    static func hideBecauseQueueIsEmpty() {
        guard let window = queueWindow,
              window.isVisible,
              !window.isMiniaturized else { return }
        shouldReopenWhenFilled = true
        window.orderOut(nil)
    }

    static func markAutoReopenHandled() {
        shouldReopenWhenFilled = false
    }
}

// MARK: - Prompter

@MainActor
enum PrompterWindowController {
    private static let windowIdentifier = NSUserInterfaceItemIdentifier(PrompterView.windowID)

    static var prompterWindow: NSWindow? {
        NSApp.windows.first { window in
            window.identifier == windowIdentifier || window.title == "Prompter"
        }
    }

    static var isPrompterVisible: Bool {
        guard let window = prompterWindow else { return false }
        return window.isVisible && !window.isMiniaturized
    }

    /// Configure la fenêtre une seule fois après son apparition.
    static func configure(_ window: NSWindow) {
        window.title      = "Prompter"
        window.identifier = windowIdentifier
        window.collectionBehavior = [.fullScreenPrimary, .canJoinAllSpaces]
    }

    static func activatePanicWindow() {
        guard let window = prompterWindow else { return }
        showOnPrimaryScreen(window)
    }

    static func activatePanicWindow(openIfNeeded: () -> Void) {
        if let window = prompterWindow {
            showOnPrimaryScreen(window)
            return
        }

        openIfNeeded()

        // `openWindow(id:)` crée/affiche la scène de façon asynchrone.
        // On retente juste après for piloter la fenêtre qui vient d'apparaître.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            activatePanicWindow()
        }
    }

    private static func showOnPrimaryScreen(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                placeAndEnterFullScreen(window)
            }
        } else {
            placeAndEnterFullScreen(window)
        }
    }

    private static func placeAndEnterFullScreen(_ window: NSWindow) {
        let targetScreen = NSScreen.screens.first ?? NSScreen.main
        if let frame = targetScreen?.visibleFrame {
            window.setFrame(frame, display: true, animate: false)
        }

        window.level = .normal
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        if !window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }
}

// MARK: - NSViewRepresentable helpers

/// Donne accès at la NSWindow qui héberge PrompterView.
/// `onResolve` est appelé une seule fois at la création de la vue — pas à
/// chaque mise at jour — for éviter de reconfigurer la fenêtre en boucle.
struct PrompterWindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
        return view
    }

    // Délibérément vide : la configuration de la fenêtre n'a besoin
    // d'être effectuée qu'une seule fois, lors du makeNSView.
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Donne accès at la NSWindow qui héberge QueueFloatingView.
/// Même principe que PrompterWindowAccessor.
struct QueueWindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
        return view
    }

    // Délibérément vide.
    func updateNSView(_ nsView: NSView, context: Context) {}
}
