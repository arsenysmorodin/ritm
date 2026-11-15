typealias Joint = (x: Double, y: Double)

struct TechniquePose {
    let head: Joint
    let shoulder: Joint
    let hip: Joint
    let spine: Joint?
    let frontArm: [Joint]
    let rearArm: [Joint]
    let frontLeg: [Joint]
    let rearLeg: [Joint]

    init(head: Joint, shoulder: Joint, hip: Joint, arm: [Joint], leg: [Joint],
         otherArm: [Joint]? = nil, otherLeg: [Joint]? = nil, spine: Joint? = nil) {
        self.head = head
        self.shoulder = shoulder
        self.hip = hip
        self.spine = spine
        frontArm = [shoulder] + arm
        rearArm = otherArm.map { [shoulder] + $0 } ?? []
        frontLeg = [hip] + leg
        rearLeg = otherLeg.map { [hip] + $0 } ?? []
    }

    var torso: [Joint] { [shoulder, spine, hip].compactMap { $0 } }

    func arms(_ arm: [Joint], _ otherArm: [Joint]? = nil) -> Self {
        Self(head: head, shoulder: shoulder, hip: hip, arm: arm, leg: Array(frontLeg.dropFirst()),
             otherArm: otherArm, otherLeg: rearLeg.isEmpty ? nil : Array(rearLeg.dropFirst()), spine: spine)
    }
}

struct TechniqueFrame {
    let pose: TechniquePose
    let label: String
    var props: [[Joint]] = []
    var hasWeights = false
    var band: [Joint]? = nil
}

