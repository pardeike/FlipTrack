import SwiftUI

struct OverviewBalanceBar: View {
    let values: [Int]
    var players = ["Andreas", "Fredrik"]

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(players[0])  \(values[0])").foregroundStyle(Color.color1)
                Spacer()
                Text("\(values[1])  \(players[1])").foregroundStyle(Color.color2)
            }
            .font(.subheadline.weight(.medium).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            if values[0] + values[1] > 0 {
                GeometryReader { geometry in
                    Rectangle().fill(Color.color2.opacity(0.65))
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Color.color1.opacity(0.65))
                                .frame(width: geometry.size.width * CGFloat(values[0]) / CGFloat(values[0] + values[1]))
                        }
                        .clipShape(Capsule())
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }
        }
    }
}
