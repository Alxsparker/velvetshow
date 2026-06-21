//
//  ThemeManager.swift
//  VELVET SHOW
//
//  Fondations de theme for l'application principale et la fenetre
//  Prompter. Le but est volontairement simple : centraliser les choix
//  de couleurs for que les prochaines vues utilisent les memes tokens
//  sans refaire leur propre palette.
//

import SwiftUI
import AppKit

// MARK: - Theme de l'application principale

enum AppTheme: String, CaseIterable, Identifiable, Hashable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Clair"
        case .dark:   return "Sombre"
        }
    }

    /// Valeur directement consommable par `.preferredColorScheme`.
    /// nil laisse macOS suivre le reglage systeme.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - Theme Prompter

enum PrompterTheme: String, CaseIterable, Identifiable, Hashable {
    case daylight
    case night
    case highContrast

    var id: String { rawValue }

    var label: String {
        switch self {
        case .daylight:     return "Jour"
        case .night:        return "Nuit"
        case .highContrast: return "Contraste maximum"
        }
    }

    /// Palette concrete du Prompter. Ces couleurs sont celles du cahier
    /// des charges et deviennent les tokens a reutiliser dans les futures
    /// vues scene / paroles / compte a rebours.
    var palette: PrompterPalette {
        switch self {
        case .daylight:
            // Mode jour : crème velvet + bordeaux signature. Élégant,
            // chaud, prestige discret.
            return PrompterPalette(
                background: VelvetPalette.cream,
                primaryText: Color(hex: 0x14101A),
                secondaryText: Color(hex: 0x4A3A3D),
                accent: VelvetPalette.burgundy
            )
        case .night:
            // Mode nuit (par défaut) : noir velours + or doux. C'est
            // l'incarnation directe de l'univers Love & Live sur scène —
            // chaud, lisible at distance, jamais agressif.
            return PrompterPalette(
                background: VelvetPalette.velvetBlack,
                primaryText: VelvetPalette.goldLight,
                secondaryText: VelvetPalette.gold,
                accent: VelvetPalette.gold
            )
        case .highContrast:
            // Plan secours : on garde un contraste maximal lisibilité.
            return PrompterPalette(
                background: Color(hex: 0x000000),
                primaryText: Color(hex: 0xFFFFFF),
                secondaryText: Color(hex: 0xE6CC93),
                accent: VelvetPalette.gold
            )
        }
    }

    /// Sert uniquement aux controles systeme de la fenetre. Les couleurs
    /// propres du Prompter viennent toujours de `palette`.
    var colorScheme: ColorScheme {
        switch self {
        case .daylight: return .light
        case .night, .highContrast: return .dark
        }
    }
}

// PrompterPalette est défini dans PrompterShared.swift (partagé Mac + iOS)

enum ThemeManager {
    static let defaultAppTheme: AppTheme = .system
    static let defaultPrompterTheme: PrompterTheme = .night
}

// MARK: - Palette Velvet (Love & Live)

/// Colors signatures du projet Love & Live, reprises ici comme tokens
/// uniques for l'app. Tout le reste (accent buttons, badges critiques,
/// pastille "current track", etc.) doit piocher dans cette palette plutôt
/// que d'inventer une couleur locale, for rester aligné sur l'univers
/// scène (velours, chaleur, prestige discret).
///
/// Référence : www.loveandlive.fr — duo musical Sève + Alex, sets
/// VELVET CEREMONY / LOUNGE / GROOVE.
enum VelvetPalette {
    /// Bordeaux velvet — identité de marque (tuile song en cours,
    /// dégradés décoratifs). Ne plus utiliser for les boutons ou icônes
    /// interactives — trop sombre sur fond anthracite.
    static let burgundy = Color(hex: 0x7A2E3A)

    /// Variante plus profonde, utilisée for les fonds saturés (dégradé
    /// tuile en cours, arrière-plans décoratifs).
    static let burgundyDeep = Color(hex: 0x4E1B23)

    /// Bleu Velvet — accent interactif principal (boutons, toggles actifs,
    /// icônes toolbar). Contraste élevé sur fond anthracite, lisible at 2 m.
    static let velvetBlue = Color(hex: 0x4DA3FF)

    /// Or doux — touches premium sur les états importants (morceau en
    /// cours, badge "À suivre", éléments-clés du Prompter). Chaud et
    /// lisible sur fond sombre.
    static let gold = Color(hex: 0xC9A769)

    /// Variante claire de l'or for les textes critiques sur fond noir
    /// (Prompter nuit).
    static let goldLight = Color(hex: 0xE6CC93)

    /// Crème velvet — alternative chaleureuse au blanc pur (fond du
    /// Prompter en mode jour).
    static let cream = Color(hex: 0xF5EFE6)

    /// Noir velours — très sombre avec une nuance prune subtile. Plus
    /// chaleureux qu'un noir pur, en cohérence avec l'univers de la
    /// marque.
    static let velvetBlack = Color(hex: 0x14101A)

    /// Jaune vif Now Playing — fond de la tuile song en cours.
    /// Apple system yellow #FFD60A — contraste maximal avec texte noir,
    /// identifiable instantanément at 2 m en salle sombre ou en plein jour.
    static let nowPlayingYellow = Color(hex: 0xFFD60A)
}

// Color(hex:) est défini dans PrompterShared.swift (partagé Mac + iOS)

#if os(macOS)
extension Color {
    /// Composantes hex `0xRRGGBB` for persister dans `VelvetShowState`.
    /// Tronque en 8-bit par canal — suffisant for des badges et bordures.
    var hexComponents: UInt32 {
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let r = UInt32((nsColor.redComponent * 255).rounded()) & 0xFF
        let g = UInt32((nsColor.greenComponent * 255).rounded()) & 0xFF
        let b = UInt32((nsColor.blueComponent * 255).rounded()) & 0xFF
        return (r << 16) | (g << 8) | b
    }
}
#endif