enum ExerciseTechnique {
    static func frames(for id: String) -> [TechniqueFrame] {
        switch id {
        case "squat": pair(standing, squat, "Опустите таз")
        case "sumo-squat": pair(wide, wideSquat, "Колени по линии стоп")
        case "goblet-squat": pair(standing.arms([(57, 47), (61, 36)]), squat.arms([(49, 58), (57, 49)]), "Гантель у груди", weights: true)
        case "chair-squat": pair(standing, squat, "Коснитесь сиденья", props: chairBehind)
        case "squat-jump": pair(squat, jump, "Прыгните вверх")
        case "wall-sit": [TechniqueFrame(pose: wallSit, label: "Удерживайте положение", props: [[(26, 16), (26, 94)]])]
        case "forward-lunge": pair(standing, splitLunge, "Шагните вперёд")
        case "reverse-lunge": pair(standing, rearLunge, "Шагните назад")
        case "lateral-lunge": pair(wide, lateralLunge, "Таз к опорной ноге")
        case "step-up": pair(stepStart, stepEnd, "Поднимитесь на опору", props: stepProp)
        case "split-squat": pair(splitStanding, splitSquat, "Опуститесь на передней ноге", props: rearStep)
        case "calf-raise": pair(standing, calves, "Поднимите пятки")
        case "hinge": pair(standing, hinge, "Отведите таз назад")
        case "dumbbell-rdl": pair(standing, hinge, "Гантели близко к ногам", weights: true)
        case "dumbbell-single-rdl": pair(standing, singleHinge, "Отведите ногу назад", weights: true)
        case "push-up": pair(highPlank, lowPush, "Грудь к полу")
        case "close-push-up": pair(highPlank.arms([(75, 72), (76, 94)], [(70, 72), (71, 94)]), lowPush.arms([(62, 70), (76, 94)], [(58, 71), (71, 94)]), "Локти вдоль корпуса")
        case "knee-push-up": pair(kneePush, kneePushLow, "Грудь к полу")
        case "incline-push-up": pair(incline, inclineLow, "Грудь к опоре", props: frontBench)
        case "pike-push-up": pair(pike, pikeLow, "Макушка к полу")
        case "high-plank": hold(highPlank, "Кисти под плечами")
        case "plank": hold(plank, "Локти под плечами")
        case "side-plank": hold(sidePlank, "Таз поднят")
        case "shoulder-tap": pair(widePlank, widePlank.arms([(67, 49), (58, 35)], [(50, 55), (45, 72)]), "Коснитесь плеча")
        case "bridge": pair(bridgeDown, bridgeUp, "Поднимите таз")
        case "single-bridge": pair(singleBridgeDown, singleBridge, "Таз вверх, нога вытянута")
        case "band-glute-bridge":
            [TechniqueFrame(pose: bridgeDown, label: "Стопы на полу", band: [(73, 63), (82, 63)]),
             TechniqueFrame(pose: bridgeUp, label: "Таз вверх", band: [(72, 59), (81, 59)])]
        case "side-leg-raise": pair(sideDown, sideLift, "Поднимите верхнюю ногу")
        case "clamshell": pair(closedClam, openClam, "Поднимите верхнее колено")
        case "donkey-kick": pair(quadruped, kick, "Согнутое колено назад")
        case "bird-dog": pair(quadruped, birdDog, "Вытяните руку и ногу")
        case "cat-cow": pair(cat, cow, "Мягко разогните спину", start: "Округлите спину")
        case "child-pose": hold(child, "Таз к пяткам")
        case "bear-crawl": pair(bear, bearStep, "Шаг рукой и ногой")
        case "dead-bug": pair(deadBug, deadBugLong, "Противоположные рука и нога")
        case "crunch": pair(crunchDown, crunchUp, "Поднимите лопатки")
        case "reverse-crunch": pair(reverseDown, reverseUp, "Подкрутите таз")
        case "hollow-hold": hold(hollow, "Поясница на полу")
        case "mountain-climber": pair(highPlank, climber, "Колено к корпусу")
        case "jumping-jack": pair(standing, jumpingJack, "Руки вверх, стопы шире")
        case "high-knees": pair(standing, highKnees, "Поднимите колено")
        case "burpee":
            [TechniqueFrame(pose: standing, label: "Стойка"),
             TechniqueFrame(pose: burpeeDown, label: "Руки на пол"),
             TechniqueFrame(pose: highPlank, label: "Планка")]
        case "hip-stretch": hold(hipStretch, "Таз мягко вперёд")
        case "ankle-rock": pair(ankleStart, ankleEnd, "Колено к стене", props: [[(90, 37), (90, 94)]])
        case "thoracic-rotation": pair(quadruped, thoracic, "Разверните грудную клетку")
        case "trunk-rotation": pair(wide.arms([(44, 44), (58, 48)], [(66, 44), (54, 48)]),
                                    wide.arms([(47, 46), (35, 45)], [(60, 40), (43, 43)]), "Поверните плечи")
        case "dumbbell-row": pair(hinge, hinge.arms([(62, 49), (63, 64)], [(57, 49), (57, 62)]), "Локти к корпусу", weights: true)
        case "dumbbell-floor-press": pair(floorPress, floorPress.arms([(36, 60), (36, 41)], [(29, 61), (29, 42)]), "Выжмите вверх", weights: true)
        case "dumbbell-pullover": pair(floorPress.arms([(36, 59), (37, 40)]), floorPress.arms([(19, 65), (10, 74)]), "Заведите за голову", weights: true)
        case "dumbbell-press": pair(pressSet, pressUp, "Выжмите вверх", weights: true)
        case "dumbbell-lateral-raise": pair(wide, wide.arms([(75, 35), (92, 36)], [(39, 35), (22, 36)]), "Руки в стороны", weights: true)
        case "dumbbell-rear-fly": pair(hinge, hinge.arms([(80, 33), (96, 39)], [(60, 30), (47, 34)]), "Разведите руки", weights: true)
        case "dumbbell-curl", "dumbbell-hammer-curl": pair(standing, standing.arms([(54, 49), (62, 35)], [(49, 49), (56, 36)]), "Согните локти", weights: true)
        case "dumbbell-extension": pair(pressUp.arms([(50, 24), (41, 31)]), pressUp.arms([(50, 21), (50, 11)]), "Разогните локти", weights: true)
        case "farmer-carry": pair(standing, walking, "Шагайте ровно", weights: true)
        case "band-row":
            [TechniqueFrame(pose: standing.arms([(71, 46), (84, 46)]), label: "Руки вперёд", band: [(84, 46), (103, 46)]),
             TechniqueFrame(pose: standing.arms([(48, 49), (66, 48)]), label: "Локти назад", band: [(66, 48), (103, 46)])]
        case "band-pull-apart":
            [TechniqueFrame(pose: wide.arms([(49, 39), (48, 41)], [(65, 39), (66, 41)]), label: "Руки перед грудью", band: [(48, 41), (66, 41)]),
             TechniqueFrame(pose: wide.arms([(78, 35), (91, 37)], [(35, 35), (22, 37)]), label: "Разведите руки", band: [(22, 37), (91, 37)])]
        case "band-walk":
            [TechniqueFrame(pose: wideSquat, label: "Согните колени", band: [(32, 83), (81, 83)]),
             TechniqueFrame(pose: lateralLunge, label: "Шаг в сторону", band: [(35, 83), (86, 83)])]
        case "band-pallof":
            [TechniqueFrame(pose: standing.arms([(58, 48), (62, 39)]), label: "Кисти у груди", band: [(63, 39), (97, 42)]),
             TechniqueFrame(pose: standing.arms([(73, 37), (85, 37)]), label: "Руки вперёд", band: [(85, 37), (97, 42)])]
        case "band-overhead-press":
            [TechniqueFrame(pose: pressSet, label: "Кисти у плеч", band: [(36, 30), (45, 91), (66, 91), (75, 30)]),
             TechniqueFrame(pose: pressUp, label: "Выжмите вверх", band: [(48, 13), (45, 91), (66, 91), (64, 13)])]
        case "hang": [TechniqueFrame(pose: hang, label: "Повисните на перекладине", props: bar)]
        case "pull-up", "chin-up": pair(hang, pullUp, "Подбородок к перекладине", props: bar)
        case "scapular-pull-up": pair(hang, scapular, "Опустите плечи", props: bar)
        default: []
        }
    }

