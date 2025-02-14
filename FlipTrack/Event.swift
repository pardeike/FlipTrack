import Foundation

import Foundation

public struct Event: Identifiable {
    public var id = UUID()
    public let date: Date

    public init(date: Date) {
        self.date = date
    }
}
