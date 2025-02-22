import SwiftUI

struct UniformRowHeightKey: EnvironmentKey {
    static let defaultValue = CGFloat.zero
}

extension EnvironmentValues {
    var uniformRowHeight: CGFloat {
        get { self[UniformRowHeightKey.self] }
        set { self[UniformRowHeightKey.self] = newValue }
    }
}

struct RowHeightPreferenceKey: PreferenceKey {
    static var defaultValue = CGFloat.zero
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    func measureHeight() -> some View {
        self.background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: RowHeightPreferenceKey.self,
                                value: geometry.size.height)
            }
        )
    }
}

struct UniformRowContainerModifier: ViewModifier {
    @State private var maxHeight = CGFloat.zero

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(RowHeightPreferenceKey.self) { maxHeight = $0 }
            .environment(\.uniformRowHeight, maxHeight)
    }
}

extension View {
    func uniformRowHeight() -> some View {
        self.modifier(UniformRowContainerModifier())
    }
}

struct FillRowHeightModifier: ViewModifier {
    @Environment(\.uniformRowHeight) private var rowHeight

    func body(content: Content) -> some View {
        content.frame(height: rowHeight)
    }
}

extension View {
    func fillRowHeight() -> some View {
        self.modifier(FillRowHeightModifier())
    }
}
