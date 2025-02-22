import SwiftUI

struct GoldShineModifier: ViewModifier {
    @State private var animate = false
    let animation = Animation.linear(duration: TimeInterval.random(in: 3...5)).repeatForever(autoreverses: false)
    
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Color.gold
                    GeometryReader { geo in
                        let width = geo.size.width
                        LinearGradient(
                            gradient: Gradient(colors: [.clear, Color.white.opacity(0.4), .clear]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: width, height: geo.size.height)
                        .rotationEffect(.degrees(30))
                        .offset(x: animate ? width : -width)
                        .onAppear {
                            withAnimation(animation.delay(TimeInterval.random(in: 0...0.5))) {
                                animate = true
                            }
                        }
                    }
                }
                .clipped()
            )
    }
}

extension Color {
    static func goldShine(_ view: AnyView) -> AnyView {
        view.goldShine()
    }
}

extension View {
    func goldShine() -> AnyView {
        AnyView(self.modifier(GoldShineModifier()))
    }
}
