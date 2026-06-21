//
//  ShowBuddyDatabase.swift
//  VELVET SHOW
//
//  Mini-wrapper SQLite read-only construit directement sur l'API C de
//  SQLite3 (livrée avec macOS — aucune dépendance externe nécessaire).
//
//  Objectif Phase 1 :
//  - ouvrir ShowBuddy.db en lecture seule (on ne veut JAMAIS modifier
//    le backup de l'utilisateur),
//  - compter les lignes de chaque table,
//  - charger les Sets / LightShows / AudioFiles / SetElements.
//
//  On garde la surface volontairement petite : chaque table a une
//  petite fonction de chargement dédiée, facile at étendre plus tard
//  (filtres, pagination, jointures côté SQL, etc.).
//

import Foundation
import SQLite3

// MARK: - Errors

enum ShowBuddyError: LocalizedError {
    case openFailed(String)
    case notSQLiteDatabase(String)
    case prepareFailed(String)
    case stepFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let m):    return "Could not open database: \(m)"
        case .notSQLiteDatabase(let name):
            return "\"\(name)\" is not a SQLite database. Select the real ShowBuddy.db file, not a PDF, folder, incomplete alias, or another exported file."
        case .prepareFailed(let m): return "Failed to prepare query: \(m)"
        case .stepFailed(let m):    return "Failed to read row: \(m)"
        }
    }
}

// SQLite définit SQLITE_TRANSIENT comme `((sqlite3_destructor_type)-1)` dans
// son header C, mais cette macro n'est pas exposée at Swift. On la recrée ici
// for pouvoir l'utiliser le jour où on bindra des strings (Phase 2+).
private let SQLITE_TRANSIENT = unsafeBitCast(
    OpaquePointer(bitPattern: -1),
    to: sqlite3_destructor_type.self
)

// MARK: - Wrapper

final class ShowBuddyDatabase {

    /// Pointeur opaque to la connexion sqlite3. Nil tant qu'on n'a pas ouvert.
    private var db: OpaquePointer?

    /// URL du fichier ouvert, conservée for affichage et debug.
    let fileURL: URL

    // MARK: Ouverture / fermeture

    /// Ouvre la base en READ-ONLY. Throw si SQLite refuse (fichier corrompu,
    /// pas un .db, droits insuffisants, etc.).
    init(url: URL) throws {
        self.fileURL = url

        // SQLite accepte parfois d'ouvrir un fichier quelconque puis ne
        // signale l'erreur qu'à la première requête ("file is not a
        // database"). On vérifie donc l'en-tête standard avant d'aller
        // plus loin, for donner une erreur claire at l'utilisateur.
        guard Self.hasSQLiteHeader(url: url) else {
            throw ShowBuddyError.notSQLiteDatabase(url.lastPathComponent)
        }

        // SQLITE_OPEN_READONLY garantit qu'on ne modifie jamais le backup.
        let flags = SQLITE_OPEN_READONLY
        let openResult = sqlite3_open_v2(url.path, &db, flags, nil)

        if openResult != SQLITE_OK {
            // Récupère le message d'erreur SQLite avant de tout fermer.
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "inconnu"
            sqlite3_close(db)
            db = nil
            throw ShowBuddyError.openFailed(message)
        }
    }

    deinit {
        if db != nil { sqlite3_close(db) }
    }

    private static func hasSQLiteHeader(url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let header = try? handle.read(upToCount: 16)
        return header == Data("SQLite format 3\u{0}".utf8)
    }

    // MARK: - Lecteurs de colonnes "défensifs"
    //
    // À chaque cellule on vérifie d'abord si la valeur est NULL for la
    // remonter comme nil côté Swift. Cela évite d'obtenir un 0 trompeur
    // for un entier réellement absent dans la base.

