import Foundation

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
        .init("hang", "Вис на турнике", .bar, [.forearms], [.shoulders, .upperBack], "Держитесь за перекладину обеими руками, удерживая плечи в удобном положении.", target: 20, unit: .seconds),
        .init("sumo-squat", "Приседания сумо", .body, [.quads, .glutes, .adductors], [.abs], "Поставьте стопы шире плеч и немного разверните носки. Опускайтесь между бёдер, направляя колени по линии стоп."),
        .init("squat-jump", "Приседания с выпрыгиванием", .body, [.quads, .glutes, .calves], [.abs], "Из неглубокого приседа вытолкните себя вверх. Приземлитесь мягко и согните колени перед следующим повтором.", target: 6),
        .init("forward-lunge", "Выпады вперёд", .body, [.quads, .glutes], [.hamstrings, .calves], "Шагните вперёд и опустите таз. Оттолкнитесь передней стопой и вернитесь. Повторы считайте на сторону."),
        .init("lateral-lunge", "Боковые выпады", .body, [.quads, .glutes, .adductors], [.abs], "Шагните в сторону, отведите таз назад и согните опорную ногу. Вторая нога остаётся почти прямой.", target: 8),
        .init("single-bridge", "Ягодичный мост на одной ноге", .body, [.glutes], [.hamstrings, .abs], "Оставьте одну стопу на полу, другую ногу вытяните. Поднимайте таз без перекоса. Повторы считайте на сторону.", target: 8),
        .init("side-leg-raise", "Подъём ноги лёжа на боку", .body, [.glutes], [.obliques], "Лягте на бок, сложив бёдра одно над другим. Поднимайте верхнюю ногу, удерживая носок направленным вперёд.", target: 12),
        .init("clamshell", "Ракушка лёжа на боку", .body, [.glutes], [.obliques], "Согните ноги и соедините стопы. Поднимайте верхнее колено, сохраняя таз неподвижным.", target: 12),
        .init("donkey-kick", "Разгибание бедра на четвереньках", .body, [.glutes], [.hamstrings, .abs], "Поднимите согнутое колено назад до линии корпуса и медленно опустите. Держите таз ровно.", target: 12),
        .init("knee-push-up", "Отжимания с колен", .body, [.chest, .triceps], [.shoulders, .abs], "Сохраняйте прямую линию от головы до колен. Опускайте грудь к полу и выжимайте себя вверх.", target: 8),
        .init("close-push-up", "Отжимания узким хватом", .body, [.triceps, .chest], [.shoulders, .abs], "Поставьте ладони ближе друг к другу, чем в обычных отжиманиях, и направляйте локти назад вдоль корпуса.", target: 8),
        .init("pike-push-up", "Отжимания уголком", .body, [.shoulders, .triceps], [.chest, .abs], "Начните из упора с высоко поднятым тазом. Сгибайте локти и опускайте макушку к полу впереди ладоней.", target: 6),
        .init("high-plank", "Планка на прямых руках", .body, [.abs], [.shoulders, .obliques], "Разместите кисти под плечами. Удерживайте прямую линию от головы до пяток и дышите спокойно.", target: 30, unit: .seconds),
        .init("shoulder-tap", "Касания плеч в планке", .body, [.abs, .obliques], [.shoulders], "Из упора на прямых руках коснитесь ладонью противоположного плеча. Поставьте стопы шире для устойчивости.", target: 10),
        .init("crunch", "Скручивания лёжа", .body, [.abs], [], "На выдохе приподнимите лопатки, приблизив рёбра к тазу. Поясницу оставьте на полу, голову поддерживайте легко.", target: 12),
        .init("reverse-crunch", "Обратные скручивания", .body, [.abs], [.obliques], "Поднимите согнутые ноги. Подкрутите таз и слегка оторвите его от пола, затем верните с контролем.", target: 12),
        .init("hollow-hold", "Лодочка на спине", .body, [.abs], [.hipFlexors], "Прижмите поясницу к полу и приподнимите лопатки и ноги. Согните колени, если поясница начинает подниматься.", target: 20, unit: .seconds),
        .init("bear-crawl", "Медвежья ходьба", .body, [.abs, .shoulders, .quads], [.obliques], "Приподнимите колени над полом и шагайте противоположными рукой и ногой. Сохраняйте корпус параллельно полу.", target: 20, unit: .seconds),
        .init("high-knees", "Бег на месте с высоким коленом", .body, [.hipFlexors, .calves], [.quads, .abs], "Поочерёдно поднимайте колени, мягко ставя стопы под корпус. Начните с шага, если так удобнее.", target: 20, unit: .seconds),
        .init("burpee", "Бёрпи без отжимания", .body, [.quads, .glutes, .shoulders], [.abs, .calves], "Поставьте руки на пол, уйдите ногами в планку, верните стопы и выпрямитесь. Ноги можно переносить шагом.", target: 6),
        .init("child-pose", "Поза ребёнка", .body, [.lats, .lowerBack], [], "Из положения на четвереньках мягко отведите таз к пяткам и вытяните руки вперёд. Дышите спокойно.", target: 30, unit: .seconds),
        .init("ankle-rock", "Колено к стене", .body, [.calves], [], "Поставьте стопу перед стеной. Направьте колено к стене по линии носка, удерживая пятку на полу.", target: 8),
        .init("chair-squat", "Приседания до стула", .chair, [.quads, .glutes], [.abs], "Встаньте перед устойчивым стулом. Отведите таз до лёгкого касания сиденья и встаньте без раскачивания."),
        .init("dumbbell-hammer-curl", "Молотковые сгибания", .dumbbells, [.biceps, .forearms], [], "Поднимайте гантели с ладонями, повёрнутыми друг к другу. Локти остаются рядом с корпусом.", target: 12),
        .init("dumbbell-rear-fly", "Разведения гантелей в наклоне", .dumbbells, [.shoulders, .upperBack], [.lowerBack], "Наклонитесь за счёт движения таза. Разведите руки с мягкими локтями в стороны и опустите с контролем.", target: 12),
        .init("dumbbell-pullover", "Пуловер с гантелью на полу", .dumbbells, [.lats, .chest], [.triceps], "Лягте на спину и держите одну гантель над грудью. Плавно заведите её за голову до удобной амплитуды."),
        .init("dumbbell-single-rdl", "Румынская тяга на одной ноге", .dumbbells, [.hamstrings, .glutes], [.abs, .lowerBack], "Слегка согните опорное колено. Наклоняйтесь, отводя свободную ногу назад и удерживая таз параллельно полу.", target: 8),
        .init("band-overhead-press", "Жим резинки над головой", .band, [.shoulders, .triceps], [.abs], "Наступите на резинку обеими стопами. Выжмите руки вверх от плеч, удерживая рёбра над тазом."),
        .init("band-glute-bridge", "Ягодичный мост с резинкой", .band, [.glutes], [.hamstrings], "Разместите петлю выше колен. Поднимайте таз, сохраняя колени на ширине стоп.", target: 12),
        .init("chin-up", "Подтягивания обратным хватом", .bar, [.lats, .biceps], [.upperBack, .forearms], "Возьмитесь за перекладину ладонями к себе. Согните локти, поднимитесь без раскачивания и опуститесь с контролем.", target: 5),
        .init("scapular-pull-up", "Лопаточные подтягивания", .bar, [.upperBack, .lats], [.forearms], "Повисните на прямых руках. Опустите плечи и слегка поднимите корпус движением лопаток, сохраняя локти прямыми.", target: 8)
    ]

    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    private static let byName = Dictionary(uniqueKeysWithValues: all.map { (normalize($0.name), $0) })

    static func normalize(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased().replacingOccurrences(of: "ё", with: "е")
    }

    static func find(_ plan: ExercisePlan) -> ExercisePreset? {
        guard plan.isCustom != true else { return nil }
        if let id = plan.catalogID, let preset = byID[id] { return preset }
        return byName[normalize(plan.name)]
    }
}

extension ExercisePlan {
    var muscles: MuscleSelection {
        if let muscleOverride { return muscleOverride }
        guard let preset = ExerciseCatalog.find(self) else { return MuscleSelection() }
        return MuscleSelection(primary: preset.primary, secondary: preset.secondary)
    }
}
