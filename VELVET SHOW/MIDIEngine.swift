//
//  MIDIEngine.swift
//  VELVET SHOW
//
//  Wrapper minimal autour de CoreMIDI for la Phase MIDI 1.
//
//  Rôle :
//  - créer un client + un port de sortie CoreMIDI au lancement,
//  - lister les destinations MIDI visibles sur le Mac (interfaces USB,
//    drivers IAC, ports virtuels d'autres apps, etc.),
//  - se tenir at jour automatiquement quand un device est branché ou
//    débranché (via `MIDIClientCreateWithBlock`),
//  - envoyer un `MidiMessage` (issu de la base ShowBuddy) at une
//    destination donnée.
//
//  Ce que ce fichier NE fait PAS, volontairement :
//  - aucune logique métier (catégorie MAESTRO vs CQ18T, log, simulation
//    vs live...) — tout ça vit dans `AppState`,
//  - aucune écoute d'entrée MIDI (pas de footswitch en V1),
//  - aucune mémorisation de la destination préférée (UserDefaults vit
//    dans `AppState`),
//  - aucun timecode/scheduling (envoi immédiat avec timestamp 0).
//
//  Sandbox / Hardened Runtime : CoreMIDI ne nécessite PAS d'entitlement
//  spécifique sur macOS. Les destinations système sont accessibles
//  directement depuis une app sandboxée.
//

import Foundation
import CoreMIDI

@MainActor
@Observable
final class MIDIEngine {

    // MARK: - Types

    /// Une destination MIDI visible du système : identifiée par son
    /// `MIDIUniqueID` (stable entre sessions for les interfaces hardware).
    struct Destination: Identifiable, Hashable {
        let id: MIDIUniqueID          // identité stable, persistable
        let displayName: String
        let endpoint: MIDIEndpointRef // utilisé for MIDISend (volatile)