    private func optString(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let cString = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cString)
    }

    private func optInt(_ stmt: OpaquePointer, _ index: Int32) -> Int64? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(stmt, index)
    }

    private func optDouble(_ stmt: OpaquePointer, _ index: Int32) -> Double? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(stmt, index)
    }

    // MARK: - Helpers génériques

    /// COUNT(*) sur une table. Retourne 0 si la table est absente plutôt
    /// que de propager une erreur — on veut un dashboard tolérant.
    func count(table: String) -> Int {
        // Les guillemets doubles protègent les noms réservés ("Sets", etc.).
        let sql = "SELECT COUNT(*) FROM \"\(table)\""
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return 0
        }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    /// Exécute `sql` et transforme chaque ligne en T via `map`.
    private func query<T>(_ sql: String, _ map: (OpaquePointer) -> T) throws -> [T] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let stmt = statement else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "inconnu"
            throw ShowBuddyError.prepareFailed(msg)
        }

        var rows: [T] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_ROW {
                rows.append(map(stmt))
            } else if step == SQLITE_DONE {
                break
            } else {
                let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "inconnu"
                throw ShowBuddyError.stepFailed(msg)
            }
        }
        return rows
    }

    // MARK: - Chargements typés

    func loadSets() throws -> [ShowSet] {
        let sql = """
            SELECT SetID, Name, Note, Folder, "Type"
            FROM "Sets"
            ORDER BY Name COLLATE NOCASE
            """
        return try query(sql) { stmt in
            ShowSet(
                setID:   sqlite3_column_int64(stmt, 0),
                name:    optString(stmt, 1),
                note:    optString(stmt, 2),
                folder:  optString(stmt, 3),
                setType: optString(stmt, 4)
            )
        }
    }

    func loadLightShows() throws -> [LightShow] {
        let sql = """
            SELECT LightShowID, Name, AudioFileID, DmxisShowName, Note,
                   Tempo, TrimStart, TrimEnd, AudioVolume
            FROM LightShows
            """
        return try query(sql) { stmt in
            LightShow(
                lightShowID:    sqlite3_column_int64(stmt, 0),
                name:           optString(stmt, 1),
                audioFileID:    optInt(stmt, 2),
                dmxisShowName:  optString(stmt, 3),
                note:           optString(stmt, 4),
                tempo:          optDouble(stmt, 5),
                trimStart:      optDouble(stmt, 6),
                trimEnd:        optDouble(stmt, 7),
                audioVolume:    optDouble(stmt, 8)
            )
        }
    }

    func loadAudioFiles() throws -> [AudioFile] {
        let sql = """
            SELECT AudioFileID, Name, Path, Note, LengthSecs, MainAudioFileID
            FROM AudioFiles
            """
        return try query(sql) { stmt in
            AudioFile(
                audioFileID:     sqlite3_column_int64(stmt, 0),
                name:            optString(stmt, 1),
                path:            optString(stmt, 2),
                note:            optString(stmt, 3),
                lengthSecs:      optDouble(stmt, 4),
                mainAudioFileID: optInt(stmt, 5)
            )
        }
    }

    /// Charge les éléments d'un set précis, ordonnés par PlayOrder.
    /// On utilise un paramètre lié (?1) plutôt qu'une concaténation : c'est
    /// la bonne hygiène SQL même si l'ID vient de notre propre base.
    func loadSetElements(forSetID setID: Int64) throws -> [SetElement] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        let sql = """
            SELECT SetElementID, SetID, LightShowID, PlayOrder, Note,
                   AutoStart, Loop, Colour
            FROM SetElements
            WHERE SetID = ?1
            ORDER BY PlayOrder
            """

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let stmt = statement else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "inconnu"
            throw ShowBuddyError.prepareFailed(msg)
        }
        sqlite3_bind_int64(stmt, 1, setID)

        var result: [SetElement] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_ROW {
                result.append(SetElement(
                    setElementID: sqlite3_column_int64(stmt, 0),
                    setID:        sqlite3_column_int64(stmt, 1),
                    lightShowID:  sqlite3_column_int64(stmt, 2),
                    playOrder:    optInt(stmt, 3),
                    note:         optString(stmt, 4),
                    autoStart:    optInt(stmt, 5),
                    loop:         optInt(stmt, 6),
                    colour:       optString(stmt, 7)
                ))
            } else if step == SQLITE_DONE {
                break
            } else {
                let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "inconnu"
                throw ShowBuddyError.stepFailed(msg)
            }
        }
        return result
    }

    func loadShowMemos() throws -> [ShowMemo] {
        let sql = """
            SELECT ShowMemoID, LightShowID, ShortName, Memo, MemoTime,
                   MemoLength, CountIn, StartMidiEventID, EndMidiEventID
            FROM ShowMemos
            ORDER BY MemoTime
            """
        return try query(sql) { stmt in
            ShowMemo(
                showMemoID:       sqlite3_column_int64(stmt, 0),
                lightShowID:      optInt(stmt, 1),
                shortName:        optString(stmt, 2),
                memo:             optString(stmt, 3),
                memoTime:         optDouble(stmt, 4),
                memoLength:       optDouble(stmt, 5),
                countIn:          optDouble(stmt, 6),
                startMidiEventID: optInt(stmt, 7),
                endMidiEventID:   optInt(stmt, 8)
            )
        }
    }

    func loadMidiEvents() throws -> [MidiEvent] {
        let sql = "SELECT MidiEventID, Name, Category FROM MidiEvents"
        return try query(sql) { stmt in
            MidiEvent(
                midiEventID: sqlite3_column_int64(stmt, 0),
                name:        optString(stmt, 1),
                category:    optString(stmt, 2)
            )
        }
    }

    /// Charge tous les MidiMessages, ordonnés par MidiEventID puis Time.
    /// On les indexera ensuite côté `AppState` par MidiEventID pour
    /// pouvoir afficher les messages d'un event en O(1).
    func loadMidiMessages() throws -> [MidiMessage] {
        let sql = """
            SELECT MidiMessageID, MidiEventID, Time, OutDevice, Channel,
                   Message, Data1, Data2
            FROM MidiMessages
            ORDER BY MidiEventID, Time
            """
        return try query(sql) { stmt in
            MidiMessage(
                midiMessageID: sqlite3_column_int64(stmt, 0),
                midiEventID:   optInt(stmt, 1),
                time:          optDouble(stmt, 2),
                outDevice:     optString(stmt, 3),
                channel:       optInt(stmt, 4),
                message:       optInt(stmt, 5),
                data1:         optInt(stmt, 6),
                data2:         optInt(stmt, 7)
            )
        }
    }

    // MARK: - Compteurs globaux for le dashboard

    func loadStats() -> LibraryStats {
        LibraryStats(
            audioFiles:   count(table: "AudioFiles"),
            lightShows:   count(table: "LightShows"),
            sets:         count(table: "Sets"),
            setElements:  count(table: "SetElements"),
            midiEvents:   count(table: "MidiEvents"),
            midiMessages: count(table: "MidiMessages"),
            showMemos:    count(table: "ShowMemos")
        )
    }
}
