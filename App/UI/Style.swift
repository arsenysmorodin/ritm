import SwiftUI

// Dark aubergine, lavender highlights and apricot used only for action or effort.
enum Ink {
    static let paper = Color(red: 0.066, green: 0.060, blue: 0.100)
    static let panel = Color(red: 0.108, green: 0.098, blue: 0.156)
    static let raised = Color(red: 0.157, green: 0.141, blue: 0.220)
    static let line = Color.white.opacity(0.105)
    static let primary = Color(red: 0.975, green: 0.954, blue: 1)
    static let muted = Color(red: 0.685, green: 0.661, blue: 0.759)
    static let lilac = Color(red: 0.851, green: 0.799, blue: 1)
    static let peach = Color(red: 1, green: 0.766, blue: 0.660)
    static let onAccent = Color(red: 0.147, green: 0.101, blue: 0.205)
}

struct Page<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        #if RITM_PREVIEW
        contentLayout.fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: .infinity, alignment: .top).clipped()
            .background(Ink.paper)
        #else
        ScrollView { contentLayout }
            .scrollIndicators(.hidden)
            .background(Ink.paper.ignoresSafeArea())
        #endif
    }

    private var contentLayout: some View {
        VStack(alignment: .leading, spacing: 22) { content }
            .frame(maxWidth: 560)
            .padding(.horizontal, 21)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    let caption: String
    @ViewBuilder var trailing: Trailing
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 39.0

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: titleSize, weight: .semibold)).tracking(-1.7).accessibilityAddTraits(.isHeader)
                Text(caption).font(.subheadline).foregroundStyle(Ink.muted)
            }
            Spacer(minLength: 4)
            trailing
        }
    }
}

struct Panel<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.panel, in: RoundedRectangle(cornerRadius: 19))
            .overlay { RoundedRectangle(cornerRadius: 19).strokeBorder(Ink.line, lineWidth: 1).allowsHitTesting(false) }
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    var solid = true
    var color = Ink.lilac
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(solid ? Ink.onAccent : color)
                .frame(maxWidth: .infinity, minHeight: 49)
                .padding(.horizontal, 12)
                .background(solid ? color : Ink.raised, in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(PressStyle())
        .opacity(enabled ? 1 : 0.47)
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.76 : 1)
            .contentShape(Rectangle())
    }
}

struct IconBadge: View {
    var icon: String
    var color = Ink.lilac
    var size: CGFloat = 43
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: size * 0.30))
            .accessibilityHidden(true)
    }
}

struct SectionHeading: View {
    let title: String
    var body: some View {
        Text(title).font(.title3.weight(.semibold)).tracking(-0.35).accessibilityAddTraits(.isHeader)
    }
}

struct HintPanel: View {
    let icon: String
    let title: String
    let text: String
    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 9) {
                IconBadge(icon: icon)
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension View {
    func numericKeyboard(decimal: Bool = false) -> some View {
        #if os(iOS)
        self.keyboardType(decimal ? .decimalPad : .numberPad)
        #else
        self
        #endif
    }

    func editAutocorrection() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.sentences)
        #else
        self
        #endif
    }

    func formTint() -> some View {
        self.scrollContentBackground(.hidden).background(Ink.paper.ignoresSafeArea()).tint(Ink.lilac)
    }
}

extension WorkoutKind {
    var color: Color {
        switch self { case .strength: Ink.lilac; case .mobility: Color(red: 0.71, green: 0.91, blue: 0.83); case .intervals: Ink.peach }
    }
}

enum Format {
    static let russian = Locale(identifier: "ru_RU")
    static func integer(_ value: Int) -> String { value.formatted(.number.locale(russian)) }
    static func weight(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2)).locale(russian)) }
    static func date(_ value: Date, year: Bool = false) -> String {
        let style = Date.FormatStyle().day().month(.wide).locale(russian)
        return value.formatted(year ? style.year() : style)
    }
    static func clock(_ seconds: Int) -> String { String(format: "%02d:%02d", max(0, seconds) / 60, max(0, seconds) % 60) }
    static func duration(_ seconds: Int) -> String { seconds < 60 ? "\(seconds) сек" : "\(seconds / 60) мин" }
    static func count(_ value: Int, _ forms: (String, String, String)) -> String {
        let last = value % 10
        let word = (11...14).contains(value % 100) ? forms.2 : last == 1 ? forms.0 : (2...4).contains(last) ? forms.1 : forms.2
        return "\(value) \(word)"
    }
    static func exercises(_ count: Int) -> String { self.count(count, ("упражнение", "упражнения", "упражнений")) }
    static func sets(_ count: Int) -> String { self.count(count, ("подход", "подхода", "подходов")) }
    static func workouts(_ count: Int) -> String { self.count(count, ("тренировка", "тренировки", "тренировок")) }
}
