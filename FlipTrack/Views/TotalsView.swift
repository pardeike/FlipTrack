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

    func fgColor(_ idx: Int, _ player: Int) -> Color {
        if idx == player { return .yellow }
        return .white
    }
    
    var bgColor: (AnyView) -> AnyView { Color(white: 0.1).asBackground() }
    var bg1: Color { colorFor(0).mix(with: .black, by: 0.5) }
    var bg2: Color { colorFor(1).mix(with: .black, by: 0.5) }

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
            SectionHeader(title: "STATS").padding(.bottom, -8)
            // players
            PrefixedRow(background1: bgColor, background2: bgColor, column1: {
                Text("")
            }, column2: {
                HStack {
                    Spacer()
                    Text("Andreas")
                        .padding(.vertical, 2)
                        .padding(.trailing, 6)
                        .font(.title3)
                }
            }, column3: {
                HStack {
                    Spacer()
                    Text("Fredrik")
                        .padding(.vertical, 2)
                        .padding(.trailing, 6)
                        .font(.title3)
                }
            })
            
            // games
            PrefixedRow(background1: bgColor, background2: bgColor, column1: {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(.yellow)
            }, column2: {
                HStack {
                    Spacer()
                    Text("\(playerWins[0])")
                        .foregroundColor(fgColor(playerWinIndex, 0))
                        .padding(.vertical, 6)
                        .padding(.trailing, 6)
                        .font(.title3)
                        .bold()
                }
                .background { bg1 }
            }, column3: {
                HStack {
                    Spacer()
                    Text("\(playerWins[1])")
                        .foregroundColor(fgColor(playerWinIndex, 1))
                        .padding(.vertical, 6)
                        .padding(.trailing, 6)
                        .font(.title3)
                        .bold()
                }
                .background { bg2 }
            })
            .padding(.bottom, 2)
            
            // highest
            PrefixedRow(background1: bgColor, background2: bgColor, column1: {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
            }, column2: {
                HStack {
                    Spacer()
                    Text(formattedNumber(highScores[0]))
                        .foregroundColor(fgColor(highestScoreIndex(), 0))
                        .padding(.vertical, 6)
                        .padding(.trailing, 6)
                        .font(.title3)
                        .bold()
                }
                .background { bg1 }
            }, column3: {
                HStack {
                    Spacer()
                    Text(formattedNumber(highScores[1]))
                        .foregroundColor(fgColor(highestScoreIndex(), 1))
                        .padding(.vertical, 6)
                        .padding(.trailing, 6)
                        .font(.title3)
                        .bold()
                }
                .background { bg2 }
            })
            .padding(.bottom, 2)
            
            // total
            PrefixedRow(background1: bgColor, background2: bgColor, column1: {
                Image(systemName: "sum")
                    .bold()
                    .foregroundStyle(.yellow.opacity(0.75))
            }, column2: {
                HStack {
                    Spacer()
                    Text(formattedNumber(playerTotals[0]))
                        .foregroundColor(fgColor(playerTotalIndex, 0))
                        .padding(.vertical, 6)
                        .padding(.trailing, 6)
                        .font(.title3)
                        .opacity(0.75)
                }
                .background { bg1 }
            }, column3: {
                HStack {
                    Spacer()
                    Text(formattedNumber(playerTotals[1]))
                        .foregroundColor(fgColor(playerTotalIndex, 1))
                        .padding(.vertical, 6)
                        .padding(.trailing, 6)
                        .font(.title3)
                        .opacity(0.75)
                }
                .background { bg2 }
            })
            .padding(.bottom, 2)
            
            // average
            PrefixedRow(background1: bgColor, background2: bgColor, column1: {
                Image(systemName: "divide")
                    .bold()
                    .foregroundStyle(.yellow.opacity(0.75))
            }, column2: {
                HStack {
                    Spacer()
                    Text("~ " + formattedNumber(averageScores[0]))
                        .foregroundColor(fgColor(averageScoreIndex(), 0))
                        .padding(.vertical, 6)
                        .padding(.trailing, 6)
                        .font(.title3)
                        .opacity(0.75)
                }
                .background { bg1 }
            }, column3: {
                HStack {
                    Spacer()
                    Text("~ " + formattedNumber(averageScores[1]))
                        .foregroundColor(fgColor(averageScoreIndex(), 1))
                        .padding(.vertical, 6)
                        .padding(.trailing, 6)
                        .font(.title3)
                        .opacity(0.75)
                }
                .background { bg2 }
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
