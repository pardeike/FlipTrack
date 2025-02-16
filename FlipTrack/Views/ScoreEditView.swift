import SwiftUI

struct ScoreEditView: View {
    let game: Game
    let scoreIndex: Int
    let numberFormatter: NumberFormatter
    let done: () -> Void
    
    @State private var editedScore = ""
    @FocusState var focus: Bool
    
    func formatted(_ game: Game) -> String {
        let num = NSNumber(value: game.scores[scoreIndex])
        return numberFormatter.string(from: num) ?? ""
    }
    
    var body: some View {
        Group {
            VStack(alignment: .center) {
                Text(formatted(game))
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
                    .onAppear() { focus = true }
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
        }
        .onAppear {
            editedScore = String(game.scores[scoreIndex])
        }
    }
}
