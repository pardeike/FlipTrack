import SwiftUI

struct ScoreEditView: View {
    let game: Game
    let scoreIndex: Int
    let numberFormatter: NumberFormatter
    let done: () -> Void
    
    @State private var editedScore = ""
    @FocusState var focus: Bool
    
    var formatted: String {
        let num = NSNumber(value: game.scores[scoreIndex])
        return numberFormatter.string(from: num) ?? ""
    }
    
    var body: some View {
        VStack(alignment: .center) {
            Text(formatted)
                .bold()
                .foregroundStyle(.red)
                .padding(.top, 16)
            TextField("Score", text: $editedScore)
                .bold()
                .focused($focus)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .presentationDetents([.height(160)])
                .presentationDragIndicator(.hidden)
                .onAppear() {
                    focus = true
                }
            Button(" Save ") {
                if let newScore = Int(editedScore), newScore > 0, game.scores[scoreIndex] != newScore {
                    game.scores[scoreIndex] = newScore
                    try? game.modelContext?.save()
                }
                done()
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .padding(.top, 16)
        }
        .font(.title)
        .onAppear {
            editedScore = String(game.scores[scoreIndex])
        }
    }
}

struct GamesPlayedView: View {
    @Environment(\.modelContext) private var context
    
    let games: [Game]
    let formattedNumber: (Int) -> String
    let winningColor: (Game) -> Color
    
    @FocusState private var editFocus: Bool
    @State var editGame: Game? = nil
    @State var editScoreIndex = 0
    @State var isEditing = false
    
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
        editGame = game
        editScoreIndex = scoreIndex
        isEditing = true
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
                    ForEach(games.sorted(using: SortDescriptor(\Game.nr))) { game in
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
                                    .onTapGesture(count: 2) {
                                        startEdit(game, 0)
                                    }
                            }
                            HStack {
                                Spacer()
                                if game.winningIndex == 1 {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.yellow)
                                }
                                Text(formattedNumber(game.scores[1]))
                                    .onTapGesture(count: 2) { startEdit(game, 1) }
                                    .padding(.trailing, 6)
                            }
                        }
                        .padding(6)
                        .background(winningColor(game).opacity(0.25))
                        .gesture(
                            LongPressGesture(minimumDuration: UIDevice.isSimulator ? 0.25 : 3)
                                .onEnded { _ in
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
        .sheet(isPresented: $isEditing) {
            ScoreEditView(
                game: editGame ?? Game(),
                scoreIndex: editScoreIndex,
                numberFormatter: numberFormatter,
                done: { isEditing = false }
            )
        }
    }
}

#Preview {
    let games = [
        Game(nr: 1, scores: [12000, 32720], session: Session(date: Date.now )),
        Game(nr: 2, scores: [480230, 19260], session: Session(date: Date.now.addingTimeInterval(24 * 3600))),
    ]
    GamesPlayedView(games: games, formattedNumber: { "\($0)" }, winningColor: { [Color.clear, Color.red, Color.green][$0.winningIndex + 1] })
    .preferredColorScheme(.dark)
    
}
