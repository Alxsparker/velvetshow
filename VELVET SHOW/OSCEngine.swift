//
//  OSCEngine.swift
//  VELVET SHOW
//
//  Minimal Open Sound Control (OSC 1.0) sender, sibling to MIDIEngine.
//
//  Role:
//  - encode an OSC message (address + optional typed argument) as a binary
//    packet per the OSC 1.0 spec (4-byte aligned, null-terminated strings,
//    big-endian numerics, type-tag string starting with ',') ;
//  - send it over UDP to an arbitrary host:port using Network.framework.
//
//  Explicitly out of scope (would belong in AppState if ever needed):
//  - no bundling, no time-tags (everything is sent immediately, the
//    scheduling lives in AppState.tickMidiScheduler);
//  - no destination persistence (each OSC cue carries its own host/port);
//  - no incoming OSC (the app is sender-only in V1).
//

import Foundation
import Network

@MainActor
@Observable
final class OSCEngine {

    enum OSCError: LocalizedError {
        case invalidAddress
        case invalidHost
        case invalidPort
        case sendFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidAddress:        return "OSC address pattern is empty or invalid"
            case .invalidHost:           return "OSC host is empty"
            case .invalidPort:           return "OSC port must be 1...65535"
            case .sendFailed(let msg):   return "OSC send failed: \(msg)"
            }
        }
    }

    /// Last error encountered when sending — surfaced in debug UI.
    private(set) var lastError: String?

    // ── Connexions persistantes ──────────────────────────────────────────
    // Une NWConnection UDP par host:port, créée au premier envoi puis
    // réutilisée (plus de setup ~ms + allocations par message, ordre
    // d'émission garanti). Retirée du cache si elle échoue — le prochain
    // envoi la recrée. `sendDatagram` est appelable depuis n'importe quel
    // thread (scheduler temps réel inclus) : NWConnection.send est
    // thread-safe et les envois émis avant `.ready` sont mis en attente
    // par Network.framework.
    nonisolated(unsafe) private var connections: [String: NWConnection] = [:]
    nonisolated(unsafe) private let connectionsLock = NSLock()
    private static let oscQueue = DispatchQueue(
        label: "fr.loveandlive.velvetshow.osc",
        qos: .userInitiated
    )

    /// Send an OSC message immediately to the given host/port.
    /// `value` is optional (commands like `/cue/scene/1` are often valueless).
    func send(
        address: String,
        value: OSCValue?,
        host: String,
        port: Int
    ) throws {
        let cleanAddress = address.trimmingCharacters(in: .whitespaces)
        guard !cleanAddress.isEmpty, cleanAddress.hasPrefix("/") else {
            throw OSCError.invalidAddress
        }
        let cleanHost = host.trimmingCharacters(in: .whitespaces)
        guard !cleanHost.isEmpty else { throw OSCError.invalidHost }
        guard (1...65535).contains(port) else { throw OSCError.invalidPort }

        let data = Self.encodePacket(address: cleanAddress, value: value)
        sendDatagram(data, host: cleanHost, port: UInt16(port))
    }

    /// Envoi d'un datagramme pré-encodé sur la connexion persistante du
    /// couple host:port. Thread-safe — utilisé par le scheduler MIDI/OSC.
    nonisolated func sendDatagram(_ data: Data, host: String, port: UInt16) {
        guard let connection = connection(host: host, port: port) else { return }
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.invalidateConnection(host: host, port: port)
                Task { @MainActor [weak self] in
                    self?.lastError = error.localizedDescription
                }
            }
        })
    }

    nonisolated private func connection(host: String, port: UInt16) -> NWConnection? {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return nil }
        let key = "\(host):\(port)"
        connectionsLock.lock()
        if let existing = connections[key] {
            connectionsLock.unlock()
            return existing
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .udp)
        connections[key] = connection
        connectionsLock.unlock()
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error):
                self?.invalidateConnection(host: host, port: port)
                Task { @MainActor [weak self] in
                    self?.lastError = error.localizedDescription
                }
            case .cancelled:
                self?.invalidateConnection(host: host, port: port)
            default:
                break
            }
        }
        connection.start(queue: Self.oscQueue)
        return connection
    }

    nonisolated private func invalidateConnection(host: String, port: UInt16) {
        let key = "\(host):\(port)"
        connectionsLock.lock()
        let connection = connections.removeValue(forKey: key)
        connectionsLock.unlock()
        connection?.cancel()
    }

    // MARK: - Packet encoding (OSC 1.0)

    /// Encode one OSC message: address pattern + ",<typetag>" + argument bytes.
    /// Each piece is null-terminated and padded to a 4-byte boundary.
    static func encodePacket(address: String, value: OSCValue?) -> Data {
        var data = Data()
        data.append(oscString(address))

        switch value {
        case .none:
            data.append(oscString(","))
        case .some(.int(let v)):
            data.append(oscString(",i"))
            data.append(oscInt32(Int32(clamping: v)))
        case .some(.float(let v)):
            data.append(oscString(",f"))
            data.append(oscFloat32(Float(v)))
        case .some(.string(let v)):
            data.append(oscString(",s"))
            data.append(oscString(v))
        case .some(.bool(let v)):
            // OSC 1.1 booleans: type tag T (true) or F (false), no payload.
            data.append(oscString(v ? ",T" : ",F"))
        }
        return data
    }

    /// OSC string: UTF-8 bytes, null-terminated, padded to a 4-byte boundary.
    private static func oscString(_ s: String) -> Data {
        var bytes = Data(s.utf8)
        bytes.append(0)
        let padding = (4 - bytes.count % 4) % 4
        if padding > 0 {
            bytes.append(contentsOf: [UInt8](repeating: 0, count: padding))
        }
        return bytes
    }

    private static func oscInt32(_ v: Int32) -> Data {
        var be = v.bigEndian
        return Data(bytes: &be, count: 4)
    }

    private static func oscFloat32(_ v: Float) -> Data {
        var be = v.bitPattern.bigEndian
        return Data(bytes: &be, count: 4)
    }
}
