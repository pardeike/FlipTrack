import SwiftUI
import Foundation

struct SessionView: View {
    let session: Session

    let color1 = Color(hue: 0.54, saturation: 1, brightness: 1)
    let color2 = Color(hue: 0.07, saturation: 1, brightness: 1)
    static let gold = Color.yellow.opacity(0.25)

    init(session: Session) {
        self.session = session
    }

    func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        return formatter.string(from: date)
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

    private var rndScore: Int {
        Int.random(in: 0...100)
    }

    var body: some View {
        VStack(spacing: 0) {
            CurrentGameView(firstPlayer: session.firstPlayer,
                            secondPlayer: session.secondPlayer,
                            firstPlayerIndex: session.firstPlayerIndex,
                            colorFor: color(for:),
                            gold: SessionView.gold)

            TotalsView(playerTotals: session.playerTotals,
                       playerWins: session.playerWins,
                       colorFor: color(for:),
                       formattedNumber: formattedNumber,
                       gold: SessionView.gold)

            if session.games?.isEmpty == false {
                GamesPlayedView(games: session.games ?? [],
                                formattedNumber: formattedNumber,
                                winningColor: winningColor)
            } else {
                Spacer()
            }

            Button(action: {
                camera.takePhoto { image in
                    Task {
                        let scores = await Analyzer.extractScore(image, 320, 0.2)
                        if scores.count == 2 {
                            let newGame = Game(nr: (session.games?.count ?? 0) + 1, scores: scores, session: session)
                            session.games = session.games ?? []
                            session.games?.append(newGame)
                            session.modelContext?.insert(newGame)
                            try? session.modelContext?.save()
                        }
                    }
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
        .navigationTitle(formattedDate(session.date))
        .navigationBarTitleDisplayMode(.inline)
    }
}


#Preview {
    SessionView(session: Session(date: Date()))
}
