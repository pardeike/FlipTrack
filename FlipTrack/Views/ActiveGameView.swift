import SwiftUI

struct ActiveGameView: View {
    let display: ActiveGameDisplay
    let tracking: Bool
    let formattedNumber: (Int) -> String
    let colorFor: (Int) -> Color
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .headline) private var scoreSize = 19.0

    var body: some View {
        Group {
            if display.missingFinals {
                Text("Add the previous game's final scores")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    player(slot: 1, name: display.leftName, score: display.left, person: display.leftPerson)
                    ball
                    player(slot: 2, name: display.rightName, score: display.right, person: 1-display.leftPerson)
                }
                .padding(8)
            }
        }
        .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 16))
    }

    private func player(slot: Int, name: String, score: Int?, person: Int) -> some View {
        let active = tracking && display.turn?.slot == slot
        return VStack(alignment: slot == 1 ? .leading : .trailing, spacing: 3) {
            Text(name.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(colorFor(person))
            Text(score.map(formattedNumber) ?? "—")
                .font(.system(size: scoreSize, weight: .semibold).monospacedDigit())
                .foregroundStyle(active ? Color.primary : Color.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.65)
        .frame(maxWidth: .infinity, alignment: slot == 1 ? .leading : .trailing)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color(white: active ? 0.19 : 0.13), in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(active ? Color.white : .clear, lineWidth: 1.5) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(slot == 1 ? "Left" : "Right"), \(name), \(score.map { String($0) } ?? "score unknown")\(active ? ", playing" : "")\(display.uncertain ? ", tracking uncertain" : "")")
        .accessibilityIdentifier("liveScore\(slot)")
    }

    private var ball: some View {
        VStack(spacing: 5) {
            Text("BALL").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            if let turn = display.turn {
                HStack(spacing: 4) {
                    ForEach(1...3, id: \.self) { number in
                        Circle()
                            .fill(number <= turn.ball ? Color(white: 0.8) : Color(white: 0.25))
                            .frame(width: 7, height: 7)
                            .overlay { if number == turn.ball { Circle().stroke(.white, lineWidth: 1.2).padding(-2.5) } }
                    }
                }
                .frame(height: 12)
            } else {
                Text(display.uncertain ? "?" : "—").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(display.turn.map { "Ball \($0.ball)" } ?? "Ball unknown")
        .accessibilityIdentifier("liveBall")
    }
}
