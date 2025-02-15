import SwiftUI

struct Bar: View {
    let color1 = Color(hue: 0.54, saturation: 1, brightness: 1)
    let color2 = Color(hue: 0.07, saturation: 1, brightness: 1)
    func color(for playerIndex: Int) -> Color { [color1, color2][playerIndex] }
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
                            .foregroundStyle(.black).font(.caption)
                    }
                    .overlay(alignment: .trailing) {
                        Text("Fredrik \(values[1])")
                            .padding(.trailing, 6)
                            .foregroundStyle(.black).font(.caption)
                    }
            }
        }
    }
}
