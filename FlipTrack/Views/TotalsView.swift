import SwiftUI

public struct TotalsView: View {
    public let playerTotals: [Int]
    public let playerWins: [Int]
    public let highScores: [Int]
    public let averageScores: [Int]
    public let colorFor: (Int) -> Color
    public let formattedNumber: (Int) -> String

    private var playerTotalIndex: Int {
        playerTotals[0] == playerTotals[1] ? -1 : (playerTotals[0] > playerTotals[1] ? 0 : 1)
    }

    private var playerWinIndex: Int {
        playerWins[0] == playerWins[1] ? -1 : (playerWins[0] > playerWins[1] ? 0 : 1)
    }
    
    func highestScoreIndex() -> Int {
        let hs = highScores
        if hs[0] == hs[1] { return -1 }
        return hs[0] > hs[1] ? 0 : 1
    }
    
    func averageScoreIndex() -> Int {
        let avg = averageScores
        if avg[0] == avg[1] { return -1 }
        return avg[0] > avg[1] ? 0 : 1
    }

    private let bgColor: (AnyView) -> AnyView = Color(white: 0.1).asBackground()
    private var background1: [Color] { [.clear, Color.highlight, .clear] }
    private var background2: [Color] { [.clear, .clear, Color.highlight] }

    public init(playerTotals: [Int], playerWins: [Int], highScores: [Int], averageScores: [Int], colorFor: @escaping (Int) -> Color, formattedNumber: @escaping (Int) -> String) {
        self.playerTotals = playerTotals
        self.playerWins = playerWins
        self.highScores = highScores
        self.averageScores = averageScores
        self.colorFor = colorFor
        self.formattedNumber = formattedNumber
    }

    public var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "STATS")
            // players
            PrefixedRow(background1: bgColor, background2: bgColor, column1: {
                Text(" ")
            }, column2: {
                HStack {
                    Spacer()
                    Text("Andreas")
                        .foregroundColor(colorFor(0))
                        .font(.headline)
                        .bold()
                        .padding(.trailing, 6)
                }
            }, column3: {
                HStack {
                    Spacer()
                    Text("Fredrik")
                        .foregroundColor(colorFor(1))
                        .font(.headline)
                        .padding(.trailing, 6)
                        .bold()
                }
            })
            // games
            PrefixedRow(background1: bgColor, background2: bgColor, column1: {
                Text("#").bold()
                    .foregroundStyle(Color.gold)
                    .font(.title2)
            }, column2: {
                HStack {
                    Spacer()
                    Text("\(playerWins[0])")
                        .foregroundColor(colorFor(0))
                        .padding(.vertical, 2)
                        .padding(.trailing, 6)
                        .font(.title2)
                }
                .if(playerWinIndex == 0) { $0.frame(maxWidth: .infinity).goldShine() }
            }, column3: {
                HStack {
                    Spacer()
                    Text("\(playerWins[1])")
                        .foregroundColor(colorFor(1))
                        .padding(.vertical, 2)
                        .padding(.trailing, 6)
                        .font(.title2)
                }
                .if(playerWinIndex == 1) { $0.frame(maxWidth: .infinity).goldShine() }
            })
            // highest
            PrefixedRow(background1: bgColor, background2: bgColor, column1: {
                Image(systemName: "star.fill")
                    .foregroundStyle(Color.gold)
            }, column2: {
                HStack {
                    Spacer()
                    Text(formattedNumber(highScores[0]))
                        .bold()
                        .foregroundColor(colorFor(0))
                        .padding(.vertical, 6)
                        .padding(.trailing, 6)
                        .font(.title2)
                }
                .if(highestScoreIndex() == 0) { $0.frame(maxWidth: .infinity).goldShine() }
            }, column3: {
                HStack {
                    Spacer()
                    Text(formattedNumber(highScores[1]))
                        .bold()
                        .foregroundColor(colorFor(1))
                        .padding(.vertical, 6)
                        .padding(.trailing, 6)
                        .font(.title2)
                }
                .if(highestScoreIndex() == 1) { $0.frame(maxWidth: .infinity).goldShine() }
            })
            // total
            PrefixedRow(background1: bgColor, background2: bgColor, column1: {
                Image(systemName: "sum")
                    .fontWeight(.heavy).foregroundStyle(Color.gold)
            }, column2: {
                HStack {
                    Spacer()
                    Text(formattedNumber(playerTotals[0]))
                        .foregroundColor(colorFor(0))
                        .padding(.vertical, 6)
                        .padding(.trailing, 6)
                        .font(.title2)
                }
                .if(playerTotalIndex == 0) { $0.frame(maxWidth: .infinity).goldShine() }
            }, column3: {
                HStack {
                    Spacer()
                    Text(formattedNumber(playerTotals[1]))
                        .foregroundColor(colorFor(1))
                        .padding(.vertical, 6)
                        .padding(.trailing, 6)
                        .font(.title2)
                }
                .if(playerTotalIndex == 1) { $0.frame(maxWidth: .infinity).goldShine() }
            })
            // average
            PrefixedRow(background1: bgColor, background2: bgColor, column1: {
                Image(systemName: "divide")
                    .fontWeight(.heavy).foregroundStyle(Color.gold)
            }, column2: {
                HStack {
                    Spacer()
                    Text("~ " + formattedNumber(averageScores[0]))
                        .foregroundColor(colorFor(0))
                        .padding(.vertical, 6)
                        .padding(.trailing, 6)
                        .font(.title2)
                }
                .if(averageScoreIndex() == 0) { $0.frame(maxWidth: .infinity).goldShine() }
            }, column3: {
                HStack {
                    Spacer()
                    Text("~ " + formattedNumber(averageScores[1]))
                        .foregroundColor(colorFor(1))
                        .padding(.vertical, 6)
                        .padding(.trailing, 6)
                        .font(.title2)
                }
                .if(averageScoreIndex() == 1) { $0.frame(maxWidth: .infinity).goldShine() }
            })
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
               formattedNumber: { "(\($0))" })
    .preferredColorScheme(.dark)
}
