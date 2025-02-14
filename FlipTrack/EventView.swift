import SwiftUI

struct EventView: View {
    @StateObject private var viewModel = EventViewModel()
    @State private var eventDate = Date()

    var body: some View {
        VStack(spacing: 0) {
            // Header with back button and event date.
            HStack {
                Button(action: {
                    // Back action handled by NavigationView.
                }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.white)
                        .padding()
                }
                Spacer()
                Text(formattedEventDate(for: eventDate))
                    .foregroundColor(.white)
                    .font(.headline)
                Spacer()
                // Dummy spacer for symmetry.
                Spacer().frame(width: 44)
            }
            .background(Color.black)

            // Current game header.
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Game")
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Text("\(viewModel.currentGameInfo.firstPlayer) starts")
                        .font(.title2)
                        .bold()
                        .foregroundColor(color(for: viewModel.currentGameInfo.firstPlayer))
                }
                .padding()
                Spacer()
            }
            .background(Color.gray.opacity(0.2))

            // Totals section showing scores and wins.
            let totals = viewModel.playerTotals
            let wins = viewModel.playerWins
            HStack {
                Spacer()
                VStack {
                    Text(viewModel.player1)
                        .font(.headline)
                        .foregroundColor(color(for: viewModel.player1))
                    Text("Score: \(totals.player1Score)")
                        .foregroundColor(totals.player1Score >= totals.player2Score ? color(for: viewModel.player1) : .white)
                        .fontWeight(totals.player1Score >= totals.player2Score ? .bold : .regular)
                    Text("Wins: \(wins.player1Wins)")
                        .foregroundColor(wins.player1Wins >= wins.player2Wins ? color(for: viewModel.player1) : .white)
                        .fontWeight(wins.player1Wins >= wins.player2Wins ? .bold : .regular)
                }
                Spacer()
                VStack {
                    Text(viewModel.player2)
                        .font(.headline)
                        .foregroundColor(color(for: viewModel.player2))
                    Text("Score: \(totals.player2Score)")
                        .foregroundColor(totals.player2Score >= totals.player1Score ? color(for: viewModel.player2) : .white)
                        .fontWeight(totals.player2Score >= totals.player1Score ? .bold : .regular)
                    Text("Wins: \(wins.player2Wins)")
                        .foregroundColor(wins.player2Wins >= wins.player1Wins ? color(for: viewModel.player2) : .white)
                        .fontWeight(wins.player2Wins >= wins.player1Wins ? .bold : .regular)
                }
                Spacer()
            }
            .padding()
            .background(Color.black)

            // List of all games.
            List {
                ForEach(viewModel.games) { game in
                    HStack {
                        Text("#\(game.id)")
                            .frame(width: 40, alignment: .leading)
                        let players = playersFor(game: game)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(players.first) vs \(players.second)")
                                .foregroundColor(.white)
                            HStack {
                                let p1Score = (game.id % 2 != 0) ? game.leftScore : game.rightScore
                                let p2Score = (game.id % 2 != 0) ? game.rightScore : game.leftScore
                                Text("\(p1Score)")
                                    .foregroundColor(p1Score >= p2Score ? color(for: players.first) : .white)
                                Text("-")
                                    .foregroundColor(.white)
                                Text("\(p2Score)")
                                    .foregroundColor(p2Score > p1Score ? color(for: players.second) : .white)
                            }
                        }
                    }
                    .listRowBackground(Color.black)
                }
            }
            .listStyle(PlainListStyle())

            // Footer with snapshot button.
            HStack {
                Spacer()
                Button(action: {
                    // Trigger snapshot logic.
                }) {
                    Text("Snapshot")
                        .font(.headline)
                        .foregroundColor(.black)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(8)
                }
                Spacer()
            }
            .padding()
            .background(Color.black)
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
        .preferredColorScheme(.dark)
    }

    // Adjusts the event date based on a 2AM start.
    func formattedEventDate(for date: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let adjustedDate = (hour < 2) ? calendar.date(byAdding: .day, value: -1, to: date) ?? date : date
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: adjustedDate)
    }

    // Returns color for a given player.
    func color(for player: String) -> Color {
        return player == viewModel.player1 ? Color.yellow : Color.orange
    }

    // Determines players order based on game number.
    func playersFor(game: Game) -> (first: String, second: String) {
        if game.id % 2 != 0 {
            return (first: viewModel.player1, second: viewModel.player2)
        } else {
            return (first: viewModel.player2, second: viewModel.player1)
        }
    }
}

struct EventView_Previews: PreviewProvider {
    static var previews: some View {
        EventView()
    }
}
