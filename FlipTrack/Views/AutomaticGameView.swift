import SwiftUI

struct AutomaticGameView: View {
    let state: AutomaticGameState
    let players: [String]
    let gameNumber: Int
    var isPaused = false
    var playerWins = [0, 0]
    var lastScores: [Int]?

    private var actionColor: Color { [Color.color1, Color.color2][state.actionPlayerIndex] }
    private var heading: String {
        switch state.phase {
        case .ready: "Come and play"
        case .playing: "Your turn"
        case .switchPlayers: "Switch"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack(spacing: 6) {
                    Circle().fill(isPaused ? .orange : .green).frame(width: 6, height: 6)
                    Text(isPaused ? "PAUSED · GAME \(gameNumber)" : "AUTOMATIC · GAME \(gameNumber)")
                        .font(.caption.weight(.semibold)).tracking(1)
                }
                .foregroundStyle(.secondary)
                .padding(.top, 16)

                VStack(spacing: 16) {
                    Image(systemName: state.phase == .switchPlayers ? "arrow.left.arrow.right" : "arcade.stick")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(actionColor)
                        .accessibilityHidden(true)
                    Text(heading)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(players[state.actionPlayerIndex])
                        .font(.system(size: 62, weight: .bold, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.45)
                        .foregroundStyle(actionColor)
                        .accessibilityLabel("\(heading), \(players[state.actionPlayerIndex])")
                    if state.phase == .switchPlayers {
                        Text("You start the next game")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .padding(.horizontal, 16)
                .background(actionColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 24))

                VStack(spacing: 6) {
                    Text(players[state.otherPlayerIndex])
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 14) {
                        let wins = playerWins[state.otherPlayerIndex]
                        Label(wins == 1 ? "1 win" : "\(wins) wins", systemImage: "trophy")
                        if let lastScores {
                            Text("Last \(lastScores[state.otherPlayerIndex].formatted(.number.locale(Locale(identifier: "de_DE"))))")
                                .monospacedDigit()
                        }
                    }
                    .font(.caption)
                }
                .foregroundStyle(.secondary)

                if let scores = state.finishedScores {
                    VStack(spacing: 12) {
                        Label("Game saved", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.medium)).foregroundStyle(.green)
                        HStack {
                            ForEach(0..<2) { index in
                                VStack(spacing: 4) {
                                    Text(players[index]).foregroundStyle(.secondary)
                                    Text(scores[index].formatted(.number.locale(Locale(identifier: "de_DE"))))
                                        .fontWeight(.semibold).monospacedDigit()
                                        .lineLimit(1).minimumScaleFactor(0.65)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .font(.subheadline)
                        Text("Waiting for both scores to reset to zero")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}

#Preview("Ready") {
    AutomaticGameView(state: AutomaticGameState(), players: ["Andreas", "Fredrik"], gameNumber: 1)
        .preferredColorScheme(.dark)
}

#Preview("Switch") {
    AutomaticGameView(state: AutomaticGameState(firstPlayerIndex: 0, lastScores: [24_274_100, 37_531_870]),
                      players: ["Andreas", "Fredrik"], gameNumber: 2)
        .preferredColorScheme(.dark)
}
