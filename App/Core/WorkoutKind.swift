enum WorkoutKind: String, Codable, CaseIterable, Identifiable {
    case strength, mobility, intervals
    var id: Self { self }
    var title: String {
        switch self { case .strength: "Силовая"; case .mobility: "Подвижность"; case .intervals: "Интервальная" }
    }
    var icon: String {
        switch self { case .strength: "dumbbell"; case .mobility: "figure.flexibility"; case .intervals: "bolt" }
    }
}
