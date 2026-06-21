//
//  VelvetRemoteClient.swift
//  Velvet Remote
//
//  Découverte Bonjour + connexion TCP au serveur VELVET SHOW.
//  Lecture seule — aucune commande envoyée (Étape 3).
//

import Network
import Foundation

// MARK: - Transport

enum RemoteTransport: Equatable {
    case usb    // wiredEthernet — câble Apple USB/USB-C
    case wifi
    case other
    case disconnected

    var label: String {
        switch self {
        case .usb:          return String(localized: "remote.transport.usb",   bundle: .main)
        case .wifi:         return String(localized: "remote.transport.wifi",  bundle: .main)
        case .other:        return String(localized: "remote.transport.other", bundle: .main)
        case .disconnected: return String(localized: "remote.disconnected",    bundle: .main)
        }
    }

    /// Texte complet de connexion (utilisé dans le badge et la liste de découverte).
    var connectedLabel: String {
        switch self {
        case .wifi:  return String(localized: "remote.connected.wifi", bundle: .main)
        case .usb:   return String(localized: "remote.connected.usb",  bundle: .main)
        default:     return label
        }
    }

}

// MARK: - Client

@Observable @MainActor
final class VelvetRemoteClient {

    // MARK: - Public state

    enum ConnectionStatus: Equatable {
        case idle, browsing, connecting, connected, failed(String)
    }

    var status: ConnectionStatus = .idle
    var transport: RemoteTransport = .disconnected
    var latestState: RemoteStateUpdate?
    var discoveredServices: [NWBrowser.Result] = []

    // MARK: - Private

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var receiveBuffer = Data()

    // Network.framework exige une queue série dédiée — pas .global() (concurrente),
    // qui peut entrelacer les callbacks et corrompre l'état interne de libdispatch
    // (crash "-[OS_dispatch_mach_msg _setContext:]: unrecognized selector").
    private let networkQueue = DispatchQueue(label: "com.velvetshow.remote.network")

    // Watchdog connexion
    private static let staleThreshold: TimeInterval = 8
    private static let watchdogInterval: TimeInterval = 4
    private var lastDataReceived: Date = .distantPast
    private var watchdogTimer: Timer?

    // Watchdog browser : relance NWBrowser si aucun service trouvé après N secondes
    private static let browserRestartDelay: TimeInterval = 10
    private var browserStartedAt: Date = .distantPast
    private var browserRestartTimer: Timer?

    // Auto-reconnect : persistant entre tentatives, effacé par disconnect() explicite uniquement.
    private var lastConnectedServiceName: String?

    // MARK: - Discovery

