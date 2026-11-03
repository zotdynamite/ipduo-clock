import Foundation

/// Accent choices stored by name so the setting survives relaunch and can be renamed with the app.
public enum AccentPalette: String, Codable, CaseIterable, Identifiable {
    case aurora
    case sunrise
    case tide
    case blossom
    case ember
    case graphite

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .aurora: return "Aurora"
        case .sunrise: return "Sunrise"
        case .tide: return "Tide"
        case .blossom: return "Blossom"
        case .ember: return "Ember"
        case .graphite: return "Graphite"
        }
    }

    /// sRGB components in 0...1.
    public var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .aurora: return (0.45, 0.78, 0.72)
        case .sunrise: return (0.93, 0.55, 0.38)
        case .tide: return (0.36, 0.55, 0.86)
        case .blossom: return (0.86, 0.48, 0.62)
        case .ember: return (0.89, 0.42, 0.31)
        case .graphite: return (0.55, 0.57, 0.60)
        }
    }
}

public enum ClockFaceID: String, Codable, CaseIterable, Identifiable {
    case analog
    case digital
    case flip
    case ambient

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .analog: return "Analog"
        case .digital: return "Digital"
        case .flip: return "Flip"
        case .ambient: return "Ambient"
        }
    }
}

public enum AppearanceChoice: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}
