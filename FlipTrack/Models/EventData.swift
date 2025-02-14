actor EventData {
    private(set) var games: [Game] = []

    init(games: [Game] = []) {
        self.games = games
    }

    func addGame(_ game: Game) {
        games.append(game)
    }

    func updateGames(_ games: [Game]) {
        self.games = games
    }
}
