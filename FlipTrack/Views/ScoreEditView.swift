import SwiftUI

struct ScoreEditView: View {
    let game: Game
    let scoreIndex: Int
    let numberFormatter: NumberFormatter
    let done: () -> Void
    
    @State private var saveError: String?
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
                    if let newScore = Int(editedScore), newScore >= 0, newScore < 10_000_000_000, game.scores[scoreIndex] != newScore {
                        game.scores[scoreIndex] = newScore
                        do { try game.modelContext?.save() }
                        catch {
                            game.modelContext?.rollback()
                            saveError = error.localizedDescription
                            return
                        }
                    }
                    done()
                }
                .disabled(Int(editedScore).map { $0 < 0 || $0 >= 10_000_000_000 } ?? true)
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .padding(.top, 16)
            }
            .font(.title)
        }
        .alert("Score was not saved", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
        .onAppear {
            editedScore = String(game.scores[scoreIndex])
        }
    }
}
