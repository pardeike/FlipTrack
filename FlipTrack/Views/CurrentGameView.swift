import SwiftUI

struct CurrentGameView: View {
    let firstPlayer: String
    let secondPlayer: String
    let firstPlayerIndex: Int
    let colorFor: (Int) -> Color
    var gameNumber = 1

    var body: some View {
        HStack(spacing: 10) {
            Text("GAME \(gameNumber)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text("\(firstPlayer) starts")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colorFor(firstPlayerIndex))
            Image(systemName: "arrow.right")
                .font(.caption).foregroundStyle(.secondary)
            Text(secondPlayer)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Game \(gameNumber). Player 1: \(firstPlayer). Player 2: \(secondPlayer).")
    }
}
