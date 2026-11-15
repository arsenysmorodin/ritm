import Foundation

enum Muscle: String, CaseIterable, Identifiable {
    case chest, shoulders, biceps, triceps, forearms, abs, obliques
    case upperBack, lats, lowerBack, glutes, quads, hamstrings, calves

    var id: Self { self }
    var title: String {
        switch self {
        case .chest: "Грудные"
        case .shoulders: "Плечи"
        case .biceps: "Бицепсы"
        case .triceps: "Трицепсы"
        case .forearms: "Предплечья"
        case .abs: "Пресс"
        case .obliques: "Косые мышцы живота"
        case .upperBack: "Верх спины"
        case .lats: "Широчайшие"
        case .lowerBack: "Поясница"
        case .glutes: "Ягодичные"
        case .quads: "Передняя поверхность бедра"
        case .hamstrings: "Задняя поверхность бедра"
        case .calves: "Икры"
        }
    }
}

enum Equipment: String, CaseIterable, Identifiable {
    case body, dumbbells, band, bar, chair
    var id: Self { self }
    var title: String {
        switch self {
        case .body: "Без инвентаря"
        case .dumbbells: "Гантели"
        case .band: "Резинка"
        case .bar: "Турник"
        case .chair: "Опора"
        }
    }
}

struct ExercisePreset: Identifiable {
    let id: String
    let name: String
    let equipment: Equipment
    let primary: [Muscle]
    let secondary: [Muscle]
    let hint: String
    let target: Int
    let unit: ExerciseUnit

    init(_ id: String, _ name: String, _ equipment: Equipment, _ primary: [Muscle], _ secondary: [Muscle],
         _ hint: String, target: Int = 10, unit: ExerciseUnit = .repetitions) {
        self.id = id
        self.name = name
        self.equipment = equipment
        self.primary = primary
        self.secondary = secondary
        self.hint = hint
        self.target = target
        self.unit = unit
    }
}

