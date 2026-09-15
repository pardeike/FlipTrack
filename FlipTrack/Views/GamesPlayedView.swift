import SwiftUI
import SwiftData

struct GamesPlayedView: View {
    let games: [Game]
    let formattedNumber: (Int) -> String
    let colorFor: (Int) -> Color
    var onBeginEditing: () -> Void = {}
    @State private var saveError: String?
    @State private var editGame: Game?
    @State private var deletingGame: Game?

    private var sortedGames: [Game] { games.sorted { $0.nr > $1.nr } }
    private var highestScore: Int? { games.flatMap(\.scores).max() }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("#").frame(width: 36)
                ForEach(0..<2) { index in
                    Text(index == 0 ? games.first?.session?.player1 ?? "Player 1" : games.first?.session?.player2 ?? "Player 2")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 10)
                        .foregroundStyle(colorFor(index))
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            ForEach(sortedGames) { game in
                HStack(spacing: 6) {
                    Menu {
                        Button("Swap scores", systemImage: "arrow.left.arrow.right") {
                            onBeginEditing()
                            game.scores.swapAt(0, 1)
                            game.session?.recalculateRace()
                            saveChanges(in: game.modelContext)
                        }
                        Button("Delete game", systemImage: "trash", role: .destructive) { onBeginEditing(); deletingGame = game }
                    } label: {
                        Text("\(game.nr)")
                            .font(.subheadline.weight(.medium).monospacedDigit())
                            .foregroundStyle(.primary)
                            .padding(.trailing, 10)
                            .frame(width: 36, height: 44, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                    .tint(.primary)
                    .accessibilityLabel("Game \(game.nr) actions")
                    ForEach(0..<2) { index in
                        Button {
                            onBeginEditing()
                            editGame = game
                        } label: {
                            HStack(spacing: 4) {
                                if game.scores[index] == game.session?.highScores[index] {
                                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                                }
                                Spacer(minLength: 0)
                                Text(formattedNumber(game.scores[index]))
                                    .font(.subheadline.weight(.medium).monospacedDigit())
                                    .foregroundStyle(game.scores[index] == highestScore ? Color.yellow : Color.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                            }
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(.primary)
                            .background(colorFor(index).opacity(game.winningIndex == index ? 0.24 : 0.08), in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                            .accessibilityLabel("Game \(game.nr), \(index == 0 ? game.session?.player1 ?? "Player 1" : game.session?.player2 ?? "Player 2"), \(game.scores[index]) . Edit game")
                    }
                }
            }
        }
        .padding(14)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16))
        .confirmationDialog("Delete game \(deletingGame?.nr ?? 0)?", isPresented: Binding(get: { deletingGame != nil }, set: { if !$0 { deletingGame = nil } }), titleVisibility: .visible) {
            Button("Delete game", role: .destructive) {
                if let game = deletingGame, let context = game.modelContext {
                    let session = game.session
                    session?.games?.removeAll { $0.id == game.id }
                    context.delete(game)
                    session?.recalculateRace()
                    saveChanges(in: context)
                }
                deletingGame = nil
            }
        } message: { Text("This removes both scores. The next starting player stays the same.") }
        .alert("Changes were not saved", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
        .sheet(item: $editGame) {
            GameEditView(game: $0)
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
