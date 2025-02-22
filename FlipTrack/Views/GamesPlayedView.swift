import SwiftUI

struct GamesPlayedView: View {
    let games: [Game]
    let formattedNumber: (Int) -> String
    let winningColor: (Game) -> Color
    let colorFor: (Int) -> Color
    
    @FocusState private var editFocus: Bool
    @State var editGame: Game? = nil
    @State var editScoreIndex = 0
    
    func bgColor(_ game: Game) -> (AnyView) -> AnyView {
        winningColor(game).mix(with: .black, by: 0.5).asBackground()
    }
    
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
        if game.scores[index] == hs[index] { return Color.gold }
        return .white
    }
    
    func isHighestScore(_ game: Game, _ index: Int) -> Bool {
        guard let session = game.session else { return false }
        let hs = session.highScores
        return game.scores[index] == max(hs[0], hs[1])
    }
    
    var sortedGames: [Game] { games.sorted(using: SortDescriptor(\Game.nr)).reversed() }
    
    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "GAMES")
            ScrollView(.vertical) {
                ScrollViewReader { scrollReader in
                    ForEach(sortedGames) { game in
                        VStack(spacing: 0) {
                            PrefixedRow(background1: bgColor(game), background2: bgColor(game), column1: {
                                Text("\(game.nr)").font(.title3).padding(6)
                            }, column2: {
                                HStack {
                                    Spacer()
                                    if isHighestScore(game, 0) {
                                        Image(systemName: "star.fill")
                                            .foregroundColor(Color.gold)
                                    }
                                    Text(formattedNumber(game.scores[0]))
                                        .foregroundStyle(textColor(game, 0))
                                        .onTapGesture(count: 2) {
                                            startEdit(game, 0)
                                        }
                                }
                                .font(.title3)
                                .padding(6)
                            }, column3: {
                                HStack {
                                    Spacer()
                                    if isHighestScore(game, 1) {
                                        Image(systemName: "star.fill")
                                            .foregroundColor(Color.gold)
                                    }
                                    Text(formattedNumber(game.scores[1]))
                                        .foregroundStyle(textColor(game, 1))
                                        .onTapGesture(count: 2) { startEdit(game, 1) }
                                        .padding(.trailing, 6)
                                }
                                .font(.title3)
                                .padding(6)
                            })
                        }
                        .padding(.bottom, -6)
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