enum ExerciseCatalog {
    static let all: [ExercisePreset] = [
        .init("squat", "Приседания", .body, [.quads, .glutes], [.abs], "Сгибайте колени и таз одновременно. Опирайтесь на всю стопу.", target: 12),
        .init("push-up", "Отжимания", .body, [.chest, .triceps], [.shoulders, .abs], "Опускайтесь и поднимайтесь всем корпусом, сохраняя прямую линию от плеч до пяток.", target: 8),
        .init("bridge", "Ягодичный мост", .body, [.glutes], [.hamstrings], "Поднимайте таз, опираясь на стопы. В верхней точке не прогибайте поясницу.", target: 12),
        .init("reverse-lunge", "Обратные выпады", .body, [.quads, .glutes], [.hamstrings, .abs], "Шагните назад, опуститесь на передней ноге и вернитесь. Повторы считайте на сторону."),
        .init("plank", "Планка", .body, [.abs], [.obliques, .shoulders], "Локти под плечами. Сохраняйте ровный корпус и свободное дыхание.", target: 30, unit: .seconds),
        .init("side-plank", "Боковая планка", .body, [.obliques], [.shoulders, .glutes], "Поставьте локоть под плечо, поднимите таз и удерживайте линию корпуса. Время считайте на сторону.", target: 20, unit: .seconds),
        .init("dead-bug", "Мёртвый жук", .body, [.abs], [.obliques], "На выдохе медленно отведите противоположные руку и ногу. Меняйте стороны."),
        .init("bird-dog", "Птица-собака", .body, [.lowerBack, .glutes], [.abs, .shoulders], "Стоя на четвереньках, вытяните противоположные руку и ногу, не разворачивая таз."),
        .init("calf-raise", "Подъём на носки", .body, [.calves], [], "Поднимайте пятки и опускайте их с контролем. При необходимости держитесь за устойчивую опору.", target: 15),
        .init("wall-sit", "Стульчик у стены", .body, [.quads], [.glutes], "Облокотитесь на стену и удерживайте положение на удобной глубине.", target: 25, unit: .seconds),
        .init("hinge", "Наклон с отведением таза", .body, [.hamstrings, .glutes], [.lowerBack], "Слегка согните колени и отведите таз назад. Вернитесь за счёт движения в тазобедренных суставах."),
        .init("mountain-climber", "Альпинист", .body, [.abs], [.shoulders, .quads], "Из упора по очереди подтягивайте колени к корпусу. Держите плечи над кистями.", target: 30, unit: .seconds),
        .init("jumping-jack", "Прыжки с разведением", .body, [.calves, .shoulders], [.quads, .glutes], "Разводите ноги и поднимайте руки в одном ритме. Можно заменить прыжок шагом.", target: 30, unit: .seconds),
        .init("cat-cow", "Кошка-корова", .body, [.upperBack, .lowerBack], [.abs], "На четвереньках плавно округляйте и разгибайте спину в удобной амплитуде.", target: 8),
        .init("thoracic-rotation", "Повороты грудного отдела", .body, [.upperBack, .obliques], [], "Медленно поворачивайте верхнюю часть корпуса, удерживая таз на месте. Повторы считайте на сторону.", target: 8),
        .init("trunk-rotation", "Повороты корпуса", .body, [.obliques], [.abs, .upperBack], "Держите таз устойчиво и плавно поворачивайте корпус в обе стороны."),
        .init("hip-stretch", "Растяжка сгибателей бедра", .body, [.quads], [.glutes], "Встаньте на одно колено, слегка подкрутите таз и мягко перенесите вес вперёд. Время считайте на сторону.", target: 25, unit: .seconds),
        .init("step-up", "Шаг на платформу", .chair, [.quads, .glutes], [.calves], "Используйте устойчивую невысокую платформу. Опускайтесь медленно. Повторы считайте на сторону."),
        .init("incline-push-up", "Отжимания от опоры", .chair, [.chest, .triceps], [.shoulders, .abs], "Упритесь в устойчивую опору и опускайте грудь между ладонями."),
        .init("split-squat", "Болгарские приседания", .chair, [.quads, .glutes], [.hamstrings, .abs], "Поставьте заднюю стопу на устойчивую опору и плавно сгибайте переднюю ногу. Повторы считайте на сторону.", target: 8),
        .init("goblet-squat", "Присед с гантелью у груди", .dumbbells, [.quads, .glutes], [.abs, .upperBack], "Держите гантель у груди и опускайтесь с опорой на всю стопу."),
        .init("dumbbell-row", "Тяга гантелей", .dumbbells, [.lats, .upperBack], [.biceps, .forearms], "Отведите таз назад и тяните локти к корпусу, удерживая плечи под контролем."),
        .init("dumbbell-rdl", "Румынская тяга с гантелями", .dumbbells, [.hamstrings, .glutes], [.lowerBack, .forearms], "Отводите таз назад, ведя гантели близко к ногам. Поднимайтесь движением таза вперёд."),
        .init("dumbbell-floor-press", "Жим гантелей лёжа на полу", .dumbbells, [.chest, .triceps], [.shoulders], "Опускайте локти до лёгкого касания пола и выжимайте гантели вверх."),
        .init("dumbbell-press", "Жим гантелей над головой", .dumbbells, [.shoulders, .triceps], [.abs, .upperBack], "Выжимайте гантели от плеч вверх, сохраняя устойчивое положение корпуса."),
        .init("dumbbell-lateral-raise", "Разведения гантелей в стороны", .dumbbells, [.shoulders], [.upperBack], "Поднимайте руки в стороны, слегка согнув локти. Опускайте плавно.", target: 12),
        .init("dumbbell-curl", "Сгибания рук с гантелями", .dumbbells, [.biceps], [.forearms], "Держите локти рядом с корпусом. Поднимайте и опускайте гантели без раскачивания.", target: 12),
        .init("dumbbell-extension", "Разгибание рук с гантелью", .dumbbells, [.triceps], [.shoulders], "Удерживая плечи на месте, сгибайте и разгибайте локти с контролем.", target: 12),
        .init("farmer-carry", "Прогулка фермера", .dumbbells, [.forearms, .upperBack], [.abs, .obliques], "Держите гантели по бокам и идите ровными шагами, сохраняя вертикальный корпус.", target: 30, unit: .seconds),
        .init("band-row", "Тяга резинки к поясу", .band, [.upperBack, .lats], [.biceps], "Закрепите резинку на устойчивой опоре и тяните локти назад вдоль корпуса.", target: 12),
        .init("band-pull-apart", "Разведение рук с резинкой", .band, [.upperBack, .shoulders], [.forearms], "Держите резинку перед грудью и разводите руки в стороны, не поднимая плечи.", target: 15),
        .init("band-walk", "Шаги в сторону с резинкой", .band, [.glutes], [.quads], "Слегка согните ноги и делайте короткие шаги, сохраняя натяжение резинки.", target: 12),
        .init("band-pallof", "Жим Палофа", .band, [.obliques, .abs], [.shoulders], "Встаньте боком к креплению резинки. Выпрямляйте руки, удерживая корпус от поворота."),
        .init("pull-up", "Подтягивания", .bar, [.lats, .biceps], [.upperBack, .forearms], "Подтягивайтесь без раскачивания. Опускайтесь до удобного выпрямления рук.", target: 5),
        .init("hang", "Вис на турнике", .bar, [.forearms], [.shoulders, .upperBack], "Держитесь за перекладину обеими руками, удерживая плечи в удобном положении.", target: 20, unit: .seconds)
    ]

    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    private static let byName = Dictionary(uniqueKeysWithValues: all.map { (normalize($0.name), $0) })

    static func normalize(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased().replacingOccurrences(of: "ё", with: "е")
    }

    static func find(_ plan: ExercisePlan) -> ExercisePreset? {
        if let id = plan.catalogID, let preset = byID[id] { return preset }
        return byName[normalize(plan.name)]
    }
}
