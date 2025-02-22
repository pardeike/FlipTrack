import SwiftUI

struct CurrentGameView: View {
    let firstPlayer: String
    let secondPlayer: String
    let firstPlayerIndex: Int
    let colorFor: (Int) -> Color
    
    func bgColor(_ index: Int) -> Color {
        index == firstPlayerIndex
        ? colorFor(0).mix(with: .black, by: 0.5)
        : colorFor(1).mix(with: .black, by: 0.5)
    }

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "CURRENT")
            PrefixedRow(background1: Color(white: 0.1).asBackground(), background2: Color(white: 0.1).asBackground(), column1: {
                Image(systemName: "arcade.stick")
                    .foregroundStyle(.yellow)
            }, column2: {
                HStack {
                    Image(systemName: "1.square.fill")
                        .scaleEffect(1.25)
                        .padding(.trailing, 6)
                    Text(firstPlayer)
                        .font(.title2)
                        .bold()
                        .padding(.vertical, 6)
                }
                .frame(maxWidth: .infinity)
                .background { bgColor(0) }
            }, column3: {
                HStack {
                    Image(systemName: "2.square.fill")
                        .scaleEffect(1.25)
                        .padding(.trailing, 6)
                    Text(secondPlayer)
                        .font(.title2)
                        .bold()
                        .padding(.vertical, 6)
                }
                .frame(maxWidth: .infinity)
                .background { bgColor(1) }
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
