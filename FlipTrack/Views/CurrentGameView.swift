import SwiftUI

struct CurrentGameView: View {
    let firstPlayer: String
    let secondPlayer: String
    let firstPlayerIndex: Int
    let colorFor: (Int) -> Color

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "CURRENT")
            PrefixedRow(background1: Color.goldShine, background2: Color(white: 0.1).asBackground(), column1: {
                Image(systemName: "arrow.right.circle.fill").foregroundColor(colorFor(firstPlayerIndex))
            }, column2: {
                Text(firstPlayer)
                    .foregroundColor(colorFor(firstPlayerIndex))
                    .font(.title)
                    .bold()
                    .padding(.vertical, 6)
            }, column3: {
                Text(secondPlayer)
                    .foregroundColor(colorFor(1 - firstPlayerIndex).opacity(0.1))
                    .font(.title)
                    .bold()
                    .padding(.vertical, 6)
            })
            .padding(.bottom, 20)
        }
    }
}

#Preview {
    CurrentGameView(firstPlayer: "Andreas",
        secondPlayer: "Fredrik",
        firstPlayerIndex: 0,
        colorFor: { [Color.red, Color.green][$0] })
        .preferredColorScheme(.dark)
}
