import SwiftUI
import AVFoundation
import Foundation
import Combine

struct SessionView: View {
    @State var cameraReady = false
    @State var scanning = false
    @State var showingPrefs = false
    let session: Session

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
        [Color.color1, Color.color2][playerIndex]
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
                            colorFor: color(for:))

            TotalsView(playerTotals: session.playerTotals,
                       playerWins: session.playerWins,
                       highScores: session.highScores,
                       averageScores: session.averageScores,
                       colorFor: color(for:),
                       formattedNumber: formattedNumber)

            if session.games?.isEmpty == false {
                GamesPlayedView(games: session.games ?? [],
                                formattedNumber: formattedNumber,
                                winningColor: winningColor, colorFor: color(for:))
            } else {
                Spacer()
            }

            if UIDevice.isSimulator || cameraReady {
                ZStack {
                    HStack {
                        Spacer()
                        CameraButton(session: session, scanning: $scanning)
                            .overlay(
                                Group {
                                    if scanning {
                                        VStack {
                                            CameraPreview()
                                                .frame(width: 400, height: 200)
                                                .padding(2)
                                        }
                                        .background(Color.yellow)
                                        .offset(CGSize(width: 0, height: -170))
                                    }
                                }
                            )
                        Spacer()
                    }
                    HStack {
                        Spacer()
                        Button { showingPrefs = true } label: {
                            Image(systemName: "gear").imageScale(.large).padding()
                        }
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
        .sheet(isPresented: $showingPrefs) {
            PreferencesView()
        }
    }
}

#Preview("extreme") {
    @Previewable @State var session = Session.dummy(0, [[69068440, 12353550], [512353550, 1920]])
    SessionView(session: session)
}

#Preview("equal") {
    @Previewable @State var session = Session.dummy(0, [[10000, 10000]])
    SessionView(session: session)
}
