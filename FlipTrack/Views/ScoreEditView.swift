import SwiftUI

struct ScoreEditView: View {
    let game: Game
    let scoreIndex: Int
    let numberFormatter: NumberFormatter
    let done: () -> Void
    @State private var saveError: String?
    @State private var editedScore = ""
    @FocusState private var focus: Bool

    private var player: String {
        guard let session = game.session else { return "Player \(scoreIndex + 1)" }
        return scoreIndex == 0 ? session.player1 : session.player2
    }

    private var score: Int? {
        guard let value = Int(editedScore), (0..<10_000_000_000).contains(value) else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Score", text: $editedScore)
                        .font(.title2.monospacedDigit())
                        .keyboardType(.numberPad)
                        .focused($focus)
                        .accessibilityLabel("\(player)'s score")
                    if let score {
                        Text(numberFormatter.string(from: NSNumber(value: score)) ?? "")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } header: { Text("\(player) · game \(game.nr)") }
            }
            .navigationTitle("Edit score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: done) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let score else { return }
                        game.scores[scoreIndex] = score
                        do { try game.modelContext?.save(); done() }
                        catch {
                            game.modelContext?.rollback()
                            saveError = error.localizedDescription
                        }
                    }
                    .disabled(score == nil)
                    .accessibilityIdentifier("saveScore")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .alert("Score was not saved", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
        .onAppear {
            editedScore = String(game.scores[scoreIndex])
            focus = true
        }
    }
}
