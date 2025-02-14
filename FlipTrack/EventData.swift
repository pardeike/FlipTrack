actor EventData {
    private(set) var events: [Event] = []
    private(set) var games: [Game] = []

    init(events: [Event] = [], games: [Game] = []) {
        self.events = events
        self.games = games
    }
    
    func addEvent(_ event: Event) {
        events.append(event)
    }
    
    func updateEvent(_ events: [Event]) {
        self.events = events
    }
    
    func addGame(_ game: Game) {
        games.append(game)
    }
    
    func updateGames(_ games: [Game]) {
        self.games = games
    }
}
