import SwiftUI

struct CurrentGameView: View {
    let firstPlayer: String
    let secondPlayer: String
    let firstPlayerIndex: Int
    let colorFor: (Int) -> Color
    let gold: Color

    var body: some View {
        Grid(alignment: .center) {
            GridRow {
                Text("CURRENT GAME")
                    .font(.headline)
                    .foregroundColor(.gray)
                    .padding(6)
                    .gridCellColumns(2)
            }
            GridRow {
                Text(firstPlayer)
                    .foregroundColor(colorFor(firstPlayerIndex))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(gold)
                Text(secondPlayer)
                    .foregroundColor(colorFor(1 - firstPlayerIndex))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .textCase(.uppercase)
            .font(.title)
            .bold()
        }
        .background(Color(white: 0.1))
        .padding(.bottom, 20)
    }
}

#Preview {
    CurrentGameView(firstPlayer: "A",
        secondPlayer: "B",
        firstPlayerIndex: 0,
        colorFor: { [Color.red, Color.green][$0] },
        gold: .yellow)
        .preferredColorScheme(.dark)
}
