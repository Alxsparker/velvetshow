//
//  LicenseView.swift
//  VELVET SHOW
//
//  Shown when the 30-day trial expires. Lets the user enter a license key
//  or visit velvetshow.app to purchase.
//

import SwiftUI

struct LicenseView: View {

    @Environment(LicenseManager.self) private var license

    var body: some View {
        @Bindable var license = license

        VStack(spacing: 0) {

            // Header
            VStack(spacing: 16) {
                Image(systemName: "music.note.house")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                    .padding(.top, 48)

                Text("Velvet Show")
                    .font(.system(size: 32, weight: .bold, design: .default))

                Text("Your 30-day trial has ended.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 32)

            Divider()

            // License input
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

            // Purchase CTA
            VStack(spacing: 12) {
                Text("Don't have a license yet?")
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button("Buy on velvetshow.app — $79") {
                        NSWorkspace.shared.open(URL(string: "https://velvetshow.lemonsqueezy.com/checkout/buy/9d35d3c7-eaaf-463d-9d60-d191452e75b1")!)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .keyboardShortcut("q", modifiers: .command)
                }
            }
            .padding(32)
        }
        .frame(width: 520)
        .fixedSize()
    }
}
