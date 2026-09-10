import SwiftUI
import SwiftData

struct GamesPlayedView: View {
    let games: [Game]
    let formattedNumber: (Int) -> String
    let colorFor: (Int) -> Color
    var allowsEditing = true
    @State private var saveError: String?
    @State private var editGame: Game?
    @State private var editScoreIndex = 0
    @State private var deletingGame: Game?

    private let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        return formatter
    }()

    private var sortedGames: [Game] { games.sorted { $0.nr > $1.nr } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("GAMES").font(.caption.weight(.semibold)).tracking(1)
                Spacer()
                Text(allowsEditing ? "Tap a score to edit" : "Stop scanning to edit").font(.caption)
            }
            .foregroundStyle(.secondary)
            ForEach(sortedGames) { game in
                HStack(spacing: 6) {
                    Menu {
                        Button("Swap scores", systemImage: "arrow.left.arrow.right") {
                            game.scores.swapAt(0, 1)
                            saveChanges(in: game.modelContext)
                        }
                        Button("Delete game", systemImage: "trash", role: .destructive) { deletingGame = game }
                    } label: {
                        Text("\(game.nr)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 44)
                            .contentShape(Rectangle())
                    }
                    .disabled(!allowsEditing)
                    .accessibilityLabel("Game \(game.nr) actions")
                    ForEach(0..<2) { index in
                        Button {
                            editScoreIndex = index
                            editGame = game
                        } label: {
                            HStack(spacing: 4) {
                                if game.scores[index] == game.session?.highScores[index] {
                                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                                }
                                Spacer(minLength: 0)
                                Text(formattedNumber(game.scores[index]))
                                    .font(.subheadline.weight(.medium).monospacedDigit())
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                            }
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(.primary)
                            .background(colorFor(index).opacity(game.winningIndex == index ? 0.24 : 0.08), in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                        .disabled(!allowsEditing)
                        .accessibilityLabel("Game \(game.nr), \(index == 0 ? game.session?.player1 ?? "Player 1" : game.session?.player2 ?? "Player 2"), \(game.scores[index])\(allowsEditing ? ". Edit score" : "")")
                    }
                }
            }
        }
        .padding(14)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16))
        .confirmationDialog("Delete game \(deletingGame?.nr ?? 0)?", isPresented: Binding(get: { deletingGame != nil }, set: { if !$0 { deletingGame = nil } }), titleVisibility: .visible) {
            Button("Delete game", role: .destructive) {
                if let game = deletingGame, let context = game.modelContext {
                    context.delete(game)
                    saveChanges(in: context)
                }
                deletingGame = nil
            }
        } message: { Text("This removes both scores. The next starting player stays the same.") }
        .alert("Changes were not saved", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
        .sheet(item: $editGame) {
            ScoreEditView(game: $0, scoreIndex: editScoreIndex, numberFormatter: numberFormatter, done: { editGame = nil })
        }
    }

    private func saveChanges(in context: ModelContext?) {
        do { try context?.save() }
        catch {
            context?.rollback()
            saveError = error.localizedDescription
        }
    }
}
