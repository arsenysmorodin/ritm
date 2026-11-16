import SwiftUI

enum RitmAccent: String, CaseIterable, Identifiable {
    case lime, blue, violet, amber, rose

    static let appKey = "ritm.appearance.accent"
    static let widgetKey = "ritm.widgets.accent"
    var id: Self { self }

    var title: String {
        switch self {
        case .lime: "Лайм"
        case .blue: "Голубой"
        case .violet: "Сиреневый"
        case .amber: "Янтарный"
        case .rose: "Розовый"
        }
    }

    var color: Color {
        self == .lime ? Theme.accent : Color("Accent-" + rawValue)
    }
}

enum RitmAppearance: String, CaseIterable, Identifiable {
    static let key = "ritm.appearance.mode"
    case system, light, dark

    var id: Self { self }
    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var title: String {
        switch self {
        case .system: "Как в iOS"
        case .light: "Светлая"
        case .dark: "Тёмная"
        }
    }
}

private struct RitmAccentKey: EnvironmentKey {
    static let defaultValue = RitmAccent.lime.color
}

extension EnvironmentValues {
    var ritmAccent: Color {
        get { self[RitmAccentKey.self] }
        set { self[RitmAccentKey.self] = newValue }
    }
}

enum Theme {
    static let background = Color("Background")
    static let surface = Color("Surface")
    static let elevated = Color("Elevated")
    static let primary = Color("TextPrimary")
    static let secondary = Color("TextSecondary")
    static let border = Color("Border")
    static let accent = Color("Accent")
    static let onAccent = Color("OnAccent")
    static let warning = Color("Warning")
    static let reference = Color("Reference")

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let gutter: CGFloat = 20
        static let section: CGFloat = 24
    }

    enum Radius {
        static let control: CGFloat = 12
        static let panel: CGFloat = 18
    }

    static let touch: CGFloat = 44
    static let actionHeight: CGFloat = 52
    static let contentWidth: CGFloat = 560

    static let screenTitle = Font.system(.largeTitle, weight: .bold)
    static let sectionTitle = Font.system(.title3, weight: .semibold)
    static let metric = Font.system(.largeTitle, weight: .semibold).monospacedDigit()
    static let timer = Font.system(.title, design: .monospaced, weight: .semibold)
    static let number = Font.system(.title3, weight: .semibold).monospacedDigit()
}
