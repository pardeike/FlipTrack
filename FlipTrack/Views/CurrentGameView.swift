import SwiftUI

struct CurrentGameView: View {
    let firstPlayer: String
    let secondPlayer: String
    let firstPlayerIndex: Int
    let colorFor: (Int) -> Color
    let gold: Color

    var body: some View {
        VStack {
            Grid(alignment: .center) {
                GridRow {
                    Text("CURRENT")
                        .font(.headline)
                        .foregroundColor(.gray)
                        .padding(6)
                        .gridCellColumns(3)
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color(white: 0.1))
            .padding(.bottom, -8)
            
            LazyVGrid(columns: [
                GridItem(.fixed(50), spacing: 0, alignment: .center),
                GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 0, alignment: .trailing),
                GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 0, alignment: .trailing)
            ]) {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(.yellow)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 6)
                    .background(gold)
                Text(firstPlayer)
                    .foregroundColor(colorFor(firstPlayerIndex))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(gold)
                    .font(.title)
                    .bold()
                Text(secondPlayer)
                    .foregroundColor(colorFor(1 - firstPlayerIndex).opacity(0.1))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .font(.title)
                    .bold()
            }
            .background(Color(white: 0.1))
            .padding(.bottom, 20)
        }
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
