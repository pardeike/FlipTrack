import SwiftUI

struct TotalsView: View {
    let playerTotals: [Int]
    let playerWins: [Int]
    let colorFor: (Int) -> Color
    let formattedNumber: (Int) -> String
    let gold: Color

    private var playerTotalIndex: Int {
        playerTotals[0] == playerTotals[1] ? -1 : (playerTotals[0] > playerTotals[1] ? 0 : 1)
    }

    private var playerWinIndex: Int {
        playerWins[0] == playerWins[1] ? -1 : (playerWins[0] > playerWins[1] ? 0 : 1)
    }

    private var background1: [Color] { [.clear, gold, .clear] }
    private var background2: [Color] { [.clear, .clear, gold] }

    var body: some View {
        Grid(alignment: .center) {
            GridRow {
                Text("TOTALS")
                    .font(.headline)
                    .foregroundColor(.gray)
                    .padding(6)
                    .gridCellColumns(2)
            }
            GridRow {
                Text("Andreas")
                    .foregroundColor(colorFor(0))
                Text("Fredrik")
                    .foregroundColor(colorFor(1))
            }
            .font(.headline)
            .bold()
            .frame(maxWidth: .infinity)
            .padding(.bottom, 6)
            GridRow {
                Text(formattedNumber(playerTotals[0]))
                    .foregroundColor(colorFor(0))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(background1[playerTotalIndex + 1])
                Text(formattedNumber(playerTotals[1]))
                    .foregroundColor(colorFor(1))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(background2[playerTotalIndex + 1])
            }
            .font(.title2)
            GridRow {
                Text("#\(playerWins[0])")
                    .foregroundColor(colorFor(0))
                    .font(.title)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(background1[playerWinIndex + 1])
                Text("#\(playerWins[1])")
                    .foregroundColor(colorFor(1))
                    .font(.title)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(background2[playerWinIndex + 1])
            }
        }
        .background(Color(white: 0.1))
        .padding(.bottom, 20)
    }
}

#Preview {
    TotalsView(playerTotals: [1000, 2000],
               playerWins: [33, 22],
               colorFor: { [Color.red, Color.green][$0] },
               formattedNumber: { "(\($0))" },
               gold: .yellow)
    .preferredColorScheme(.dark)
}