    private static func pair(_ a: TechniquePose, _ b: TechniquePose, _ end: String,
                             start: String = "Исходное положение", props: [[Joint]] = [], weights: Bool = false) -> [TechniqueFrame] {
        [TechniqueFrame(pose: a, label: start, props: props, hasWeights: weights),
         TechniqueFrame(pose: b, label: end, props: props, hasWeights: weights)]
    }

    private static func hold(_ pose: TechniquePose, _ label: String) -> [TechniqueFrame] {
        [TechniqueFrame(pose: pose, label: label)]
    }

    private static let chairBehind: [[Joint]] = [[(9, 63), (33, 63), (33, 94)], [(9, 43), (9, 94)]]
    private static let stepProp: [[Joint]] = [[(58, 94), (58, 71), (90, 71), (90, 94)]]
    private static let rearStep: [[Joint]] = [[(12, 94), (12, 72), (32, 72), (32, 94)]]
    private static let frontBench: [[Joint]] = [[(68, 94), (68, 61), (99, 61), (99, 94)]]
    private static let bar: [[Joint]] = [[(25, 14), (85, 14)]]

    private static let standing = TechniquePose(head: (57, 18), shoulder: (54, 30), hip: (52, 56),
        arm: [(54, 47), (56, 63)], leg: [(54, 76), (53, 92), (62, 93)],
        otherArm: [(48, 47), (49, 62)], otherLeg: [(48, 76), (46, 92), (54, 93)])
    private static let wide = TechniquePose(head: (55, 18), shoulder: (55, 30), hip: (55, 55),
        arm: [(68, 46), (70, 62)], leg: [(70, 73), (79, 91), (86, 93)],
        otherArm: [(43, 46), (41, 62)], otherLeg: [(40, 73), (31, 91), (24, 93)])
    private static let squat = TechniquePose(head: (62, 42), shoulder: (54, 50), hip: (35, 66),
        arm: [(65, 53), (78, 52)], leg: [(60, 69), (50, 90), (61, 93)],
        otherArm: [(62, 57), (73, 54)], otherLeg: [(56, 70), (45, 90), (55, 93)])
    private static let wideSquat = TechniquePose(head: (55, 36), shoulder: (55, 48), hip: (55, 69),
        arm: [(64, 61), (56, 60)], leg: [(77, 69), (80, 91), (90, 93)],
        otherArm: [(46, 61), (54, 60)], otherLeg: [(33, 69), (30, 91), (20, 93)])
    private static let lateralLunge = TechniquePose(head: (70, 36), shoulder: (65, 48), hip: (62, 67),
        arm: [(68, 64), (77, 59)], leg: [(86, 67), (86, 91), (96, 93)],
        otherArm: [(58, 60), (73, 58)], otherLeg: [(43, 78), (27, 91), (19, 93)])
    private static let jump = TechniquePose(head: (58, 13), shoulder: (54, 24), hip: (51, 49),
        arm: [(68, 23), (76, 12)], leg: [(53, 67), (49, 83), (57, 87)],
        otherArm: [(40, 26), (32, 16)], otherLeg: [(47, 68), (44, 82), (51, 86)])
    private static let calves = TechniquePose(head: (57, 10), shoulder: (54, 22), hip: (52, 48),
        arm: [(54, 40), (56, 55)], leg: [(54, 69), (53, 87), (62, 94)], otherLeg: [(49, 69), (47, 87), (56, 94)])
    private static let wallSit = TechniquePose(head: (33, 35), shoulder: (30, 46), hip: (30, 69),
        arm: [(43, 56), (56, 65)], leg: [(58, 70), (58, 92), (68, 94)], otherLeg: [(53, 72), (53, 92), (64, 94)])
    private static let splitLunge = TechniquePose(head: (63, 40), shoulder: (60, 51), hip: (57, 73),
        arm: [(61, 65), (66, 73)], leg: [(81, 70), (81, 91), (92, 94)], otherLeg: [(44, 90), (28, 88), (25, 94)])
    private static let rearLunge = TechniquePose(head: (53, 40), shoulder: (51, 51), hip: (49, 73),
        arm: [(54, 64), (62, 70)], leg: [(72, 72), (69, 91), (80, 94)], otherLeg: [(35, 90), (16, 87), (15, 94)])
    private static let stepStart = TechniquePose(head: (52, 19), shoulder: (50, 31), hip: (44, 57),
        arm: [(60, 46), (68, 42)], leg: [(63, 52), (68, 71), (78, 71)], otherLeg: [(40, 74), (41, 91), (51, 94)])
    private static let stepEnd = TechniquePose(head: (74, 9), shoulder: (71, 19), hip: (69, 38),
        arm: [(68, 33), (75, 41)], leg: [(71, 52), (70, 69), (79, 71)], otherLeg: [(59, 52), (62, 68), (69, 71)])
    private static let splitStanding = TechniquePose(head: (63, 22), shoulder: (62, 33), hip: (57, 56),
        arm: [(57, 46), (61, 57)], leg: [(69, 73), (76, 92), (85, 94)], otherLeg: [(39, 70), (22, 71), (27, 72)])
    private static let splitSquat = TechniquePose(head: (63, 41), shoulder: (62, 52), hip: (54, 73),
        arm: [(58, 63), (64, 69)], leg: [(78, 70), (78, 91), (88, 93)], otherLeg: [(37, 90), (23, 73), (29, 72)])
    private static let hinge = TechniquePose(head: (81, 30), shoulder: (70, 39), hip: (40, 58),
        arm: [(69, 55), (67, 72)], leg: [(54, 73), (51, 91), (62, 94)],
        otherArm: [(64, 55), (63, 70)], otherLeg: [(49, 73), (46, 91), (56, 94)])
    private static let singleHinge = TechniquePose(head: (88, 42), shoulder: (76, 49), hip: (52, 53),
        arm: [(75, 66), (74, 77)], leg: [(56, 73), (58, 92), (68, 94)], otherLeg: [(34, 51), (13, 51), (9, 57)])

