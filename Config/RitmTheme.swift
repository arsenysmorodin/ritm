import SwiftUI

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
