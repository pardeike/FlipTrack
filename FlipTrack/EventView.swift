import SwiftUI

struct EventView: View {
    @StateObject private var viewModel = EventViewModel()
    @State private var eventDate = Date()

    let color1 = Color(hue: 0.54, saturation: 1, brightness: 1)
    let color2 = Color(hue: 0.07, saturation: 1, brightness: 1)
    static let gold = Color.yellow.opacity(0.25)

    func formattedEventDate(for date: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let adjustedDate = (hour < 2) ? (calendar.date(byAdding: .day, value: -1, to: date) ?? date) : date
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: adjustedDate)
    }

    func formattedNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    func color(for playerIndex: Int) -> Color {
        [color1, color2][playerIndex]
    }

    func winningColor(_ game: Game) -> Color {
        color(for: game.winningIndex)
    }

    var body: some View {
        VStack(spacing: 0) {
            EventHeaderView(formattedDate: formattedEventDate(for: eventDate)) { /* TODO navigate back */ }
            
            CurrentGameView(firstPlayer: viewModel.firstPlayer,
                            secondPlayer: viewModel.secondPlayer,
                            firstPlayerIndex: viewModel.firstPlayerIndex,
                            colorFor: color(for:),
                            gold: EventView.gold)
            
            TotalsView(playerTotals: viewModel.playerTotals,
                       playerWins: viewModel.playerWins,
                       colorFor: color(for:),
                       formattedNumber: formattedNumber,
                       gold: EventView.gold)
            
            if !viewModel.games.isEmpty {
                GamesPlayedView(games: viewModel.games,
                                formattedNumber: formattedNumber,
                                winningColor: winningColor)
            } else {
                Spacer()
            }
            
            Button(action: {
                Task {
                    await viewModel.addGame(scores: [rndScore, rndScore])
                }
            }) {
                Circle()
                    .frame(width: 60, height: 60)
                    .foregroundColor(.accentColor)
                    .overlay {
                        Image(systemName: "camera.fill")
                            .foregroundColor(.white)
                            .scaleEffect(1.6)
                    }
            }
        }
        .padding(.horizontal)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    EventView()
}