        static func == (lhs: Destination, rhs: Destination) -> Bool {
            lhs.id == rhs.id
        }
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    enum MIDIError: LocalizedError {
        case clientCreationFailed(OSStatus)
        case portCreationFailed(OSStatus)
        case noStatusByte
        case engineNotReady
        case sendFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .clientCreationFailed(let s): return "MIDIClientCreate failed (OSStatus \(s))"
            case .portCreationFailed(let s):   return "MIDIOutputPortCreate failed (OSStatus \(s))"
            case .noStatusByte:                return "Message MIDI sans status byte"
            case .engineNotReady:              return "CoreMIDI engine is not initialized"
            case .sendFailed(let s):           return "MIDISend failed (OSStatus \(s))"
            }
        }
    }

    // MARK: - État observable

    /// Liste des destinations MIDI actuellement visibles.
    private(set) var destinations: [Destination] = []

    /// `true` une fois que le client + le port de sortie sont créés.
    private(set) var isReady: Bool = false

    /// Dernière erreur de configuration (init / refresh). Pour debug UI.
    private(set) var lastError: String?

    // MARK: - Internals CoreMIDI
    //
    // Les deux refs CoreMIDI sont des opaque pointers gérés par le
    // framework lui-même — l'état "Swift" qu'on protège via @MainActor
    // ce sont `destinations` / `isReady` / `lastError`, pas ces refs.
    // `nonisolated(unsafe)` permet at `deinit` (qui n'est pas main-actor
    // dans Swift 6) d'appeler `MIDIPortDispose` / `MIDIClientDispose`
    // sans warning d'isolation.

    nonisolated(unsafe) private var client: MIDIClientRef = 0
    nonisolated(unsafe) private var outputPort: MIDIPortRef = 0

    // MARK: - Cycle de vie

    init() {
        // 1) Client : reçoit les notifications de changement de setup
        //    (device branché/débranché, renommage, etc.) — on rafraîchit
        //    la liste at chaque notif sur le main actor.
        let clientStatus = MIDIClientCreateWithBlock(
            "VELVET SHOW" as CFString,
            &client
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        guard clientStatus == noErr else {
            self.lastError = MIDIError
                .clientCreationFailed(clientStatus)
                .localizedDescription
            return
        }

        // 2) Port de sortie : nécessaire for appeler MIDISend.
        let portStatus = MIDIOutputPortCreate(
            client,
            "VELVET SHOW Output" as CFString,
            &outputPort
        )
        guard portStatus == noErr else {
            self.lastError = MIDIError
                .portCreationFailed(portStatus)
                .localizedDescription
            return
        }

        self.isReady = true
        refresh()
    }

    deinit {
        // L'ARC de Swift n'appelle pas automatiquement Dispose sur les
        // ressources CoreMIDI — il faut les relâcher explicitement.
        if outputPort != 0 { MIDIPortDispose(outputPort) }
        if client     != 0 { MIDIClientDispose(client) }
    }

    // MARK: - Énumération des destinations

    /// Rafraîchit la liste des destinations. Appelé au démarrage et
    /// automatiquement quand le setup MIDI système change.
    func refresh() {
        var list: [Destination] = []
        let count = MIDIGetNumberOfDestinations()

        for i in 0..<count {
            let endpoint = MIDIGetDestination(i)
            guard endpoint != 0 else { continue }

            var uid: MIDIUniqueID = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uid)

            var nameRef: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &nameRef)
            let name = (nameRef?.takeRetainedValue() as String?) ?? "Sans nom"

            list.append(Destination(id: uid, displayName: name, endpoint: endpoint))
        }

        self.destinations = list.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    /// Retrouve une destination par son UniqueID (utilisé for résoudre
    /// le choix utilisateur persisté dans UserDefaults).
    func destination(withID id: MIDIUniqueID) -> Destination? {
        destinations.first { $0.id == id }
    }

    // MARK: - Envoi

    /// Envoie un `MidiMessage` at une destination CoreMIDI.
    ///
    /// Reconstruit le status byte canonique en combinant le high nibble
    /// stocké en base (`message`, ex. 144 = 0x90 = Note On) avec le low
    /// nibble du canal (`channel`, valeur brute 0-15 de la base).
    ///
    /// Le nombre de data bytes dépend du type :
    /// - Program Change (0xC0) et Channel Pressure (0xD0) : 1 data byte.
    /// - Les more (Note On/Off, CC, Pitch Bend, etc.) : 2 data bytes.
    ///
    /// Envoi immédiat (timestamp 0). Le scheduling fin (synchro audio)
    /// viendra avec la Phase Audio + Timeline.
    func send(message: MidiMessage, to destination: Destination) throws {
        guard isReady else { throw MIDIError.engineNotReady }
        guard let statusHigh = message.message else { throw MIDIError.noStatusByte }

        // Status byte : haut = type de message, bas = canal (0-15).
        let channel = UInt8((message.channel ?? 0) & 0x0F)
        let status  = UInt8(statusHigh & 0xF0) | channel

        // 1 data byte (PC, CP) ou 2 (le reste) ?
        let twoData: Bool
        switch statusHigh & 0xF0 {
        case 0xC0, 0xD0: twoData = false
        default:         twoData = true
        }

        var bytes: [UInt8] = [status]
        bytes.append(UInt8((message.data1 ?? 0) & 0x7F))
        if twoData {
            bytes.append(UInt8((message.data2 ?? 0) & 0x7F))
        }

        try sendBytes(bytes, to: destination.endpoint)
    }

    /// Empaquète un petit message MIDI dans un `MIDIPacketList` et
    /// l'envoie. Pour des messages courts (≤ 3 octets, cas standard
    /// Note On / Off / CC / PC), un seul packet inline suffit.
    private func sendBytes(_ bytes: [UInt8], to endpoint: MIDIEndpointRef) throws {
        var packet = MIDIPacket()
        packet.timeStamp = 0
        packet.length    = UInt16(bytes.count)

        // `packet.data` est exposé en Swift comme un tuple de 256 UInt8.
        // On y écrit nos bytes via une UnsafeMutableRawBufferPointer.
        withUnsafeMutableBytes(of: &packet.data) { raw in
            for i in 0..<bytes.count where i < raw.count {
                raw[i] = bytes[i]
            }
        }

        var list   = MIDIPacketList(numPackets: 1, packet: packet)
        let status = MIDISend(outputPort, endpoint, &list)
        if status != noErr {
            throw MIDIError.sendFailed(status)
        }
    }
}