    private static let highPlank = TechniquePose(head: (89, 54), shoulder: (78, 64), hip: (49, 74),
        arm: [(77, 77), (78, 94)], leg: [(33, 81), (16, 88), (16, 94)], otherLeg: [(29, 82), (11, 90), (11, 94)])
    private static let lowPush = TechniquePose(head: (88, 72), shoulder: (77, 77), hip: (49, 84),
        arm: [(61, 78), (78, 93)], leg: [(33, 85), (15, 89), (15, 94)], otherLeg: [(28, 86), (11, 90), (11, 94)])
    private static let kneePush = TechniquePose(head: (88, 48), shoulder: (78, 60), hip: (52, 76),
        arm: [(77, 77), (78, 94)], leg: [(32, 92), (15, 86), (12, 90)])
    private static let kneePushLow = TechniquePose(head: (88, 69), shoulder: (77, 76), hip: (52, 85),
        arm: [(62, 76), (78, 94)], leg: [(32, 92), (15, 86), (12, 90)])
    private static let incline = TechniquePose(head: (89, 22), shoulder: (79, 32), hip: (49, 58),
        arm: [(82, 47), (84, 61)], leg: [(31, 75), (15, 91), (13, 94)])
    private static let inclineLow = TechniquePose(head: (91, 43), shoulder: (78, 48), hip: (48, 67),
        arm: [(65, 47), (84, 61)], leg: [(31, 80), (15, 91), (13, 94)])
    private static let pike = TechniquePose(head: (78, 66), shoulder: (69, 58), hip: (47, 33),
        arm: [(72, 74), (75, 94)], leg: [(31, 61), (19, 91), (24, 94)])
    private static let pikeLow = TechniquePose(head: (83, 81), shoulder: (73, 69), hip: (49, 39),
        arm: [(61, 77), (76, 94)], leg: [(32, 65), (19, 91), (23, 94)])
    private static let plank = TechniquePose(head: (91, 59), shoulder: (76, 71), hip: (49, 77),
        arm: [(72, 92), (92, 94)], leg: [(33, 82), (14, 89), (12, 94)])
    private static let sidePlank = TechniquePose(head: (86, 50), shoulder: (78, 62), hip: (52, 72),
        arm: [(76, 91), (93, 93)], leg: [(34, 79), (16, 89), (13, 94)], otherArm: [(77, 42), (74, 27)])
    private static let widePlank = TechniquePose(head: (56, 19), shoulder: (56, 32), hip: (56, 58),
        arm: [(72, 52), (77, 71)], leg: [(70, 74), (82, 89), (92, 91)],
        otherArm: [(42, 52), (36, 71)], otherLeg: [(42, 74), (28, 89), (19, 91)])
    private static let climber = TechniquePose(head: highPlank.head, shoulder: highPlank.shoulder, hip: highPlank.hip,
        arm: [(77, 77), (78, 94)], leg: [(64, 82), (44, 92), (38, 94)], otherLeg: [(31, 81), (12, 90), (12, 94)])

