//
//  RemoteDiscoveryView.swift
//  Velvet Remote
//
//  Écran de découverte Bonjour — liste les instances VELVET SHOW
//  disponibles sur le réseau local et permet de se connecter.
//

import SwiftUI
import Network
import UIKit

struct RemoteDiscoveryView: View {
    @Environment(VelvetRemoteClient.self) private var client
    @State private var didTimeoutDiscovery = false
    @State private var discoveryTimeoutTask: Task<Void, Never>?

    private let discoveryTimeoutSeconds: UInt64 = 7

    var body: some View {
        Group {
            if case .connected = client.status {
                if UIDevice.current.userInterfaceIdiom == .phone {
                    RemoteControlView()
                        .environment(client)
                } else {
                    RemotePrompterView()
                        .environment(client)
                }
            } else {
                discoveryList
            }
        }
        .onAppear { startDiscoveryAttempt(restartBrowser: false) }
        .onDisappear {
            discoveryTimeoutTask?.cancel()
            client.stopBrowsing()
        }
        .onChange(of: client.discoveredServices.isEmpty) { _, isEmpty in
            if !isEmpty {
                didTimeoutDiscovery = false
                discoveryTimeoutTask?.cancel()
            }
        }
    }

    // MARK: - Discovery list

    private var discoveryList: some View {
        NavigationView {
            Group {
                if shouldShowNotFoundState {
                    notFoundView
                } else {
                    List {
                        statusSection
                        if !client.discoveredServices.isEmpty {
                            servicesSection
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Velvet Remote")
        }
    }

    private var shouldShowNotFoundState: Bool {
        guard client.discoveredServices.isEmpty else { return false }

        if didTimeoutDiscovery {
            return true
        }

        if case .failed = client.status {
            return true
        }

        return false
    }

    @ViewBuilder
    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                statusIndicator
                Text(statusLabel)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var statusIndicator: some View {
        Group {
            switch client.status {
            case .browsing:
                ProgressView().scaleEffect(0.8)
            case .connecting:
                ProgressView().scaleEffect(0.8)
            case .failed:
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            default:
                Image(systemName: "wifi")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusLabel: String {
        switch client.status {
        case .idle:            return String(localized: "remote.searching",   bundle: .main)
        case .browsing:        return String(localized: "remote.searching",   bundle: .main)
        case .connecting:      return String(localized: "remote.searching",   bundle: .main)
        case .connected:
            return client.transport.connectedLabel
        case .failed(let msg): return "Error: \(msg)"
        }
    }

    @ViewBuilder
    private var servicesSection: some View {
        Section("Available") {
            ForEach(client.discoveredServices, id: \.hashValue) { result in
                Button {
                    client.connect(to: result)
                } label: {
                    HStack {
                        Image(systemName: "desktopcomputer")
                            .foregroundStyle(.blue)
                        Text(displayName(for: result))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
                .foregroundStyle(.primary)
            }
        }
    }

    private var notFoundView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(.secondary)

                Text(String(localized: "remote.notFound.title", bundle: .main))
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 8) {
                    Label(String(localized: "remote.notFound.mac", bundle: .main), systemImage: "desktopcomputer")
                    Label(String(localized: "remote.notFound.network", bundle: .main), systemImage: "network")
                    Label(String(localized: "remote.notFound.permission", bundle: .main), systemImage: "lock.shield")
                }
                .font(.body)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .padding(.top, 8)
            }
            .frame(maxWidth: 360)

            Button {
                startDiscoveryAttempt(restartBrowser: true)
            } label: {
                Label(String(localized: "remote.retry", bundle: .main), systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: 280)

            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func startDiscoveryAttempt(restartBrowser: Bool) {
        didTimeoutDiscovery = false
        discoveryTimeoutTask?.cancel()

        if restartBrowser {
            client.restartBrowsing()
        } else {
            client.startBrowsing()
        }

        discoveryTimeoutTask = Task {
            try? await Task.sleep(for: .seconds(discoveryTimeoutSeconds))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if client.discoveredServices.isEmpty, client.status != .connected {
                    didTimeoutDiscovery = true
                }
            }
        }
    }

    private func displayName(for result: NWBrowser.Result) -> String {
        switch result.endpoint {
        case .service(let name, _, _, _): return name
        default: return result.endpoint.debugDescription
        }
    }
}
