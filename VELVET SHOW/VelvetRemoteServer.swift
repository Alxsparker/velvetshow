//
//  VelvetRemoteServer.swift
//  VELVET SHOW
//
//  Serveur TCP local pour Velvet Remote.
//  - Port fixe 7777
//  - Publication Bonjour _velvetshow._tcp
//  - Ping JSON toutes les 5 secondes par client connecté
//  - NWPathMonitor : relance automatique du listener si l'interface réseau change
//  - Zéro dépendance externe, Network.framework uniquement
//

import Foundation
import Network

@MainActor
final class VelvetRemoteServer {

    static let port: NWEndpoint.Port = 7777
    static let serviceType = "_velvetshow._tcp"

    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var pingTimers: [UUID: DispatchSourceTimer] = [:]
    private(set) var lastState: RemoteStateUpdate?

    private let queue = DispatchQueue(label: "velvet.remote.server", qos: .userInitiated)
    private let encoder = JSONEncoder()

    // NWPathMonitor : surveille les changements d'interface réseau Mac
    private var pathMonitor: NWPathMonitor?
    private var lastPathStatus: NWPath.Status = .unsatisfied
    // Backoff exponentiel : 1 → 2 → 4 → 8 → 16 → 30s cap
    private var restartWorkItem: DispatchWorkItem?
    private var restartAttempts: Int = 0
    private var isStartingListener: Bool = false

    /// Appelé sur @MainActor quand un client envoie une commande.
    var onCommand: ((String) -> Void)?

    // MARK: - Start / Stop

    func start() {
        startListener()
        startPathMonitor()
    }