    private static let bridgeDown = TechniquePose(head: (16, 84), shoulder: (29, 89), hip: (52, 89),
        arm: [(43, 93), (59, 93)], leg: [(74, 60), (86, 91), (97, 93)], otherLeg: [(69, 62), (81, 91), (92, 93)])
    private static let bridgeUp = TechniquePose(head: (16, 83), shoulder: (29, 89), hip: (54, 71),
        arm: [(42, 91), (61, 93)], leg: [(74, 58), (86, 91), (97, 93)], otherLeg: [(70, 60), (81, 91), (93, 93)])
    private static let singleBridge = TechniquePose(head: (16, 83), shoulder: (29, 89), hip: (54, 71),
        arm: [(42, 91), (61, 93)], leg: [(76, 57), (95, 49), (99, 50)], otherLeg: [(71, 60), (82, 91), (94, 93)])
    private static let singleBridgeDown = TechniquePose(head: (16, 83), shoulder: (29, 89), hip: (52, 89),
        arm: [(42, 91), (61, 93)], leg: [(74, 75), (94, 64), (100, 65)], otherLeg: [(71, 60), (82, 91), (94, 93)])
    private static let sideDown = TechniquePose(head: (20, 73), shoulder: (35, 81), hip: (60, 85),
        arm: [(22, 91), (17, 79)], leg: [(78, 86), (97, 87), (101, 82)], otherLeg: [(79, 91), (97, 92), (102, 88)])
    private static let sideLift = TechniquePose(head: (20, 73), shoulder: (35, 81), hip: (60, 85),
        arm: [(22, 91), (17, 79)], leg: [(76, 69), (91, 55), (96, 56)], otherLeg: [(79, 91), (97, 92), (102, 88)])
    private static let closedClam = TechniquePose(head: (18, 72), shoulder: (33, 80), hip: (57, 85),
        arm: [(22, 92), (15, 79)], leg: [(86, 78), (75, 91), (69, 93)], otherLeg: [(85, 83), (75, 91), (69, 93)])
    private static let openClam = TechniquePose(head: (18, 72), shoulder: (33, 80), hip: (57, 85),
        arm: [(22, 92), (15, 79)], leg: [(77, 62), (75, 91), (69, 93)], otherLeg: [(85, 83), (75, 91), (69, 93)])
    private static let quadruped = TechniquePose(head: (86, 50), shoulder: (73, 59), hip: (43, 60),
        arm: [(73, 76), (73, 94)], leg: [(44, 91), (23, 92)], otherArm: [(68, 76), (68, 94)], otherLeg: [(40, 89), (20, 91)])
    private static let kick = TechniquePose(head: quadruped.head, shoulder: quadruped.shoulder, hip: quadruped.hip,
        arm: [(73, 76), (73, 94)], leg: [(23, 58), (22, 38), (28, 37)], otherArm: [(68, 76), (68, 94)], otherLeg: [(43, 91), (22, 92)])
    private static let birdDog = TechniquePose(head: (87, 50), shoulder: (73, 59), hip: (43, 60),
        arm: [(85, 55), (101, 53)], leg: [(43, 91), (22, 92)], otherArm: [(68, 76), (68, 94)], otherLeg: [(25, 60), (9, 60), (7, 65)])
    private static let cat = TechniquePose(head: (78, 68), shoulder: (72, 57), hip: (42, 52),
        arm: [(72, 74), (73, 94)], leg: [(43, 91), (21, 94)], otherLeg: [(38, 89), (16, 92)], spine: (55, 45))
    private static let cow = TechniquePose(head: (85, 43), shoulder: (72, 57), hip: (42, 62),
        arm: [(72, 75), (73, 94)], leg: [(43, 91), (21, 94)], otherLeg: [(38, 89), (16, 92)], spine: (55, 68))
    private static let thoracic = TechniquePose(head: (77, 49), shoulder: (72, 59), hip: (43, 60),
        arm: [(78, 39), (80, 19)], leg: [(44, 91), (23, 92)], otherArm: [(68, 76), (68, 94)], otherLeg: [(40, 89), (20, 91)])
    private static let child = TechniquePose(head: (68, 79), shoulder: (57, 76), hip: (30, 84),
        arm: [(74, 87), (99, 92)], leg: [(55, 93), (25, 93)], otherLeg: [(51, 91), (21, 92)])
    private static let bear = TechniquePose(head: (83, 48), shoulder: (71, 58), hip: (40, 57),
        arm: [(72, 74), (72, 94)], leg: [(43, 81), (22, 91)], otherArm: [(67, 74), (67, 93)], otherLeg: [(39, 79), (19, 91)])
    private static let bearStep = TechniquePose(head: (87, 47), shoulder: (75, 56), hip: (44, 59),
        arm: [(80, 73), (87, 93)], leg: [(39, 84), (20, 92)], otherArm: [(68, 73), (64, 93)], otherLeg: [(52, 80), (39, 92)])

