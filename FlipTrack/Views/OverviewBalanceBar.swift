import SwiftUI

struct OverviewBalanceBar: View {
    func color(for playerIndex: Int) -> Color { [Color.color1b, Color.color2b][playerIndex] }
    let values: [Int]
    var f: CGFloat { CGFloat(values[0]) / CGFloat(values[0] + values[1]) }
    var body: some View {
        if values[0] + values[1] > 0 {
            GeometryReader { geo in
                Rectangle()
                    .fill(color(for: 1))
                    .frame(width: geo.size.width, height: 20)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(color(for: 0))
                            .frame(width: geo.size.width * f, height: 20)
                    }
                    .overlay(alignment: .leading) {
                        Text("\(values[0]) Andreas")
                            .padding(.leading, 6)
                            .foregroundStyle(.white).bold().font(.caption)
                    }
                    .overlay(alignment: .trailing) {
                        Text("Fredrik \(values[1])")
                            .padding(.trailing, 6)
                            .foregroundStyle(.white).bold().font(.caption)
                    }
            }
        }
    }
}
