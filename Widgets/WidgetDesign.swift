import SwiftUI
import WidgetKit

func widgetAccent() -> RitmAccent {
    WidgetStorage.preferences.string(forKey: RitmAccent.widgetKey).flatMap(RitmAccent.init(rawValue:)) ?? .lime
}

struct WidgetPalette {
    let selection: RitmAccent

    var accent: Color { selection.color }
    var primary: Color { selection == .monochrome ? accent : Theme.primary }
    var secondary: Color { selection == .monochrome ? Color("WidgetMonoSecondary") : Theme.secondary }
    var surface: Color { selection == .monochrome ? Color("WidgetMonoSurface") : Theme.surface }
    var elevated: Color { selection == .monochrome ? Color("WidgetMonoElevated") : Theme.elevated }
}

struct WidgetCard<Content: View>: View {
    let palette: WidgetPalette
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(palette.primary)
            .containerBackground(for: .widget) {
                ContainerRelativeShape()
                    .fill(palette.surface)
                    .overlay {
                        ContainerRelativeShape().strokeBorder(palette.secondary.opacity(0.18), lineWidth: 1)
                    }
            }
    }
}

struct WidgetHeader: View {
    let title: String
    let icon: String
    let palette: WidgetPalette
    var context: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 20, height: 20)
                .foregroundStyle(palette.accent)
                .background(palette.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 5))
                .widgetAccentable()
                .accessibilityHidden(true)
            Text(title).font(.caption.weight(.semibold))
                .lineLimit(1).minimumScaleFactor(0.75)
                .accessibilityAddTraits(.isHeader)
            if let context {
                Spacer(minLength: 2)
                Text(context).font(.caption2).foregroundStyle(palette.secondary)
                    .lineLimit(1).minimumScaleFactor(0.72)
            }
        }
    }
}

struct WidgetNumber: View {
    let value: String
    var unit = ""
    let palette: WidgetPalette
    var size: Font.TextStyle = .largeTitle

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size, design: .monospaced, weight: .semibold))
                .tracking(size == .largeTitle || size == .title ? -0.8 : -0.2)
                .minimumScaleFactor(0.57).lineLimit(1)
                .layoutPriority(1)
            if !unit.isEmpty {
                Text(unit).font(.caption2.weight(.medium)).foregroundStyle(palette.secondary)
                    .minimumScaleFactor(0.68).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct WidgetRule: View {
    let palette: WidgetPalette
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle().fill(palette.secondary.opacity(0.24))
            .frame(height: 1 / max(displayScale, 1))
            .accessibilityHidden(true)
    }
}

struct WidgetProgressStrip: View {
    let value: Double
    let total: Double
    let palette: WidgetPalette

    var body: some View {
        let fraction = total > 0 ? min(max(value / total, 0), 1) : 0
        HStack(spacing: 2) {
            ForEach(0..<10) { index in
                let filled = min(max(fraction * 10 - Double(index), 0), 1)
                GeometryReader { cell in
                    RoundedRectangle(cornerRadius: 1).fill(palette.secondary.opacity(0.19))
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1).fill(palette.accent)
                                .frame(width: cell.size.width * filled)
                                .widgetAccentable()
                        }
                }
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

struct WidgetEmpty: View {
    let text: String
    let palette: WidgetPalette

    var body: some View {
        Text(text).font(.caption)
            .foregroundStyle(palette.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

enum WidgetText {
    private static let russian = Locale(identifier: "ru_RU")

    static func number(_ value: Double, fraction: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(0...fraction)).locale(russian))
    }
}
