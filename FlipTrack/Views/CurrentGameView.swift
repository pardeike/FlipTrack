import SwiftUI

struct CurrentGameView: View {
    let firstPlayer: String
    let secondPlayer: String
    let firstPlayerIndex: Int
    let colorFor: (Int) -> Color
    var gameNumber = 1
    var currentPlayerIndex: Int?
    var uncertain = false
    var winner: Int?

    private var playerIndex: Int { winner ?? currentPlayerIndex ?? firstPlayerIndex }
    private var name: String { playerIndex == firstPlayerIndex ? firstPlayer : secondPlayer }


    var body: some View {
        HStack(spacing: 10) {
            Text(winner == nil ? "GAME \(gameNumber)" : "SESSION")
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
            Spacer(minLength: 4)
            Text(winner != nil ? "\(name) won" : uncertain ? "\(name) turn?" : "\(name) turn")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colorFor(playerIndex))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(winner != nil ? "\(name) won the session" : "Game \(gameNumber). \(name) turn.\(uncertain ? " Tracking uncertain. Use Resync." : "")")
        .accessibilityIdentifier("currentTurn")
    }
}
