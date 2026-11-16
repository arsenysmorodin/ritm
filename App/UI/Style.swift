import SwiftUI

struct Page<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        #if RITM_PREVIEW
        contentLayout.fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: .infinity, alignment: .top).clipped()
            .background(Theme.background)
        #else
        ScrollView { contentLayout }
            .scrollIndicators(.hidden)
            .background(Theme.background.ignoresSafeArea())
        #endif
    }

    private var contentLayout: some View {
        VStack(alignment: .leading, spacing: Theme.Space.section) { content }
            .frame(maxWidth: Theme.contentWidth)
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.top, Theme.Space.md)
            .padding(.bottom, Theme.Space.section)
            .frame(maxWidth: .infinity)
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    let caption: String
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.sm))
            : AnyLayout(HStackLayout(spacing: Theme.Space.md))
        layout {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(title).font(Theme.screenTitle).accessibilityAddTraits(.isHeader)
                Text(caption).font(.subheadline).foregroundStyle(Theme.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
    }
}

struct Panel<Content: View>: View {
    var padding: CGFloat = Theme.Space.lg
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.panel).strokeBorder(Theme.border).allowsHitTesting(false)
            }
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    var solid = true
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(.subheadline, weight: .semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(solid && enabled ? Theme.onAccent : enabled ? Theme.primary : Theme.secondary)
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, Theme.Space.sm)
                .frame(maxWidth: .infinity, minHeight: Theme.actionHeight)
                .background(solid && enabled ? Theme.accent : Theme.elevated, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
        }
        .buttonStyle(PressStyle())
    }
}

struct ActionDock<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: Theme.Space.sm) { content }
            .frame(maxWidth: Theme.contentWidth)
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.vertical, Theme.Space.sm)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)
            .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1).accessibilityHidden(true) }
    }
}

struct MetricValue: View {
    let title: String
    let value: String
    var prominence = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title).font(.subheadline).foregroundStyle(Theme.secondary)
            Text(value).font(Theme.metric).foregroundStyle(prominence ? Theme.accent : Theme.primary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct StatusMessage: View {
    let text: String
    var loading = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            if loading {
                SwiftUI.ProgressView().accessibilityHidden(true)
            } else {
                Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.warning).accessibilityHidden(true)
            }
            Text(text).font(.subheadline).foregroundStyle(Theme.primary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.76 : 1)
            .contentShape(Rectangle())
    }
}

let exerciseQuantityRange = 1...3600

struct RepetitionControl<Count: View>: View {
    let value: Int?
    let context: String
    let adjust: (Int) -> Void
    @ViewBuilder var count: Count

    var body: some View {
        HStack(spacing: 2) {
            button("minus", label: "Убавить повтор", change: -1)
                .disabled(value == exerciseQuantityRange.lowerBound)
            count.monospacedDigit()
            button("plus", label: "Добавить повтор", change: 1)
                .disabled(value == exerciseQuantityRange.upperBound)
        }
        .fixedSize(horizontal: true, vertical: false)
        .buttonRepeatBehavior(.enabled)
    }

    private func button(_ icon: String, label: String, change: Int) -> some View {
        let atLimit = value == (change < 0 ? exerciseQuantityRange.lowerBound : exerciseQuantityRange.upperBound)
        return Button { adjust(change) } label: {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(atLimit ? Theme.secondary : Theme.primary)
                .frame(width: Theme.touch, height: Theme.touch)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.control)
                        .strokeBorder(Theme.border).allowsHitTesting(false)
                }
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(label), \(context)")
    }
}

struct RepetitionField: View {
    @Binding var text: String
    var label = "Повторы"
    @ScaledMetric(relativeTo: .body) private var fieldWidth = 50.0
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        let value = Int(text.trimmed)
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.sm))
            : AnyLayout(HStackLayout(spacing: Theme.Space.xs))
        layout {
            Text("Повторы").frame(maxWidth: .infinity, alignment: .leading)
            RepetitionControl(value: value, context: label, adjust: adjust) {
                TextField("—", text: $text)
                    .numericKeyboard()
                    .multilineTextAlignment(.center)
                    .frame(width: fieldWidth)
                    .accessibilityLabel(label)
            }
        }
    }

    private func adjust(by change: Int) {
        let value = Int(text.trimmed) ?? 0
        let (next, overflow) = value.addingReportingOverflow(change)
        let bounded = overflow ? value : next
        text = String(min(max(bounded, exerciseQuantityRange.lowerBound), exerciseQuantityRange.upperBound))
    }
}

struct IconBadge: View {
    var icon: String
    var color = Theme.secondary
    var size: CGFloat = Theme.touch
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .accessibilityHidden(true)
    }
}

struct SectionHeading: View {
    let title: String
    var body: some View {
        Text(title).font(Theme.sectionTitle).accessibilityAddTraits(.isHeader)
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
                Text(text).font(.subheadline).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
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
        self.tint(Theme.accent)
    }
}

extension WorkoutKind {
    var color: Color {
        switch self { case .strength: Theme.primary; case .mobility: Theme.reference; case .intervals: Theme.secondary }
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
    static func clock(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    static func spokenTime(_ seconds: Int) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar.current
        calendar.locale = russian
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.hour, .minute, .second]
        return formatter.string(from: TimeInterval(max(0, seconds))) ?? "\(seconds) сек"
    }
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
