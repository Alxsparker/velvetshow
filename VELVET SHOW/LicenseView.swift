//
//  LicenseView.swift
//  VELVET SHOW
//
//  Shown in two contexts:
//   • Trial-expired full-screen (mode = .expired) — the historical UX.
//   • Trial-active sheet (mode = .trial(daysRemaining:)) — lets the user buy
//     or activate immediately, without waiting for the 30-day timer to expire.
//
//  The activation flow (Buy button + key entry + LemonSqueezy validation) is
//  shared verbatim between the two modes — only the header copy and the
//  bottom-bar buttons change.
//

import SwiftUI

struct LicenseView: View {

    enum Mode: Equatable {
        case expired
        case trial(daysRemaining: Int)
    }

    let mode: Mode
    let onDismiss: (() -> Void)?

    @Environment(LicenseManager.self) private var license

    /// Default initializer keeps backward compatibility for any caller that
    /// constructed `LicenseView()` without arguments (none today, but safe).
    init(mode: Mode = .expired, onDismiss: (() -> Void)? = nil) {
        self.mode = mode
        self.onDismiss = onDismiss
    }

    var body: some View {
        @Bindable var license = license

        VStack(spacing: 0) {

            // Header — copy adapts to mode, layout identical.
            VStack(spacing: 16) {
                Image(systemName: "music.note.house")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                    .padding(.top, 48)

                Text("Velvet Show")
                    .font(.system(size: 32, weight: .bold, design: .default))

                switch mode {
                case .expired:
                    Text("Your 30-day trial has ended.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                case .trial(let days):
                    let unit = days == 1 ? "day" : "days"
                    Text("Trial · \(days) \(unit) remaining")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Continue evaluating Velvet Show or unlock it now.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
            }
            .padding(.bottom, 32)

            Divider()

            // License input — identical in both modes.
            VStack(alignment: .leading, spacing: 16) {

                Text("Enter your license key")
                    .font(.headline)

                HStack(spacing: 10) {
                    TextField("XXXX-XXXX-XXXX-XXXX", text: $license.inputKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .disabled(license.state == .validating)

                    Button("Activate") {
                        Task { await license.activate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(license.inputKey.isEmpty || license.state == .validating)
                    .keyboardShortcut(.defaultAction)
                }

                // Feedback
                switch license.state {
                case .validating:
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        Text("Validating…").foregroundStyle(.secondary)
                    }
                case .error(let msg):
                    Label(msg, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                case .activated:
                    Label("License activated — thank you!", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                default:
                    EmptyView()
                }

            }
            .padding(32)

            Divider()

            // Bottom bar — purchase + secondary action.
            VStack(spacing: 12) {
                Text("Don't have a license yet?")
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button("Buy on velvetshow.app — $79") {
                        NSWorkspace.shared.open(URL(string: "https://velvetshow.lemonsqueezy.com/checkout/buy/9d35d3c7-eaaf-463d-9d60-d191452e75b1")!)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    switch mode {
                    case .expired:
                        Button("Quit") {
                            NSApplication.shared.terminate(nil)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .keyboardShortcut("q", modifiers: .command)
                    case .trial:
                        Button("Continue Trial") {
                            onDismiss?()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .keyboardShortcut(.cancelAction)
                    }
                }
            }
            .padding(32)
        }
        .frame(width: 520)
        .fixedSize()
    }
}
