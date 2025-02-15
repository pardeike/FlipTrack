import SwiftUI
import AVFoundation
import Foundation

struct SessionView: View {
    @AppStorage("openai-api-key") private var apiKey: String = ""
    @State var cameraReady = false
    
    let session: Session

    let color1 = Color(hue: 0.54, saturation: 1, brightness: 1)
    let color2 = Color(hue: 0.07, saturation: 1, brightness: 1)
    static let gold = Color.yellow.opacity(0.25)

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
        if game.winningIndex == -1 { return .clear }
        return color(for: game.winningIndex)
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
                       highScores: session.highScores,
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
            
            if apiKey.isEmpty && !UIDevice.isSimulator {
                Button("Paste API Key") {
                    apiKey = UIPasteboard.general.string ?? ""
                }
                .buttonStyle(.borderedProminent)
            }

            if UIDevice.isSimulator || (cameraReady && !apiKey.isEmpty) {
                CameraButton(session: session)
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

#Preview("extreme") {
    SessionView(session: Session.dummy(0, [[69068440, 12353550], [512353550, 1920]]))
}

#Preview("equal") {
    SessionView(session: Session.dummy(0, [[10000, 10000]]))
}
