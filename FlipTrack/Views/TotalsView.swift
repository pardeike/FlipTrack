import SwiftUI

struct TotalsView: View {
    let playerTotals: [Int]
    let playerWins: [Int]
    let highScores: [Int]
    let averageScores: [Int]
    let colorFor: (Int) -> Color
    let formattedNumber: (Int) -> String
    var players = ["Andreas", "Fredrik"]

    var body: some View {
        VStack(spacing: 0) {
            stat("Wins", icon: "trophy.fill", values: playerWins, emphasis: true)
            Divider().padding(.vertical, 8)
            stat("Best", icon: "star.fill", values: highScores)
            stat("Total", icon: "sum", values: playerTotals)
                .padding(.top, 10)
            stat("Average", icon: "divide", values: averageScores)
                .padding(.top, 10)
        }
        .padding(14)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private func stat(_ title: String, icon: String, values: [Int], emphasis: Bool = false) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Image(systemName: icon)
                    .foregroundStyle(emphasis ? Color.yellow : .secondary)
                Text(title).font(.caption2)
            }
            .foregroundStyle(.secondary)
            .frame(width: 64, alignment: .leading)
            ForEach(0..<2) { index in
                Text(formattedNumber(values[index]))
                    .font(emphasis ? .title2.weight(.semibold) : .subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(values[index] > values[1 - index] ? colorFor(index) : .primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityLabel("\(players[index]), \(title), \(values[index])")
            }
        }
    }
}

#Preview {
    TotalsView(playerTotals: [243535350, 142530330], playerWins: [3, 2],
               highScores: [131160670, 86549090], averageScores: [48707070, 28506066],
               colorFor: { [Color.color1, Color.color2][$0] }, formattedNumber: { $0.formatted() })
        .padding().preferredColorScheme(.dark)
}
