import SwiftUI

struct EventView: View {
    @StateObject private var viewModel = EventViewModel()
    @State private var eventDate = Date()
    
    let color1 = Color(hue: 0.54, saturation: 1, brightness: 1)
    let color2 = Color(hue: 0.07, saturation: 1, brightness: 1)
    static let gold = Color.yellow.opacity(0.25)
    
    let background1: [Color] = [.clear, gold, .clear]
    let background2: [Color] = [.clear, .clear, gold]

    func formattedEventDate(for date: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let adjustedDate = (hour < 2) ? calendar.date(byAdding: .day, value: -1, to: date) ?? date : date
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: adjustedDate)
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
    
    var playerTotalIndex: Int {
        if viewModel.playerTotals[0] == viewModel.playerTotals[1] { return -1 }
        return viewModel.playerTotals[0] > viewModel.playerTotals[1] ? 0 : 1
    }
    
    var playerWinIndex: Int {
        if viewModel.playerWins[0] == viewModel.playerWins[1] { return -1 }
        return viewModel.playerWins[0] > viewModel.playerWins[1] ? 0 : 1
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            HStack {
                Button(action: {}) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.white)
                        .padding()
                }
                Spacer()
                Text(formattedEventDate(for: eventDate))
                    .foregroundColor(.white)
                    .font(.headline)
                    .minimumScaleFactor(0.5)
                Spacer()
                Spacer().frame(width: 44)
            }
            .padding(.bottom, 10)
            
            Grid(alignment: .center) {
                GridRow {
                    Text("CURRENT GAME")
                        .font(.headline)
                        .foregroundColor(.gray)
                        .padding(6)
                        .gridCellColumns(2)
                }
                GridRow {
                    Text(viewModel.firstPlayer)
                        .foregroundColor(color(for: viewModel.firstPlayerIndex))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(EventView.gold)
                    Text(viewModel.secondPlayer)
                        .foregroundColor(color(for: 1 - viewModel.firstPlayerIndex))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .textCase(.uppercase)
                .font(.title)
                .bold()
            }
            .background(Color(white: 0.1))
            .padding(.bottom, 20)
            
            Grid(alignment: .center) {
                GridRow {
                    Text("TOTALS")
                        .font(.headline)
                        .foregroundColor(.gray)
                        .padding(6)
                        .gridCellColumns(2)
                }
                GridRow {
                    Text("Andreas").foregroundColor(color(for: 0))
                    Text("Fredrik").foregroundColor(color(for: 1))
                }
                .font(.headline)
                .bold()
                .frame(maxWidth: .infinity)
                .padding(.bottom, 6)
                GridRow {
                    Text(formattedNumber(viewModel.playerTotals[0]))
                        .foregroundColor(color(for: 0))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(background1[playerTotalIndex + 1])
                    Text(formattedNumber(viewModel.playerTotals[1]))
                        .foregroundColor(color(for: 1))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(background2[playerTotalIndex + 1])
                }
                .font(.title2)
                GridRow {
                    Text("#\(viewModel.playerWins[0])")
                        .foregroundColor(color(for: 0))
                        .font(.title)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(background1[playerWinIndex + 1])
                    Text("#\(viewModel.playerWins[1])")
                        .foregroundColor(color(for: 1))
                        .font(.title)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(background2[playerWinIndex + 1])
                }
            }
            .background(Color(white: 0.1))
            .padding(.bottom, 20)

            if !viewModel.games.isEmpty {
                Grid(alignment: .center) {
                    GridRow {
                        Text("GAMES PLAYED")
                            .font(.headline)
                            .foregroundColor(.gray)
                            .padding(6)
                            .gridCellColumns(2)
                    }
                }
                .frame(maxWidth: .infinity)
                .background(Color(white: 0.1))
                ScrollView(.vertical) {
                    LazyVGrid(columns: [
                        GridItem(.fixed(50), spacing: 0, alignment: .trailing),
                        GridItem(.flexible(minimum: 0, maximum: 10000), spacing: 0, alignment: .trailing),
                        GridItem(.flexible(minimum: 0, maximum: 10000), spacing: 0, alignment: .trailing),
                    ]) {
                        Text("#").padding(.trailing, 4)
                        Text("Andreas").padding(.trailing, 4)
                        Text("Fredrik").padding(.trailing, 10)
                        ForEach(Array(viewModel.games.enumerated()), id: \.element.id) { index, game in
                            Group {
                                HStack {
                                    Spacer()
                                    Text("\(game.nr)")
                                }
                                HStack {
                                    Spacer()
                                    if game.winningIndex == 0 {
                                        Image(systemName: "star.fill").foregroundColor(.yellow)
                                    }
                                    Text(formattedNumber(game.scores[0]))
                                }
                                HStack {
                                    Spacer()
                                    if game.winningIndex == 1 {
                                        Image(systemName: "star.fill").foregroundColor(.yellow)
                                    }
                                    Text(formattedNumber(game.scores[1]))
                                        .padding(.trailing, 6)
                                }
                            }
                            .padding(6)
                            .background(winningColor(game).opacity(0.25))
                        }
                    }
                    .font(.title2)
                }
                .background(Color(white: 0.1))
                .defaultScrollAnchor(.bottom)
                .scrollIndicators(.hidden)
                .padding(.bottom, 20)
            } else {
                Spacer()
            }
            
            Button(action: {
                Task {
                    await viewModel.addGame(scores: [rndScore, rndScore])
                    
                }
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
        .padding(.horizontal)
        .preferredColorScheme(.dark)
    }
}

struct EventView_Previews: PreviewProvider {
    static var previews: some View {
        EventView()
    }
}
