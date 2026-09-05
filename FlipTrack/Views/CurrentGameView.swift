import SwiftUI

struct CurrentGameView: View {
    let firstPlayer: String
    let secondPlayer: String
    let firstPlayerIndex: Int
    let colorFor: (Int) -> Color
    var gameNumber = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("GAME \(gameNumber)")
                    .font(.caption.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(firstPlayer) starts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                player(firstPlayer, position: 1, color: colorFor(firstPlayerIndex))
                player(secondPlayer, position: 2, color: colorFor(1 - firstPlayerIndex))
            }
        }
        .padding(14)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private func player(_ name: String, position: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "\(position).square.fill")
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(name)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Player \(position), \(name)")
    }
}
