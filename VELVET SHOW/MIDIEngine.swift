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

    /// Liste des sources MIDI actuellement visibles (footswitches, contrôleurs).
    private(set) var sources: [Destination] = []

    /// `true` une fois que le client + le port de sortie sont créés.
    private(set) var isReady: Bool = false

    /// Dernière erreur de configuration (init / refresh). Pour debug UI.
    private(set) var lastError: String?

    /// Callback appelé sur le main actor pour chaque message MIDI entrant.
    /// Tuple : (sourceUniqueID, status byte high nibble, channel 0-15, data1, data2).
    /// Note Off (0x80 ou Note On velocity 0) est filtré en amont pour éviter
    /// le double déclenchement à la relâche d'un footswitch.
    var onInput: ((Int32, UInt8, UInt8, UInt8, UInt8) -> Void)?

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
    nonisolated(unsafe) private var inputPort: MIDIPortRef = 0
    /// Endpoints actuellement connectés au port d'entrée. Tracé pour
    /// pouvoir déconnecter/reconnecter proprement quand le setup change.
    nonisolated(unsafe) private var connectedSourceEndpoints: Set<MIDIEndpointRef> = []

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

        // 3) Port d'entrée : on lit toutes les sources (footswitches, BT MIDI,
        //    contrôleurs) via un seul port. Le bloc callback est appelé sur
        //    un thread privé CoreMIDI — on bounce sur le main actor pour
        //    appeler `onInput`.
        let inputStatus = MIDIInputPortCreateWithBlock(
            client,
            "VELVET SHOW Input" as CFString,
            &inputPort
        ) { [weak self] packetList, _ in
            self?.processPacketList(packetList)
        }
        guard inputStatus == noErr else {
            self.lastError = MIDIError
                .portCreationFailed(inputStatus)
                .localizedDescription
            return
        }

        self.isReady = true
        refresh()
    }

    deinit {
        // L'ARC de Swift n'appelle pas automatiquement Dispose sur les
        // ressources CoreMIDI — il faut les relâcher explicitement.
        if inputPort  != 0 { MIDIPortDispose(inputPort) }
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

        // Énumère les sources (entrées MIDI) et connecte chacune au port
        // d'entrée. Idempotent : on ne reconnecte pas un endpoint déjà connu,
        // et on déconnecte ceux qui ont disparu.
        var sourceList: [Destination] = []
        var currentSourceEndpoints: Set<MIDIEndpointRef> = []
        let sourceCount = MIDIGetNumberOfSources()
        for i in 0..<sourceCount {
            let endpoint = MIDIGetSource(i)
            guard endpoint != 0 else { continue }
            var uid: MIDIUniqueID = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uid)
            var nameRef: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &nameRef)
            let name = (nameRef?.takeRetainedValue() as String?) ?? "Sans nom"
            sourceList.append(Destination(id: uid, displayName: name, endpoint: endpoint))
            currentSourceEndpoints.insert(endpoint)

            // Connecter si pas déjà connecté
            if inputPort != 0, !connectedSourceEndpoints.contains(endpoint) {
                let st = MIDIPortConnectSource(inputPort, endpoint, nil)
                if st == noErr {
                    connectedSourceEndpoints.insert(endpoint)
                } else {
                    print("[MIDI] connect source \(name) failed: \(st)")
                }
            }
        }
        // Déconnecter les endpoints disparus
        for stale in connectedSourceEndpoints.subtracting(currentSourceEndpoints) {
            if inputPort != 0 { MIDIPortDisconnectSource(inputPort, stale) }
            connectedSourceEndpoints.remove(stale)
        }
        self.sources = sourceList.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    /// Retrouve une destination par son UniqueID (utilisé for résoudre
    /// le choix utilisateur persisté dans UserDefaults).
    func destination(withID id: MIDIUniqueID) -> Destination? {
        destinations.first { $0.id == id }
    }

    /// Retrouve une source par son UniqueID.
    func source(withID id: MIDIUniqueID) -> Destination? {
        sources.first { $0.id == id }
    }

    // MARK: - Lecture entrante

    /// Appelé sur un thread privé CoreMIDI. Décode les MIDIPacket pour en
    /// extraire des messages de transport (Note On / CC / Program Change)
    /// et les rebascule vers le main actor via `onInput`.
    nonisolated private func processPacketList(_ packetList: UnsafePointer<MIDIPacketList>) {
        var packet = packetList.pointee.packet
        let n = packetList.pointee.numPackets
        for _ in 0..<n {
            let length = Int(packet.length)
            if length >= 1 {
                withUnsafeBytes(of: packet.data) { raw in
                    // On ne peut pas connaître la source du packet sans
                    // srcConnRefCon ; V1 : sourceUID toujours 0, le dispatcher
                    // AppState match juste sur (status, channel, data1).
                    // Cas ambigu : deux footswitches envoyant exactement le
                    // même message — on traitera si ça remonte un jour.
                    let b0 = length > 0 ? raw[0] : 0
                    let b1 = length > 1 ? raw[1] : 0
                    let b2 = length > 2 ? raw[2] : 0
                    let statusHigh = b0 & 0xF0
                    let channel    = b0 & 0x0F
                    // Filtre Note Off et Note On vel=0 (relâche pédale) →
                    // évite le double déclenchement push/release.
                    if statusHigh == 0x80 { return }
                    if statusHigh == 0x90, b2 == 0 { return }
                    DispatchQueue.main.async { [weak self] in
                        self?.onInput?(0, statusHigh, channel, b1, b2)
                    }
                }
            }
            packet = MIDIPacketNext(&packet).pointee
        }
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
        guard let bytes = Self.rawBytes(for: message) else { throw MIDIError.noStatusByte }
        try sendBytes(bytes, to: destination.endpoint)
    }

    /// Empaquète un petit message MIDI dans un `MIDIPacketList` et
    /// l'envoie. Pour des messages courts (≤ 3 octets, cas standard
    /// Note On / Off / CC / PC), un seul packet inline suffit.
    private func sendBytes(_ bytes: [UInt8], to endpoint: MIDIEndpointRef) throws {
        let status = Self.sendRaw(bytes, port: outputPort, endpoint: endpoint)
        if status != noErr {
            throw MIDIError.sendFailed(status)
        }
    }

    // MARK: - Envoi hors MainActor (scheduler temps réel)

    /// Port de sortie, lisible depuis la queue du scheduler. CoreMIDI refs
    /// sont des handles opaques thread-safe ; `MIDISend` est appelable
    /// depuis n'importe quel thread.
    nonisolated var schedulerOutputPort: MIDIPortRef { outputPort }

    /// Envoi brut, sans isolation — utilisé par le scheduler MIDI/OSC sur
    /// sa queue dédiée. Même empaquetage que `sendBytes`.
    nonisolated static func sendRaw(
        _ bytes: [UInt8],
        port: MIDIPortRef,
        endpoint: MIDIEndpointRef
    ) -> OSStatus {
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

        var list = MIDIPacketList(numPackets: 1, packet: packet)
        return MIDISend(port, endpoint, &list)
    }

    /// Bytes d'un `MidiMessage` — même construction que `send(message:to:)`.
    /// nil si le message n'a pas de status byte.
    nonisolated static func rawBytes(for message: MidiMessage) -> [UInt8]? {
        guard let statusHigh = message.message else { return nil }
        let channel = UInt8((message.channel ?? 0) & 0x0F)
        let status  = UInt8(statusHigh & 0xF0) | channel
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
        return bytes
    }
}