    private func startListener() {
        guard !isStartingListener else {
            print("[VelvetRemote] Restart skipped — already starting/running")
            return
        }
        isStartingListener = true
        listener?.cancel()
        listener = nil

        guard let newListener = try? NWListener(using: .tcp, on: Self.port) else {
            print("[VelvetRemote] Failed to create listener")
            isStartingListener = false
            return
        }

        newListener.service = NWListener.Service(type: Self.serviceType)

        newListener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isStartingListener = false
                    if self.restartAttempts > 0 {
                        print("[VelvetRemote] Restart attempts reset (was \(self.restartAttempts))")
                        self.restartAttempts = 0
                    }
                    print("[VelvetRemote] Server ready on port \(VelvetRemoteServer.port) — Bonjour: \(VelvetRemoteServer.serviceType)")
                }
            case .failed(let error):
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isStartingListener = false
                    print("[VelvetRemote] Server failed: \(error) — will restart")
                    self.scheduleRestart()
                }
            case .waiting(let error):
                print("[VelvetRemote] Server waiting: \(error)")
            default:
                break
            }
        }

        newListener.newConnectionHandler = { connection in
            Task { @MainActor [weak self] in self?.accept(connection) }
        }

        newListener.start(queue: queue)
        listener = newListener
    }

    func stop() {
        pathMonitor?.cancel()
        pathMonitor = nil
        restartWorkItem?.cancel()
        restartWorkItem = nil
        isStartingListener = false
        restartAttempts = 0
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        pingTimers.values.forEach { $0.cancel() }
        pingTimers.removeAll()
        listener?.cancel()
        listener = nil
        print("[VelvetRemote] Server stopped.")
    }

    // MARK: - NWPathMonitor (Mac)

    private func startPathMonitor() {
        pathMonitor?.cancel()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.handlePathUpdate(path)
            }
        }
        monitor.start(queue: DispatchQueue(label: "velvet.remote.pathmonitor", qos: .utility))
        pathMonitor = monitor
    }

    private func handlePathUpdate(_ path: NWPath) {
        let newStatus = path.status
        let ifaces = path.availableInterfaces.map { "\($0.name)(\($0.type))" }.joined(separator: ", ")
        print("[VelvetRemote] Network path update: \(newStatus) — interfaces: [\(ifaces)]")

        // Relancer si le réseau revient après avoir été indisponible
        if newStatus == .satisfied && lastPathStatus != .satisfied {
            print("[VelvetRemote] Network restored — restarting Bonjour advertisement")
            restartAttempts = 0
            scheduleRestart()
        }
        lastPathStatus = newStatus
    }

    private func scheduleRestart() {
        // Ne pas empiler plusieurs work items
        guard restartWorkItem == nil else { return }
        let delay = min(30.0, pow(2.0, Double(restartAttempts)))
        restartAttempts += 1
        print("[VelvetRemote] Restart scheduled in \(Int(delay))s (attempt \(restartAttempts))")
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.restartWorkItem = nil
                print("[VelvetRemote] Restarting listener…")
                self.connections.values.forEach { $0.cancel() }
                self.connections.removeAll()
                self.pingTimers.values.forEach { $0.cancel() }
                self.pingTimers.removeAll()
                self.startListener()
            }
        }
        restartWorkItem = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: - Connection handling

    private func accept(_ connection: NWConnection) {
        let id = UUID()
        connections[id] = connection

        connection.stateUpdateHandler = { state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    print("[VelvetRemote] Client connected — \(connection.endpoint) (\(id.uuidString.prefix(8)))")
                    self.startPing(for: id, connection: connection)
                    if let state = self.lastState { self.send(state, to: connection) }
                case .failed(let error):
                    print("[VelvetRemote] Client \(id.uuidString.prefix(8)) failed: \(error)")
                    self.remove(id)
                case .cancelled:
                    print("[VelvetRemote] Client \(id.uuidString.prefix(8)) disconnected.")
                    self.remove(id)
                default:
                    break
                }
            }
        }

        connection.start(queue: queue)
        receiveCommands(from: connection, id: id)
    }

    private func receiveCommands(from connection: NWConnection, id: UUID) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    var buffer = data
                    while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                        let lineData = buffer[buffer.startIndex...newline]
                        buffer = buffer[buffer.index(after: newline)...]
                        if let cmd = try? JSONDecoder().decode(RemoteCommand.self, from: lineData) {
                            print("[VelvetRemote] Command received: \(cmd.type)")
                            self.onCommand?(cmd.type)
                        }
                    }
                }
            }
            if !isComplete && error == nil {
                self.receiveCommands(from: connection, id: id)
            }
        }
    }

    private func remove(_ id: UUID) {
        connections[id]?.cancel()
        connections.removeValue(forKey: id)
        pingTimers[id]?.cancel()
        pingTimers.removeValue(forKey: id)
    }

    // MARK: - Ping

    private func startPing(for id: UUID, connection: NWConnection) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 5.0)
        timer.setEventHandler { [weak self] in
            self?.sendPing(to: id, connection: connection)
        }
        pingTimers[id] = timer
        timer.resume()
    }

    // nonisolated car appelé depuis le DispatchSource (queue background)
    nonisolated private func sendPing(to id: UUID, connection: NWConnection) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(RemotePing()),
              let line = String(data: data, encoding: .utf8)
        else { return }

        let payload = (line + "\n").data(using: .utf8)!
        connection.send(content: payload, completion: .contentProcessed { error in
            if let error {
                print("[VelvetRemote] Ping failed for \(id.uuidString.prefix(8)): \(error)")
            }
        })
    }

    // MARK: - Broadcast

    func broadcast(_ update: RemoteStateUpdate) {
        lastState = update
        guard !connections.isEmpty,
              let data = try? encoder.encode(update),
              let line = String(data: data, encoding: .utf8)
        else { return }

        let payload = (line + "\n").data(using: .utf8)!
        for connection in connections.values {
            connection.send(content: payload, completion: .idempotent)
        }
    }

    private func send(_ update: RemoteStateUpdate, to connection: NWConnection) {
        guard let data = try? encoder.encode(update),
              let line = String(data: data, encoding: .utf8)
        else { return }
        connection.send(content: (line + "\n").data(using: .utf8)!, completion: .idempotent)
    }
}
