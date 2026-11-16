import SwiftUI

struct TechniqueCard: View {
    let preset: ExercisePreset
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        let frames = ExerciseTechnique.frames(for: preset.id)
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "Техника")
                layout {
                    ForEach(frames.indices, id: \.self) { index in
                        let frame = frames[index]
                        VStack(spacing: 7) {
                            TechniqueDrawing(frame: frame)
                            Text(frame.label)
                                .font(.caption.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(Theme.primary)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                        .accessibilityElement(children: .combine)
                    }
                }
                Text(preset.hint)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct TechniqueDrawing: View {
    @Environment(\.ritmAccent) private var accent
    let frame: TechniqueFrame

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 110, size.height / 100)
            let offset = CGPoint(x: (size.width - scale * 110) / 2, y: (size.height - scale * 100) / 2)
            func point(_ p: Joint) -> CGPoint { CGPoint(x: offset.x + p.x * scale, y: offset.y + p.y * scale) }
            func line(_ joints: [Joint], color: Color, width: Double) {
                guard let first = joints.first else { return }
                let path = Path { p in
                    p.move(to: point(first))
                    for joint in joints.dropFirst() { p.addLine(to: point(joint)) }
                }
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width * scale, lineCap: .round, lineJoin: .round))
            }

            line([(7, 94), (103, 94)], color: Theme.border, width: 1)
            for prop in frame.props { line(prop, color: Theme.secondary, width: 2.4) }
            if let band = frame.band { line(band, color: accent, width: 1.5) }
            line(frame.pose.rearLeg, color: Theme.secondary, width: 4)
            line(frame.pose.rearArm, color: Theme.secondary, width: 3.6)
            line(frame.pose.torso, color: Theme.reference, width: 8)
            line(frame.pose.frontLeg, color: Theme.reference, width: 4.6)
            line(frame.pose.frontArm, color: Theme.reference, width: 4)
            let head = point(frame.pose.head)
            context.fill(Path(ellipseIn: CGRect(x: head.x - 5.3 * scale, y: head.y - 5.3 * scale,
                                                width: 10.6 * scale, height: 10.6 * scale)), with: .color(Theme.reference))
            if frame.hasWeights {
                for hand in [frame.pose.rearArm.last, frame.pose.frontArm.last].compactMap({ $0 }) {
                    line([(hand.x - 3.7, hand.y), (hand.x + 3.7, hand.y)], color: Theme.primary, width: 2.4)
                }
            }
        }
        .frame(minHeight: 94, idealHeight: 116, maxHeight: 116)
        .accessibilityHidden(true)
    }
}
