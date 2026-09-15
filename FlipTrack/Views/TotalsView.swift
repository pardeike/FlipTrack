import SwiftUI

struct TotalsView: View {
    let playerTotals: [Int]
    let highScores: [Int]
    let averageScores: [Int]
    let colorFor: (Int) -> Color
    let formattedNumber: (Int) -> String
    var players = ["Andreas", "Fredrik"]

    var body: some View {
        VStack(spacing: 0) {
            stat("Best", icon: "star.fill", values: highScores)
            stat("Total", icon: "sum", values: playerTotals)
                .padding(.top, 10)
            stat("Average", icon: "divide", values: averageScores)
                .padding(.top, 10)
        }
        .padding(14)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private func stat(_ title: String, icon: String, values: [Int]) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(title).font(.caption2)
            }
            .foregroundStyle(.secondary)
            .frame(width: 72, alignment: .leading)
            ForEach(0..<2) { index in
                Text(formattedNumber(values[index]))
                    .font(.subheadline.weight(.medium))
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
    TotalsView(playerTotals: [243535350, 142530330],
               highScores: [131160670, 86549090], averageScores: [48707070, 28506066],
               colorFor: { [Color.color1, Color.color2][$0] }, formattedNumber: { $0.formatted() })
        .padding().preferredColorScheme(.dark)
}
