import SwiftUI

/*
struct MaxHeight {
    struct Key: PreferenceKey {
        static var defaultValue: CGFloat = 0.0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    struct Notify: ViewModifier {
        private var sizeView: some View {
            GeometryReader { geo in
                Color.clear.preference(key: Key.self, value: geo.size.height)
            }
        }
        func body(content: Content) -> some View { content.background(sizeView) }
    }

    struct Equalizer: ViewModifier {
        @Binding var height: CGFloat?
        func body(content: Content) -> some View {
            content.onPreferenceChange(Key.self) { value in
                let oldHeigth = height ?? 0
                if value > oldHeigth {
                    height = value
                }
            }
        }
        static var notify: Notify {
            Notify()
        }
    }
}
*/

struct PrefixedRow<Column1: View, Column2: View, Column3: View>: View {
    var firstColumnWidth = CGFloat(50)
    var background1: (AnyView) -> AnyView = { $0 }
    var background2: (AnyView) -> AnyView = { $0 }
    let column1: () -> Column1
    let column2: () -> Column2
    let column3: () -> Column3
    
    @State private var maxHeight: CGFloat?
    
    var body: some View {
        Grid(horizontalSpacing: 0) {
            GridRow {
                background1( AnyView(
                    HStack(spacing: 0) {
                        column1()
                            .frame(width: firstColumnWidth)
                        
                        column2()
                            .relativeWidth { ($0 - firstColumnWidth) / 2 }
                    }
                ))
                
                background2(AnyView(
                    column3()
                        .relativeWidth { ($0 - firstColumnWidth) / 2 }
                ))
            }
        }
        .frame(maxWidth: .infinity)
        .observeGridWidth()
    }
}

#Preview {
    let star = Image(systemName: "star.fill").foregroundStyle(.red)
    let t1 = Text("Andreas").font(.title2).bold().foregroundColor(.blue).padding()
    let t2 = Text("Fredrik").font(.title2).bold().foregroundColor(.black).padding()
    VStack(spacing: 0) {
        PrefixedRow(background1: Color.yellow.asBackground(), background2: Color.gray.asBackground()) { star } column2: { t1 } column3: { t2 }
        PrefixedRow(background1: Color.yellow.asBackground(), background2: Color.gray.asBackground()) { star } column2: { t1 } column3: { t2 }
        PrefixedRow(background1: Color.yellow.asBackground(), background2: Color.gray.asBackground()) { star } column2: { t1 } column3: { t2 }
    }
}
