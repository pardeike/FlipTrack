import SwiftUI

enum ProcessingState {
    case ready
    case capturing
    case processing
}

struct CameraButton: View {
    @AppStorage("openai-api-key") private var apiKey: String = ""
    @State var state = ProcessingState.ready
    
    let session: Session
    let imageSize = 480
    let compression = 0.4
    
    func processImage(_ image: UIImage) async {
        state = .processing
        defer { state = .ready }
        let scores = await DotMatrixReader.extractScore(apiKey, image, imageSize, compression)
        if scores.count == 2 {
            let nr = (session.games?.count ?? 0) + 1
            let newGame = Game(nr: nr, scores: scores, session: session)
            session.games = session.games ?? []
            session.games?.append(newGame)
            session.modelContext?.insert(newGame)
            try? session.modelContext?.save()
        }
    }
    
    var buttonImageName: String {
        switch state {
            case .ready: return "camera.fill"
            case .capturing: return "camera"
            case .processing: return "arkit"
        }
    }
    
    var buttonColor: Color {
        switch state {
            case .ready: return .accentColor
            case .capturing: return .red
            case .processing: return .gray
        }
    }
    
    var body: some View {
        Button(action: {
            guard state == .ready else { return }
            state = .capturing
            DotMatrixReader.takePhoto { image in
                if let image {
                    Task { await processImage(image) }
                } else {
                    state = .ready
                }
            }
        }) {
            RoundedRectangle(cornerSize: .init(width: 8, height: 8))
                .frame(width: 160, height: 50)
                .foregroundColor(buttonColor)
                .overlay {
                    Image(systemName: buttonImageName)
                        .animation(nil, value: UUID())
                        .foregroundColor(.white)
                        .scaleEffect(1.6)
                }
                .animation(nil, value: UUID())
        }
        .animation(nil, value: UUID())
    }
}

#Preview {
    CameraButton(state: .ready, session: Session.dummy())
}
