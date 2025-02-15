import SwiftUI

public struct TotalsView: View {
    public let playerTotals: [Int]
    public let playerWins: [Int]
    public let highScores: [Int]
    public let colorFor: (Int) -> Color
    public let formattedNumber: (Int) -> String
    public let gold: Color

    private var playerTotalIndex: Int {
        playerTotals[0] == playerTotals[1] ? -1 : (playerTotals[0] > playerTotals[1] ? 0 : 1)
    }

    private var playerWinIndex: Int {
        playerWins[0] == playerWins[1] ? -1 : (playerWins[0] > playerWins[1] ? 0 : 1)
    }
    
    func highestScoreBGColor(_ idx: Int) -> Color {
        let hs = highScores
        if hs[0] == hs[1] { return .clear }
        return [.black, .white][hs[idx] > hs[1 - idx] ? 0 : 1]
    }
    
    func highestScoreColor(_ idx: Int) -> Color {
        let hs = highScores
        if hs[0] == hs[1] { return .clear }
        return [gold, .clear][hs[idx] > hs[1 - idx] ? 0 : 1]
    }

    private var background1: [Color] { [.clear, gold, .clear] }
    private var background2: [Color] { [.clear, .clear, gold] }

    public init(playerTotals: [Int], playerWins: [Int], highScores: [Int], colorFor: @escaping (Int) -> Color, formattedNumber: @escaping (Int) -> String, gold: Color) {
        self.playerTotals = playerTotals
        self.playerWins = playerWins
        self.highScores = highScores
        self.colorFor = colorFor
        self.formattedNumber = formattedNumber
        self.gold = gold
    }

    public var body: some View {
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
                Text(formattedNumber(highScores[0]))
                    .bold()
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(highestScoreColor(0))
                Text(formattedNumber(highScores[1]))
                    .bold()
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(highestScoreColor(1))
            }
            .font(.title2)
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
               highScores: [4000, 6000],
               colorFor: { [Color.red, Color.green][$0] },
               formattedNumber: { "(\($0))" },
               gold: .yellow)
    .preferredColorScheme(.dark)
}
