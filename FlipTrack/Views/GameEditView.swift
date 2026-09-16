import SwiftUI
import SwiftData

struct GameEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let game: Game
    @State private var firstScore = ""
    @State private var secondScore = ""
    @State private var number = ""
    @State private var starter = 0
    @State private var saveError: String?

    private var values: (Int, Int, Int)? {
        guard let first = Int(firstScore), let second = Int(secondScore),
              let nr = Int(number), nr > 0,
              (0..<10_000_000_000).contains(first), (0..<10_000_000_000).contains(second),
              !(game.session?.games?.contains { $0.id != game.id && $0.nr == nr } ?? false) else { return nil }
        return (first, second, nr)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Scores by player") {
                    field(game.session?.player1 ?? "Player 1", text: $firstScore)
                    field(game.session?.player2 ?? "Player 2", text: $secondScore)
                    Button("Swap scores", systemImage: "arrow.left.arrow.right") {
                        Telemetry.shared.action("game.swapDraft", session: game.session, gameID: game.id)
                        swap(&firstScore, &secondScore)
                    }
                }
                Section {
                    TextField("Game number", text: $number).keyboardType(.numberPad)
                    Picker("Started by", selection: $starter) {
                        Text(game.session?.player1 ?? "Player 1").tag(0)
                        Text(game.session?.player2 ?? "Player 2").tag(1)
                    }
                } footer: {
                    Text("Game numbers must be unique. Changing who started does not swap scores or change the current game's order.")
                }
            }
            .navigationTitle("Edit game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { Telemetry.shared.action("GameEditView.cancel", session: game.session, gameID: game.id); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let (first, second, nr) = values else { return }
                        Telemetry.shared.action("game.saveEdits", session: game.session, gameID: game.id)
                        let before = game.session.map(SessionSnapshot.init)
                        game.scores = [first, second]
                        game.nr = nr
                        game.startingPlayerIndex = starter
                        game.session?.recalculateRace()
                        do {
                            try context.save()
                            if let before, let session = game.session { Telemetry.shared.change("game.corrected", before: before, session: session) }
                            dismiss()
                        }
                        catch { context.rollback(); Telemetry.shared.log("GameEditView.error", ["message": error.localizedDescription]); saveError = error.localizedDescription }
                    }.disabled(values == nil)
                }
            }
            .onDisappear { Telemetry.shared.action("GameEditView.closed", session: game.session, gameID: game.id) }
            .onAppear {
                Telemetry.shared.action("GameEditView.opened", session: game.session, gameID: game.id)
                firstScore = String(game.scores[0])
                secondScore = String(game.scores[1])
                number = String(game.nr)
                starter = game.startingPlayerIndex ?? game.nr % 2
            }
            .alert("Changes were not saved", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) { }
            } message: { Text(saveError ?? "") }
        }
    }

    private func field(_ name: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name).font(.headline)
            TextField("Score", text: text)
                .keyboardType(.numberPad)
                .font(.title2.monospacedDigit())
                .accessibilityLabel("\(name)'s score")
        }.padding(.vertical, 6)
    }
}
