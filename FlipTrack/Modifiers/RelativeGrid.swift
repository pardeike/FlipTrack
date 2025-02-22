import SwiftUI

struct RelativeWidthEnvKey: EnvironmentKey {
    static let defaultValue = CGFloat.zero
}

extension EnvironmentValues {
    var relativeWidth: CGFloat {
        get { self[RelativeWidthEnvKey.self] }
        set { self[RelativeWidthEnvKey.self] = newValue }
    }
}

struct RelativeWidthObserverModifier: ViewModifier {
    @State private var measuredWidth = CGFloat.zero
    
    struct Key: PreferenceKey {
        static var defaultValue = CGFloat.zero
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader {
                    Color.clear.preference(key: Key.self, value: $0.size.width)
                }
            )
            .onPreferenceChange(Key.self) { self.measuredWidth = $0 }
            .environment(\.relativeWidth, measuredWidth)
    }
}

struct RelativeWidthApplyModifier: ViewModifier {
    @Environment(\.relativeWidth) private var gridWidth
    let transform: (CGFloat) -> CGFloat

    func body(content: Content) -> some View {
        content.frame(width: max(0, transform(gridWidth)))
    }
}

extension View {
    func observeGridWidth() -> some View {
        self.modifier(RelativeWidthObserverModifier())
    }
    
    func relativeWidth(_ transform: @escaping (CGFloat) -> CGFloat) -> some View {
        self.modifier(RelativeWidthApplyModifier(transform: transform))
    }
}
