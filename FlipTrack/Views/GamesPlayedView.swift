import SwiftUI

struct GamesPlayedView: View {
    let games: [Game]
    let formattedNumber: (Int) -> String
    let winningColor: (Game) -> Color
    let colorFor: (Int) -> Color
    
    @FocusState private var editFocus: Bool
    @State var editGame: Game? = nil
    @State var editScoreIndex = 0
    
    let numberFormatter = ({
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        return formatter
    })()

    var columns: [GridItem] {[
        GridItem(.fixed(50), spacing: 0, alignment: .trailing),
        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 0, alignment: .trailing),
        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 0, alignment: .trailing)
    ]}
    
    func startEdit(_ game: Game, _ scoreIndex: Int) {
        editScoreIndex = scoreIndex
        editGame = game
    }
    
    func textColor(_ game: Game, _ index: Int) -> Color {
        guard let session = game.session else { return .white }
        let hs = session.highScores
        if game.scores[index] == hs[index] { return .yellow }
        return .white
    }
    
    func isHighestScore(_ game: Game, _ index: Int) -> Bool {
        guard let session = game.session else { return false }
        let hs = session.highScores
        return game.scores[index] == max(hs[0], hs[1])
    }
    
    var sortedGames: [Game] { games.sorted(using: SortDescriptor(\Game.nr)).reversed() }
    
    var body: some View {
        VStack {
            Grid(alignment: .center) {
                GridRow {
                    Text("GAMES")
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
                ScrollViewReader { scrollReader in
                    LazyVGrid(columns: columns) {
                        ForEach(sortedGames) { game in
                            Group {
                                HStack {
                                    Spacer()
                                    Text("\(game.nr)")
                                }
                                HStack {
                                    Spacer()
                                    if isHighestScore(game, 0) {
                                        Image(systemName: "star.fill")
                                            .foregroundColor(.yellow)
                                    }
                                    Text(formattedNumber(game.scores[0]))
                                        .foregroundStyle(textColor(game, 0))
                                        .onTapGesture(count: 2) {
                                            startEdit(game, 0)
                                        }
                                }
                                HStack {
                                    Spacer()
                                    if isHighestScore(game, 1) {
                                        Image(systemName: "star.fill")
                                            .foregroundColor(.yellow)
                                    }
                                    Text(formattedNumber(game.scores[1]))
                                        .foregroundStyle(textColor(game, 1))
                                        .onTapGesture(count: 2) { startEdit(game, 1) }
                                        .padding(.trailing, 6)
                                }
                            }
                            .padding(6)
                            .background(winningColor(game).opacity(0.3))
                            .gesture(
                                LongPressGesture(minimumDuration: UIDevice.isSimulator ? 0.25 : 3)
                                    .onEnded { _ in
                                        if let context = game.modelContext {
                                            context.delete(game)
                                            try! context.save()
                                            scrollReader.scrollTo(0)
                                        }
                                    }
                            )
                        }
                    }
                }
                .font(.title3)
            }
            .background(Color(white: 0.1))
            .scrollIndicators(.hidden)
            .padding(.bottom, 20)
        }
        .sheet(item: $editGame) {
            ScoreEditView(
                game: $0,
                scoreIndex: editScoreIndex,
                numberFormatter: numberFormatter,
                done: { editGame = nil }
            )
        }
    }
}

#Preview {
    let games = [
        Game(nr: 1, scores: [12000, 32720], session: Session(date: Date.now )),
        Game(nr: 2, scores: [480230, 19260], session: Session(date: Date.now.addingTimeInterval(24 * 3600))),
    ]
    GamesPlayedView(
        games: games,
        formattedNumber: { "\($0)" },
        winningColor: { [Color.clear, Color.red, Color.green][$0.winningIndex + 1] },
        colorFor: { [Color.red, Color.green][$0] }
    )
    .preferredColorScheme(.dark)
}