    private static let deadBug = TechniquePose(head: (16, 83), shoulder: (28, 90), hip: (52, 90),
        arm: [(34, 72), (35, 54)], leg: [(58, 65), (78, 65)], otherArm: [(30, 73), (31, 55)], otherLeg: [(55, 65), (74, 63)])
    private static let deadBugLong = TechniquePose(head: (16, 83), shoulder: (28, 90), hip: (52, 90),
        arm: [(19, 74), (7, 67)], leg: [(55, 64), (75, 64)], otherArm: [(35, 70), (35, 54)], otherLeg: [(73, 82), (94, 76), (99, 78)])
    private static let crunchDown = bridgeDown.arms([(34, 73), (18, 79)])
    private static let crunchUp = TechniquePose(head: (24, 64), shoulder: (37, 75), hip: (54, 89),
        arm: [(45, 64), (28, 62)], leg: [(74, 59), (86, 91), (96, 93)], otherLeg: [(69, 60), (81, 91), (92, 93)])
    private static let reverseDown = deadBug.arms([(42, 92), (61, 92)])
    private static let reverseUp = TechniquePose(head: (17, 83), shoulder: (30, 89), hip: (52, 77),
        arm: [(42, 92), (61, 93)], leg: [(47, 53), (63, 49)], otherLeg: [(43, 55), (59, 51)])
    private static let hollow = TechniquePose(head: (23, 71), shoulder: (35, 82), hip: (57, 89),
        arm: [(24, 61), (12, 49)], leg: [(77, 77), (96, 67), (101, 68)], otherLeg: [(77, 82), (95, 73), (101, 72)])
    private static let jumpingJack = TechniquePose(head: (55, 18), shoulder: (55, 30), hip: (55, 55),
        arm: [(72, 20), (76, 8)], leg: [(75, 72), (91, 91), (99, 94)],
        otherArm: [(38, 20), (34, 8)], otherLeg: [(35, 72), (19, 91), (11, 94)])
    private static let highKnees = TechniquePose(head: (57, 18), shoulder: (54, 30), hip: (52, 55),
        arm: [(53, 46), (69, 39)], leg: [(75, 55), (70, 74), (77, 77)],
        otherArm: [(46, 47), (37, 52)], otherLeg: [(51, 76), (49, 92), (57, 94)])
    private static let burpeeDown = TechniquePose(head: (76, 60), shoulder: (66, 68), hip: (43, 67),
        arm: [(71, 81), (72, 94)], leg: [(58, 78), (49, 92), (58, 94)], otherLeg: [(52, 80), (43, 92), (52, 93)])
    private static let hipStretch = TechniquePose(head: (66, 39), shoulder: (63, 49), hip: (56, 72),
        arm: [(70, 63), (78, 73)], leg: [(80, 73), (80, 92), (91, 93)], otherLeg: [(40, 92), (22, 92)])
    private static let ankleStart = TechniquePose(head: (64, 24), shoulder: (63, 36), hip: (58, 62),
        arm: [(75, 53), (89, 53)], leg: [(71, 73), (70, 91), (81, 93)], otherLeg: [(50, 78), (45, 92), (53, 93)])
    private static let ankleEnd = TechniquePose(head: (70, 26), shoulder: (68, 38), hip: (64, 62),
        arm: [(76, 55), (89, 53)], leg: [(87, 75), (70, 91), (81, 93)], otherLeg: [(53, 77), (45, 92), (53, 93)])

