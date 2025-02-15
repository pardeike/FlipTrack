import SwiftUI

public struct TotalsView: View {
    public let playerTotals: [Int]
    public let playerWins: [Int]
    public let highScores: [Int]
    public let averageScores: [Int]
    public let colorFor: (Int) -> Color
    public let formattedNumber: (Int) -> String
    public let gold: Color

    private var playerTotalIndex: Int {
        playerTotals[0] == playerTotals[1] ? -1 : (playerTotals[0] > playerTotals[1] ? 0 : 1)
    }

    private var playerWinIndex: Int {
        playerWins[0] == playerWins[1] ? -1 : (playerWins[0] > playerWins[1] ? 0 : 1)
    }
    
    func highestScoreColor(_ idx: Int) -> Color {
        let hs = highScores
        if hs[0] == hs[1] { return .clear }
        return [gold, .clear][hs[idx] > hs[1 - idx] ? 0 : 1]
    }
    
    func averageScoreColor(_ idx: Int) -> Color {
        let avg = averageScores
        if avg[0] == avg[1] { return .clear }
        return [gold, .clear][avg[idx] > avg[1 - idx] ? 0 : 1]
    }

    private var background1: [Color] { [.clear, gold, .clear] }
    private var background2: [Color] { [.clear, .clear, gold] }

    public init(playerTotals: [Int], playerWins: [Int], highScores: [Int], averageScores: [Int], colorFor: @escaping (Int) -> Color, formattedNumber: @escaping (Int) -> String, gold: Color) {
        self.playerTotals = playerTotals
        self.playerWins = playerWins
        self.highScores = highScores
        self.averageScores = averageScores
        self.colorFor = colorFor
        self.formattedNumber = formattedNumber
        self.gold = gold
    }

    public var body: some View {
        VStack {
            Grid(alignment: .center) {
                GridRow {
                    Text("STATS")
                        .font(.headline)
                        .foregroundColor(.gray)
                        .padding(6)
                        .gridCellColumns(3)
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color(white: 0.1))
            .padding(.bottom, -8)
            
            LazyVGrid(columns: [
                GridItem(.fixed(50), spacing: 0, alignment: .center),
                GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 0, alignment: .trailing),
                GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 0, alignment: .trailing)
            ]) {
                Text("")
                Text("Andreas")
                    .foregroundColor(colorFor(0))
                    .font(.headline)
                    .bold()
                    .frame(maxWidth: .infinity)
                Text("Fredrik")
                    .foregroundColor(colorFor(1))
                    .font(.headline)
                    .bold()
                    .frame(maxWidth: .infinity)
                
                // games
                Text("#").bold()
                    .foregroundStyle(.yellow)
                    .font(.title2)
                Text("\(playerWins[0])")
                    .foregroundColor(colorFor(0))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                    .background(background1[playerWinIndex + 1])
                    .font(.title2)
                Text("\(playerWins[1])")
                    .foregroundColor(colorFor(1))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                    .background(background2[playerWinIndex + 1])
                    .font(.title2)
                
                // highest
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                Text(formattedNumber(highScores[0]))
                    .bold()
                    .foregroundColor(colorFor(0))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(highestScoreColor(0))
                    .font(.title2)
                Text(formattedNumber(highScores[1]))
                    .bold()
                    .foregroundColor(colorFor(1))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(highestScoreColor(1))
                    .font(.title2)
                
                // total
                Image(systemName: "sum")
                    .fontWeight(.heavy).foregroundStyle(.yellow)
                Text(formattedNumber(playerTotals[0]))
                    .foregroundColor(colorFor(0))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(background1[playerTotalIndex + 1])
                    .font(.title2)
                Text(formattedNumber(playerTotals[1]))
                    .foregroundColor(colorFor(1))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(background2[playerTotalIndex + 1])
                    .font(.title2)
                
                // average
                Image(systemName: "divide")
                    .fontWeight(.heavy).foregroundStyle(.yellow)
                Text("~ " + formattedNumber(averageScores[0]))
                    .foregroundColor(colorFor(0))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(averageScoreColor(0))
                    .font(.title2)
                Text("~ " + formattedNumber(averageScores[1]))
                    .foregroundColor(colorFor(1))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(averageScoreColor(1))
                    .font(.title2)
            }
            .background(Color(white: 0.1))
            .padding(.bottom, 20)
        }
    }
}

#Preview {
    TotalsView(playerTotals: [1000, 2000],
               playerWins: [33, 22],
               highScores: [4000, 6000],
               averageScores: [2533, 3434],
               colorFor: { [Color.red, Color.green][$0] },
               formattedNumber: { "(\($0))" },
               gold: .yellow)
    .preferredColorScheme(.dark)
}
