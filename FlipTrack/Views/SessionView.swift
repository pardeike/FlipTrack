import SwiftUI
import AVFoundation
import Foundation

struct SessionView: View {
    @AppStorage("openai-api-key") private var apiKey: String = ""
    @State var cameraReady = false
    
    let session: Session
    let imageSize = 320
    let compression = 0.2

    let color1 = Color(hue: 0.54, saturation: 1, brightness: 1)
    let color2 = Color(hue: 0.07, saturation: 1, brightness: 1)
    static let gold = Color.yellow.opacity(0.25)
    
#if targetEnvironment(simulator)
    var rScore: Int {
        let n = Int.random(in: 5..<300)
        return n * n * n * 10
    }
#endif

    init(session: Session) {
        self.session = session
    }

    func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    func formattedNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    func color(for playerIndex: Int) -> Color {
        [color1, color2][playerIndex]
    }

    func winningColor(_ game: Game) -> Color {
        color(for: game.winningIndex)
    }

    var body: some View {
        VStack(spacing: 0) {
            CurrentGameView(firstPlayer: session.firstPlayer,
                            secondPlayer: session.secondPlayer,
                            firstPlayerIndex: session.firstPlayerIndex,
                            colorFor: color(for:),
                            gold: SessionView.gold)

            TotalsView(playerTotals: session.playerTotals,
                       playerWins: session.playerWins,
                       colorFor: color(for:),
                       formattedNumber: formattedNumber,
                       gold: SessionView.gold)

            if session.games?.isEmpty == false {
                GamesPlayedView(games: session.games ?? [],
                                formattedNumber: formattedNumber,
                                winningColor: winningColor)
            } else {
                Spacer()
            }
            
            if apiKey.isEmpty {
                Button("Paste API Key") {
                    apiKey = UIPasteboard.general.string ?? ""
                }
                .buttonStyle(.borderedProminent)
            }

            if cameraReady && !apiKey.isEmpty {
                Button(action: {
#if targetEnvironment(simulator)
                    let scores = [rScore, rScore]
                    let newGame = Game(nr: (session.games?.count ?? 0) + 1, scores: scores, session: session)
                    session.games = session.games ?? []
                    session.games?.append(newGame)
                    session.modelContext?.insert(newGame)
                    try? session.modelContext?.save()
#else
                    DotMatrixReader.takePhoto { image in
                        Task {
                            let scores = await DotMatrixReader.extractScore(apiKey, image, imageSize, compression)
                            if scores.count == 2 {
                                let newGame = Game(nr: (session.games?.count ?? 0) + 1, scores: scores, session: session)
                                session.games = session.games ?? []
                                session.games?.append(newGame)
                                session.modelContext?.insert(newGame)
                                try? session.modelContext?.save()
                            }
                        }
                    }
#endif
                }) {
                    Circle()
                        .frame(width: 60, height: 60)
                        .foregroundColor(.accentColor)
                        .overlay {
                            Image(systemName: "camera.fill")
                                .foregroundColor(.white)
                                .scaleEffect(1.6)
                        }
                }
            }
        }
        .padding(.horizontal)
        .preferredColorScheme(.dark)
        .navigationTitle(formattedDate(session.date))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if AVCaptureDevice.authorizationStatus(for: .video) != .authorized {
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    cameraReady = granted
                }
            } else {
                cameraReady = true
            }
        }
    }
}


#Preview {
    SessionView(session: Session(date: Date()))
}