    private static let pressSet = wide.arms([(72, 46), (75, 30)], [(39, 46), (36, 30)])
    private static let pressUp = wide.arms([(62, 23), (64, 12)], [(51, 23), (48, 12)])
    private static let floorPress = bridgeDown.arms([(38, 88), (39, 69)], [(23, 87), (23, 69)])
    private static let walking = TechniquePose(head: (58, 18), shoulder: (54, 30), hip: (53, 55),
        arm: [(54, 46), (56, 63)], leg: [(65, 74), (74, 92), (85, 94)], otherArm: [(49, 47), (50, 62)], otherLeg: [(43, 76), (32, 86), (34, 94)])
    private static let hang = TechniquePose(head: (55, 42), shoulder: (55, 52), hip: (55, 72),
        arm: [(71, 36), (73, 14)], leg: [(60, 82), (61, 91)], otherArm: [(39, 36), (37, 14)], otherLeg: [(50, 82), (49, 91)])
    private static let pullUp = TechniquePose(head: (55, 12), shoulder: (55, 27), hip: (55, 53),
        arm: [(74, 32), (73, 14)], leg: [(60, 67), (61, 79)], otherArm: [(36, 32), (37, 14)], otherLeg: [(50, 67), (49, 79)])
    private static let scapular = TechniquePose(head: (55, 35), shoulder: (55, 46), hip: (55, 67),
        arm: [(66, 28), (73, 14)], leg: [(60, 78), (61, 88)], otherArm: [(44, 28), (37, 14)], otherLeg: [(50, 78), (49, 88)])
}
