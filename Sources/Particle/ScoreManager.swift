import Foundation

struct ScoreEntry: Codable {
    let initials: String
    let score: Int
    let wave: Int
    let date: Date?
}

final class ScoreManager {
    static let shared = ScoreManager()

    private let key = "particle_highscores"
    private(set) var scores: [ScoreEntry] = []

    private init() { load() }

    func qualifies(score: Int) -> Bool {
        scores.count < 10 || score > (scores.last?.score ?? 0)
    }

    func add(initials: String, score: Int, wave: Int) {
        let entry = ScoreEntry(initials: initials.uppercased(), score: score, wave: wave, date: Date())
        scores.append(entry)
        scores.sort { $0.score > $1.score }
        if scores.count > 10 { scores = Array(scores.prefix(10)) }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ScoreEntry].self, from: data) else { return }
        scores = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(scores) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
