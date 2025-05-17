import SwiftUI

struct CameraButton: View {
    @State var isPressed = false
    @Binding var scanning: Bool
    let session: Session
    
    init(session: Session, scanning: Binding<Bool>) {
        self.session = session
        _scanning = scanning
    }
    
    func updateState(_ active: Bool) {
        isPressed = active
        DispatchQueue.main.async { scanning = active }
    }
    
    var body: some View {
        RoundedRectangle(cornerSize: .init(width: 8, height: 8))
            .frame(width: 160, height: 50)
            .foregroundColor(scanning ? .gray : .accentColor)
            .overlay {
                Image(systemName: "camera.fill")
                    .animation(nil, value: UUID())
                    .foregroundColor(.white)
                    .scaleEffect(1.6)
            }
            .animation(nil, value: UUID())
            .onLongPressGesture(
                minimumDuration: 0,
                perform: { },
                onPressingChanged: { pressed in
                    if pressed && isPressed == false {
                        updateState(true)
                        Scanner.startScanning { scores in
                            updateState(false)
                            Scanner.stopScanning()
                            Task {
                                let count = session.games?.count ?? 0
                                var ordered = scores
                                if session.firstPlayerIndex == 1 {
                                    ordered = [scores[1], scores[0]]
                                }
                                session.games?.append(Game(nr: count + 1, scores: ordered, session: session))
                            }
                        }
                    }
                    if pressed == false && isPressed {
                        updateState(false)
                        Scanner.stopScanning()
                    }
                }
            )
    }
}

#Preview {
    @Previewable @State var scanning = false
    Spacer()
    if scanning {
        CameraPreview().frame(width: 320, height: 240)
    }
    CameraButton(session: Session.dummy(), scanning: $scanning)
}