    func startBrowsing() {
        guard browser == nil else { return }
        status = .browsing

        let params = NWParameters.tcp
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_velvetshow._tcp", domain: nil)
        let b = NWBrowser(for: descriptor, using: params)

        b.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch newState {
                case .ready:
                    print("[VelvetRemote] Browser started — scanning for _velvetshow._tcp")
                case .failed(let error):
                    print("[VelvetRemote] Browser failed: \(error)")
                    self.status = .failed(error.localizedDescription)
                case .cancelled:
                    print("[VelvetRemote] Browser cancelled")
                case .waiting(let error):
                    print("[VelvetRemote] Browser waiting — permission denied? \(error)")
                    if case .posix(let code) = error, code.rawValue == 65 {
                        self.status = .failed("Local network permission denied. Allow in Settings > Privacy.")
                    }
                default: break
                }
            }
        }

        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.discoveredServices = Array(results)
                print("[VelvetRemote] Services found: \(results.count)")
                self.attemptAutoReconnect(from: results)
            }
        }

        b.start(queue: networkQueue)
        browser = b
        browserStartedAt = Date()
        startBrowserRestartTimer()
        print("[VelvetRemote] Browser starting…")
    }

    func restartBrowsing() {
        stopBrowsing()
        startBrowsing()
    }

    func stopBrowsing() {
        browserRestartTimer?.invalidate()
        browserRestartTimer = nil
        browser?.cancel()
        browser = nil
        discoveredServices = []
        if case .browsing = status { status = .idle }
    }

    // MARK: - Browser watchdog

    private func startBrowserRestartTimer() {
        browserRestartTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: Self.browserRestartDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkBrowserWatchdog() }
        }
        RunLoop.main.add(t, forMode: .common)
        browserRestartTimer = t
    }

    private func checkBrowserWatchdog() {
        guard discoveredServices.isEmpty, browser != nil else { return }
        let age = Date().timeIntervalSince(browserStartedAt)
        print("[VelvetRemote] Browser watchdog: no service found after \(Int(age))s — restarting browser…")
        browser?.cancel()
        browser = nil
        startBrowsing()
    }

    // MARK: - Auto-reconnect

    private func attemptAutoReconnect(from results: Set<NWBrowser.Result>) {
        guard let target = lastConnectedServiceName else { return }

        guard let match = results.first(where: { Self.serviceName(from: $0) == target }) else {
            print("[VelvetRemote] Auto-reconnect skipped — '\(target)' not found yet (\(results.count) service(s))")
            return
        }

        guard case .browsing = status else { return }   // ne pas écraser une connexion active

        print("[VelvetRemote] Auto-reconnect eligible — connecting to '\(target)'…")
        connectInternal(to: match)
    }

    // MARK: - Connection (public)

    func connect(to result: NWBrowser.Result) {
        // Mémoriser le serveur choisi par l'utilisateur pour les reconnexions futures.
        lastConnectedServiceName = Self.serviceName(from: result)
        connectInternal(to: result)
    }

    // MARK: - Commands

    func sendCommand(_ type: String) {
        guard let connection, case .connected = status else { return }
        let cmd = RemoteCommand(type: type)
        guard let data = try? JSONEncoder().encode(cmd),
              let payload = (String(data: data, encoding: .utf8).map { $0 + "\n" })?.data(using: .utf8)
        else { return }
        connection.send(content: payload, completion: .idempotent)
        print("[VelvetRemote] Command sent: \(type)")
    }

    /// Déconnexion complète — désactive l'auto-reconnect.
    /// Non exposé dans l'UI : Velvet Remote est un écran passif qui se (re)connecte seul.
    func disconnectAndReset() {
        print("[VelvetRemote] Full reset — auto-reconnect disabled")
        lastConnectedServiceName = nil
        disconnectInternal()
        stopBrowsing()
        status = .idle
    }

    // MARK: - Connection (internal)

    private func connectInternal(to result: NWBrowser.Result) {
        disconnectInternal()
        status = .connecting

        let conn = NWConnection(to: result.endpoint, using: .tcp)
        connection = conn

        print("[VelvetRemote] Connecting to \(Self.endpointDescription(result.endpoint))…")

        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    let t = Self.detectTransport(from: conn.currentPath)
                    let pathDesc = Self.pathDescription(conn.currentPath)
                    print("[VelvetRemote] Connected — transport: \(t.label) | path: \(pathDesc)")
                    self.applyTransport(t)
                    self.status = .connected
                    self.lastDataReceived = Date()
                    self.startWatchdog()
                    self.receiveNextMessage()
                case .failed(let error):
                    print("[VelvetRemote] Connection failed: \(error)")
                    self.handleConnectionLost()
                case .cancelled:
                    // Annulé via disconnectInternal() — pas de reconnexion ici.
                    print("[VelvetRemote] Connection cancelled")
                case .waiting(let error):
                    print("[VelvetRemote] Connection waiting: \(error)")
                default: break
                }
            }
        }

        // Notifié quand le path change (USB → Wi-Fi ou inverse).
        conn.viabilityUpdateHandler = { [weak self] isViable in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let t = Self.detectTransport(from: conn.currentPath)
                let pathDesc = Self.pathDescription(conn.currentPath)
                print("[VelvetRemote] Path viability: \(isViable) — transport: \(t.label) | \(pathDesc)")
                if t != self.transport { self.applyTransport(t) }
            }
        }

        conn.betterPathUpdateHandler = { [weak self] hasBetter in
            guard hasBetter else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let t = Self.detectTransport(from: conn.currentPath)
                print("[VelvetRemote] Better path available — transport: \(t.label)")
                if t != self.transport { self.applyTransport(t) }
            }
        }

        conn.start(queue: networkQueue)
    }

    private func applyTransport(_ t: RemoteTransport) {
        guard t != transport else { return }
        print("[VelvetRemote] Transport changed: \(t.label)")
        transport = t
    }

    // MARK: - Internal disconnect (sans toucher lastConnectedServiceName)

    private func disconnectInternal() {
        stopWatchdog()
        connection?.cancel()
        connection = nil
        receiveBuffer = Data()
        transport = .disconnected
        // latestState conservé intentionnellement (pas de flash "waiting" inutile)
    }

    // MARK: - Stale / lost connection

    private func handleConnectionLost() {
        let target = lastConnectedServiceName
        print("[VelvetRemote] Connection lost — will auto-reconnect: \(target != nil)")
        disconnectInternal()
        if target != nil {
            status = .browsing
            stopBrowsing()
            startBrowsing()
        } else {
            status = .idle
        }
    }

    // MARK: - Watchdog

    private func startWatchdog() {
        stopWatchdog()
        let t = Timer.scheduledTimer(withTimeInterval: Self.watchdogInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkWatchdog() }
        }
        RunLoop.main.add(t, forMode: .common)
        watchdogTimer = t
    }

    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }

    private func checkWatchdog() {
        let age = Date().timeIntervalSince(lastDataReceived)
        guard age > Self.staleThreshold else { return }
        print("[VelvetRemote] Watchdog: stale — lastDataAge=\(Int(age))s — reconnecting…")
        handleConnectionLost()
    }

    // MARK: - Transport detection

    private static func detectTransport(from path: NWPath?) -> RemoteTransport {
        guard let path else { return .other }
        if path.usesInterfaceType(.wiredEthernet) { return .usb }
        if path.usesInterfaceType(.wifi)          { return .wifi }
        return .other
    }

    private static func pathDescription(_ path: NWPath?) -> String {
        guard let path else { return "nil" }
        let ifaces = path.availableInterfaces.map { "\($0.name)(\($0.type))" }.joined(separator: ", ")
        return "status=\(path.status) interfaces=[\(ifaces)]"
    }

    private static func endpointDescription(_ ep: NWEndpoint) -> String {
        switch ep {
        case .service(let name, let type, let domain, _): return "\(name).\(type)\(domain)"
        case .hostPort(let host, let port):               return "\(host):\(port)"
        default:                                          return ep.debugDescription
        }
    }

    private static func serviceName(from result: NWBrowser.Result) -> String? {
        if case .service(let name, _, _, _) = result.endpoint { return name }
        return nil
    }

    // MARK: - Receive loop

    private func receiveNextMessage() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let data, !data.isEmpty {
                    self.lastDataReceived = Date()
                    self.receiveBuffer.append(data)
                    self.processBuffer()
                }

                if isComplete || error != nil {
                    print("[VelvetRemote] Receive ended — isComplete=\(isComplete) error=\(String(describing: error))")
                    self.handleConnectionLost()
                } else {
                    self.receiveNextMessage()
                }
            }
        }
    }

    private func processBuffer() {
        while let newline = receiveBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = receiveBuffer[receiveBuffer.startIndex...newline]
            receiveBuffer = receiveBuffer[receiveBuffer.index(after: newline)...]
            if let json = try? JSONDecoder().decode(RemoteStateUpdate.self, from: lineData) {
                latestState = json
            }
            // ping : déjà compté via lastDataReceived
        }
    }
}
