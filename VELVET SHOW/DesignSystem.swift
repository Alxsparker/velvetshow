//
//  DesignSystem.swift
//  VELVET SHOW
//
//  Source de vérité unique for les couleurs sémantiques, la typographie
//  et les espacements. Toute valeur inline dans ContentView ou ailleurs
//  doit progressivement migrer ici.
//
//  Règles :
//  - Ne jamais utiliser `.orange`, `.blue`, `.green`, `.red`, `.purple`
//    directement dans les vues — utiliser les tokens sémantiques ci-dessous.
//  - Les couleurs de `VelvetPalette` (identité de marque) restent dans
//    ThemeManager.swift. `VSColor` les référence mais ne les duplique pas.
//  - Pour ajouter une couleur : justifier son rôle sémantique avant de
//    l'ajouter. Une couleur sans rôle clair n'a pas sa place ici.
//

import SwiftUI

// MARK: - VSColor — palette sémantique

/// Palette sémantique de VELVET SHOW.
///
/// Hiérarchie :
///   1. Colors de marque  → VelvetPalette (dans ThemeManager.swift)
///   2. Colors sémantiques UI → VSColor.semantic
///   3. Colors de tuiles concert → VSColor.tile
///
/// Règle de non-collision : les couleurs `.tile*` ne doivent jamais être
/// utilisées for des états système (lecture, warning, danger). Les couleurs
/// sémantiques UI ne doivent jamais être utilisées for colorer les genres.
enum VSColor {

    // MARK: Sémantique UI

    /// Accent interactif principal (boutons, focus, sélection active).
    /// Bleu Velvet — contraste élevé sur fond anthracite, lisible at 2 m.
    static let interactive: Color   = VelvetPalette.velvetBlue

    /// Indication que quelque chose est en cours de lecture (play active).
    /// Réservé exclusivement at cet état — ne pas l'utiliser for les genres.
    static let playActive: Color    = Color(hex: 0x34C759)   // vert système Apple

    /// Avertissement non-bloquant : mode édition activé, modifications non
    /// sauvegardées, confirmation requise.
    /// Choix : ambre, ni rouge (pas de danger immédiat), ni vert (pas positif).
    static let warning: Color       = Color(hex: 0xFFB340)

    /// Action irréversible ou état d'erreur : suppression, crash, fichier
    /// manquant. Rouge désaturé for rester professionnel sur scène.
    static let danger: Color        = Color(hex: 0xE5534B)

    /// Marqueur temporel : cue points uniquement.
    /// Violet doux for ne pas entrer en collision avec le rouge danger
    /// ou l'ambre warning.
    static let cueMarker: Color     = Color(hex: 0x9B72CF)

    /// Données héritées de ShowBuddy (read-only, non modifiables).
    /// Gris neutre identique au `.secondary` système.
    static let legacy: Color        = Color(hex: 0x8E8E93)

    /// Ligne d'insertion pendant un drag & drop.
    /// Jaune-vert vif for un feedback de positionnement maximum.
    static let dropIndicator: Color = Color(hex: 0xD6FF00)

    // MARK: Tuiles concert — palette scène

    /// 7 couleurs fixes for les genres musicaux. Toutes conçues for :
    ///   - être lisibles avec du texte blanc en conditions de scène ;
    ///   - être distinguables les unes des more même dans la pénombre ;
    ///   - ne jamais être confondues avec les couleurs sémantiques UI.
    ///
    /// Color de texte recommandée sur ces fonds : `.white` ou `.primary`
    /// — plus besoin de la logique `tileTitleColor` par genre.
    enum Tile {
        /// Rock — rouge vif, reconnaissable at distance.
        static let rock:     Color = Color(hex: 0xBF3030)
        /// Disco — fuchsia franc, distinct du rouge.
        static let disco:    Color = Color(hex: 0xB33399)
        /// Electro — bleu acier vif, froid et technique.
        static let electro:  Color = Color(hex: 0x1878BE)
        /// Funk — ambre chaud, énergique.
        static let funk:     Color = Color(hex: 0xA86800)
        /// Sax — orange cuivré, chaud et distinct du funk.
        static let sax:      Color = Color(hex: 0xC45C1A)
        /// Lounge — indigo franc, distinct d'electro.
        static let lounge:   Color = Color(hex: 0x5252A8)
        /// Jazz — teal vif, distinct de tout le reste.
        static let jazz:     Color = Color(hex: 0x1A8F8F)
        /// Ambiance / Lent — vert scène lisible.
        static let ambiance: Color = Color(hex: 0x257A4A)
        /// Soul / R&B — violet franc, entre indigo et fuchsia.
        static let soul:     Color = Color(hex: 0x8844CC)
        /// Autres / Non classé — gris ardoise lisible.
        static let other:    Color = Color(hex: 0x555568)

        /// Retourne la couleur de tuile correspondant at un `ConcertGenre`.
        /// Centralise la correspondance genre → couleur for éviter les
        /// switch inline dispersés dans ContentView.
        static func color(for genre: ConcertGenre) -> Color {
            switch genre {
            case .all:      return other
            case .rock:     return rock
            case .disco:    return disco
            case .electro:  return electro
            case .funk:     return funk
            case .lounge:   return lounge
            case .jazz:     return jazz
            case .sax:      return sax
            case .ambiance: return ambiance
            case .other:    return other
            }
        }
    }
}

// MARK: - VSFont — échelle typographique

