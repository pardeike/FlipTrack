import SwiftUI

struct GamesPlayedView: View {
    let games: [Game]
    let formattedNumber: (Int) -> String
    let winningColor: (Game) -> Color

    private var columns: [GridItem] {
        [
            GridItem(.fixed(50), spacing: 0, alignment: .trailing),
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 0, alignment: .trailing),
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 0, alignment: .trailing)
        ]
    }

    var body: some View {
        VStack {
            Grid(alignment: .center) {
                GridRow {
                    Text("GAMES PLAYED")
                        .font(.headline)
                        .foregroundColor(.gray)
                        .padding(6)
                        .gridCellColumns(3)
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color(white: 0.1))
            ScrollView(.vertical) {
                LazyVGrid(columns: columns) {
                    Text("#").padding(.trailing, 4)
                    Text("Andreas").padding(.trailing, 4)
                    Text("Fredrik").padding(.trailing, 10)
                    ForEach(Array(games.enumerated()), id: \.element.id) { _, game in
                        Group {
                            HStack {
                                Spacer()
                                Text("\(game.nr)")
                            }
                            HStack {
                                Spacer()
                                if game.winningIndex == 0 {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.yellow)
                                }
                                Text(formattedNumber(game.scores[0]))
                            }
                            HStack {
                                Spacer()
                                if game.winningIndex == 1 {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.yellow)
                                }
                                Text(formattedNumber(game.scores[1]))
                                    .padding(.trailing, 6)
                            }
                        }
                        .padding(6)
                        .background(winningColor(game).opacity(0.25))
                    }
                }
                .font(.title2)
            }
            .background(Color(white: 0.1))
            .defaultScrollAnchor(.bottom)
            .scrollIndicators(.hidden)
            .padding(.bottom, 20)
        }
    }
}

#Preview {
    GamesPlayedView(games: EventViewModel.sampleGames,
                    formattedNumber: { "\($0)" },
                    winningColor: { [Color.red, Color.green][$0.winningIndex] })
    .preferredColorScheme(.dark)
    
}
