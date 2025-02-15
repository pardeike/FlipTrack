import SwiftUI

struct GamesPlayedView: View {
    @Environment(\.modelContext) private var context
    
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
            .padding(.bottom, -8)
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
                        .gesture(
                            LongPressGesture(minimumDuration: 2).onEnded { _ in
                                context.delete(game)
                                try! context.save()
                            }
                        )
                    }
                }
                .font(.title3)
            }
            .background(Color(white: 0.1))
            .defaultScrollAnchor(.bottom)
            .scrollIndicators(.hidden)
            .padding(.bottom, 20)
        }
    }
}

#Preview {
    let games = [
        Game(nr: 1, scores: [12000, 32720], session: Session(date: Date.now )),
        Game(nr: 2, scores: [480230, 19260], session: Session(date: Date.now.addingTimeInterval(24 * 3600))),
    ]
    GamesPlayedView(games: games, formattedNumber: { "\($0)" }, winningColor: { [Color.red, Color.green][$0.winningIndex] })
    .preferredColorScheme(.dark)
    
}