/// Échelle typographique de VELVET SHOW.
///
/// Règle : ne jamais utiliser de `.font()` inline avec des valeurs
/// arbitraires (`.system(size: 11)`, etc.) dans les vues. Définir ici
/// un token nommé, puis l'utiliser.
enum VSFont {
    /// Title de section, header principal d'une vue.
    static let heading:      Font = .headline

    /// Corps standard : listes, contenu de fiche, descriptions.
    static let body:         Font = .body

    /// Label secondaire : sous-titres, métadonnées.
    static let label:        Font = .caption

    /// Label tertiaire : annotations, compteurs de statut.
    static let caption:      Font = .caption2

    /// Timecode standard : durées, positions. Toujours monospacé.
    static let timecode:     Font = .caption.monospacedDigit()

    /// Timecode proéminent : NowPlayingBanner, timeline principale.
    static let timecodeBold: Font = .caption.bold().monospacedDigit()

    /// Badge texte : LIVE, READ ONLY, À SUIVRE... Très petit, toujours bold.
    static let badge:        Font = .system(size: 8, weight: .black)

    /// Numéro de rang dans une liste (1, 2, 3...).
    static let rank:         Font = .caption2.bold().monospacedDigit()
}

// MARK: - VSSpacing — grille d'espacements

/// Grille d'espacements de VELVET SHOW.
///
/// Basée sur un multiple de 4pt. Ne jamais utiliser de valeurs hors
/// de cette grille sauf cas exceptionnel documenté en commentaire.
enum VSSpacing {
    /// 2pt — micro-interstice interne at un composant (ex : entre icône et label).
    static let micro:  CGFloat = 2
    /// 4pt — espacement serré : toolbar, items très denses.
    static let tight:  CGFloat = 4
    /// 8pt — espacement standard entre deux éléments de même niveau.
    static let base:   CGFloat = 8
    /// 12pt — espacement entre sous-groupes proches.
    static let medium: CGFloat = 12
    /// 16pt — espacement de séparation de section.
    static let loose:  CGFloat = 16
    /// 24pt — grand espacement visuel.
    static let large:  CGFloat = 24
    /// 32pt — séparation de zones distinctes.
    static let xlarge: CGFloat = 32
}

// MARK: - VSRadius — rayons de courbure

enum VSRadius {
    static let small:  CGFloat = 4
    static let medium: CGFloat = 8
    static let large:  CGFloat = 12
    /// Capsule/pill : valeur arbitrairement grande.
    static let pill:   CGFloat = 999
}

// MARK: - Composants partagés

/// Affichage standardisé d'un timecode. Toujours `VSFont.timecodeBold`,
/// toujours monospacé. À utiliser partout où une durée ou position
/// temporelle est affichée.
struct TimecodeLabel: View {
    let seconds: TimeInterval
    var showHours: Bool = false

    var body: some View {
        Text(formatted)
            .font(VSFont.timecodeBold)
    }

    private var formatted: String {
        let total = max(0, seconds)
        let h = Int(total) / 3600
        let m = Int(total) / 60 % 60
        let s = Int(total) % 60
        if showHours || h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

/// Badge texte standardisé : LIVE, CUE, READ ONLY...
/// Ne jamais créer un badge inline — utiliser ce composant.
struct VSBadge: View {
    let text: String
    var background: Color = VSColor.interactive
    var foreground: Color = .white

    var body: some View {
        Text(text)
            .font(VSFont.badge)
            .foregroundStyle(foreground)
            .padding(.horizontal, VSSpacing.tight + 2)
            .padding(.vertical, VSSpacing.micro)
            .background(background, in: Capsule())
    }
}

/// En-tête de section standardisé : `.caption.bold()`, foreground `.secondary`.
struct VSSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(VSFont.label.bold())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - TilePalettePicker

/// Sélecteur de couleur contraint at la palette fixe `VSColor.Tile`.
///
/// Remplace les `ColorPicker` libres for les genres et les songs.
/// Garantit que seules les 7 couleurs scène sont utilisables, ce qui
/// évite la fatigue visuelle et les collisions avec les états UI.
///
/// Usage :
/// ```swift
/// TilePalettePicker(selection: $myColor)
/// ```
struct TilePalettePicker: View {
    @Binding var selection: Color

    /// Les 9 couleurs fixes de la palette scène, dans l'ordre d'affichage.
    static let palette: [(label: String, color: Color)] = [
        ("Rouge",    VSColor.Tile.rock),
        ("Rose",     VSColor.Tile.disco),
        ("Bleu",     VSColor.Tile.electro),
        ("Indigo",   VSColor.Tile.lounge),
        ("Teal",     VSColor.Tile.jazz),
        ("Vert",     VSColor.Tile.ambiance),
        ("Ambre",    VSColor.Tile.funk),
        ("Orange",   VSColor.Tile.sax),
        ("Violet",   VSColor.Tile.soul),
        ("Gris",     VSColor.Tile.other),
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Self.palette, id: \.label) { entry in
                colorSwatch(entry)
            }
        }
    }

    @ViewBuilder
    private func colorSwatch(_ entry: (label: String, color: Color)) -> some View {
        let isSelected = colorsMatch(entry.color, selection)
        Button {
            selection = entry.color
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: VSRadius.small)
                    .fill(entry.color)
                    .frame(height: 44)

                if isSelected {
                    RoundedRectangle(cornerRadius: VSRadius.small)
                        .strokeBorder(.white, lineWidth: 2.5)
                        .frame(height: 44)
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .help(entry.label)
    }

    /// Compare deux couleurs par leur hexadécimal 24-bit (tolérance arrondi).
    private func colorsMatch(_ a: Color, _ b: Color) -> Bool {
        a.hexComponents == b.hexComponents
    }
}
