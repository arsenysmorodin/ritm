import XCTest

final class HealthOSUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() { super.setUp(); continueAfterFailure = false }

    private func launch(fixtures: Bool = false, dark: Bool = false, large: Bool = false, compact: Bool = false, reversal: Bool = false, workout: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["--ritm-ui-testing", "--ritm-ui-session", UUID().uuidString, "--ritm-ui-accent", "lime", "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXL" : "UICTContentSizeCategoryL"]
        if fixtures { app.launchArguments.append("--ritm-ui-fixtures") }
        if dark { app.launchArguments.append("--ritm-ui-dark") }
        if large { app.launchArguments.append("--ritm-ui-large-text") }
        if compact { app.launchArguments.append("--ritm-ui-compact") }
        if reversal { app.launchArguments.append("--ritm-ui-reversal") }
        if workout { app.launchArguments.append("--ritm-ui-workout") }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Сегодня"].waitForExistence(timeout: 20))
    }
    private func reveal(_ element: XCUIElement, attempts: Int = 8) {
        for _ in 0..<attempts {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "Не найден элемент: \(element)")
    }
    private func capture(_ name: String) {
        // Capture the settled layout rather than a frame of a numeric transition.
        let settle = expectation(description: "Завершены короткие анимации")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { settle.fulfill() }
        wait(for: [settle], timeout: 2)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func audit() throws {
        continueAfterFailure = true
        defer { continueAfterFailure = false }
        try app.performAccessibilityAudit(for: [.elementDetection, .sufficientElementDescription, .textClipped])
    }
    private func alignWaterForAudit() {
        // Audit a settled viewport. Partially visible labels from the preceding
        // card are ordinary ScrollView clipping, not intrinsic text truncation.
        let heading = app.staticTexts["Вода"].firstMatch
        XCTAssertTrue(heading.exists)
        for _ in 0..<4 {
            let distance = heading.frame.minY - 90
            if abs(distance) < 12 { break }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.75))
            let end = start.withOffset(CGVector(dx: 0, dy: -min(max(distance, -350), 350)))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.15)
        }
    }
    private func replace(_ field: XCUIElement, text: String) {
        field.tap()
        if app.buttons["event.clearAmount"].exists {
            app.buttons["event.clearAmount"].tap(); field.tap()
        } else { field.doubleTap() }
        field.typeText(text)
        let typed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", text), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [typed], timeout: 8), .completed)
    }

    func testWorkoutPulseDeleteSetAndUndo() throws {
        launch(dark: true, workout: true)
        app.tabBars.buttons["Тренировки"].tap()
        let resume = app.buttons["Продолжить тренировку"]
        reveal(resume); resume.tap()
        XCTAssertTrue(app.staticTexts["120"].waitForExistence(timeout: 10))
        let rows = app.buttons.matching(identifier: "workout.set.edit")
        reveal(rows.firstMatch)
        XCTAssertEqual(rows.count, 3)
        capture("workout-live-pulse")
        rows.firstMatch.tap()
        let delete = app.buttons["workout.set.delete"]
        reveal(delete); delete.tap()
        let undo = app.buttons["workout.set.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 2)
        capture("workout-deleted-set")
        undo.tap()
        XCTAssertEqual(rows.count, 3)
        XCTAssertFalse(undo.exists)
        try audit()
    }

    func testProactiveNotificationSettingsPersist() {
        launch()
        app.buttons["today.settings"].tap()
        let settings = app.buttons["Привычки и уведомления"]
        reveal(settings); settings.tap()
        let morning = app.switches["notifications.morning"]
        reveal(morning); XCTAssertEqual(morning.value as? String, "0")
        morning.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        capture("notifications-after-morning-toggle")
        XCTAssertEqual(morning.value as? String, "1", app.debugDescription)
        let time = app.staticTexts["Время обзора"]
        reveal(time)
        let evening = app.switches["notifications.checkIn"]
        reveal(evening); evening.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let changes = app.switches["notifications.changes"]
        reveal(changes); changes.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        capture("proactive-notifications")
        addUIInterruptionMonitor(withDescription: "Уведомления") { alert in
            for label in ["Разрешить", "Allow"] {
                let allow = alert.buttons[label]
                if allow.exists { allow.tap(); return true }
            }
            return false
        }
        app.buttons["Сохранить"].tap()
        let systemAlert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if systemAlert.waitForExistence(timeout: 3) {
            for label in ["Разрешить", "Allow"] where systemAlert.buttons[label].exists { systemAlert.buttons[label].tap(); break }
        }
        if app.buttons["Понятно"].exists { app.buttons["Понятно"].tap() }
        if app.buttons["Отмена"].exists { app.buttons["Отмена"].tap() }
        XCTAssertTrue(settings.waitForExistence(timeout: 8)); settings.tap()
        reveal(morning); XCTAssertEqual(morning.value as? String, "1")
        reveal(evening); XCTAssertEqual(evening.value as? String, "1")
        reveal(changes); XCTAssertEqual(changes.value as? String, "1")
    }

    func testWorkoutControlsWithAccessibilityText() {
        launch(dark: true, large: true, workout: true)
        app.tabBars.buttons["Тренировки"].tap()
        let resume = app.buttons["Продолжить тренировку"]
        reveal(resume); resume.tap()
        let mark = app.buttons["Отметить подход"]
        XCTAssertTrue(mark.waitForExistence(timeout: 10))
        XCTAssertTrue(mark.isHittable)
        XCTAssertTrue(app.staticTexts["120"].exists)
        capture("workout-accessibility-text")
    }

    func testWaterQuickAddUndoAndCustomVolume() {
        launch()
        let water = app.buttons["water.add.250"]
        reveal(water); water.tap()
        let total = app.descendants(matching: .any)["water.total"].firstMatch
        XCTAssertEqual(total.value as? String, "250")
        app.buttons["Отменить"].tap()
        XCTAssertEqual(total.value as? String, "0")
        app.buttons["Другой объём"].tap()
        let amount = app.textFields["event.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        replace(amount, text: "375")
        XCTAssertEqual(amount.value as? String, "375")
        app.buttons["event.save"].tap()
        XCTAssertTrue(water.waitForExistence(timeout: 5))
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5))
        XCTAssertEqual(total.value as? String, "375")
        capture("water-light")
    }

    func testCreateSupplementMarkDoseAndSeeIngredientTotal() {
        launch()
        app.tabBars.buttons["Сегодня"].tap()
        let supplements = app.buttons["health.supplements"]
        reveal(supplements); supplements.tap()
        app.buttons["Добавить продукт"].tap()
        let name = app.textFields["supplement.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Тестовый комплекс")
        app.buttons["Добавить ингредиент"].tap()
        app.textFields["Активное вещество"].tap(); app.textFields["Активное вещество"].typeText("Магний")
        replace(app.textFields["Количество"], text: "100")
        app.navigationBars.buttons["Сохранить"].tap()
        let take = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Принять' ")).firstMatch
        XCTAssertTrue(take.waitForExistence(timeout: 5)); reveal(take); take.tap()
        XCTAssertTrue(app.staticTexts["Суммарно за день"].waitForExistence(timeout: 5))
        reveal(app.staticTexts["100 мг"])
        XCTAssertTrue(app.staticTexts["100 мг"].exists)
        XCTAssertFalse(take.exists)
        capture("supplements-dose")
    }

    func testHealthOSHistoryInsightsAndExperimentScreens() {
        launch(fixtures: true, dark: true)
        app.tabBars.buttons["Сегодня"].tap()
        capture("health-os-dark")
        let timeline = app.buttons["health.timeline"]
        reveal(timeline); timeline.tap()
        XCTAssertTrue(app.staticTexts["Тестовые данные симулятора"].waitForExistence(timeout: 5))
        capture("timeline-dark")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let insights = app.buttons["health.insights"]
        reveal(insights); insights.tap()
        XCTAssertTrue(app.segmentedControls["insights.period"].waitForExistence(timeout: 5))
        capture("insights-dark")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let experiments = app.buttons["health.experiments"]
        reveal(experiments); experiments.tap()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'experiment.'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Условие соблюдено"].waitForExistence(timeout: 5))
        app.buttons["Условие соблюдено"].tap()
        XCTAssertTrue(app.buttons["Соблюдено ✓"].exists)
        capture("experiment-dark")
    }

    func testLargeTextAndAccessibilityOnWaterScreen() throws {
        launch(large: true)
        capture("bento-accessibility3")
        try audit()
        let water = app.buttons["water.add.250"]
        reveal(water); water.tap()
        alignWaterForAudit()
        capture("water-accessibility3")
        try audit()
    }

    func testDynamicsOverviewPeriodChartAndNumericPulseHistory() {
        launch(fixtures: true, dark: true)
        app.tabBars.buttons["Динамика"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["comparison.delta"].firstMatch.waitForExistence(timeout: 8))
        capture("dynamics-dark-overview")
        app.segmentedControls["insights.period"].buttons["7 дней"].tap()
        let chart = app.descendants(matching: .any)["insights.chart"].firstMatch
        reveal(chart)
        let chartValue = app.descendants(matching: .any)["insights.chartValue"].firstMatch
        let before = chartValue.label
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", before), object: chartValue)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        capture("dynamics-chart-selection")
        app.buttons["insights.all"].tap()
        let pulse = app.buttons["insights.list.restingPulse"]
        reveal(pulse); pulse.tap()
        XCTAssertTrue(app.buttons["insights.metric"].label.contains("Пульс в покое"))
        XCTAssertFalse(chart.exists)
        let history = app.buttons["insights.history"]
        reveal(history); history.tap()
        let records = app.buttons["insights.records"]
        reveal(records); records.tap()
        capture("dynamics-exact-records")
    }

    func testDynamicsReversedAssociationAndCalculationDetails() {
        launch(fixtures: true, dark: true, reversal: true)
        app.tabBars.buttons["Динамика"].tap()
        let connections = app.buttons["insights.connections"]
        reveal(connections); connections.tap()
        app.buttons["connections.exposure"].tap()
        app.buttons["Еда менее чем за 3 часа до сна"].tap()
        app.buttons["connections.outcome"].tap()
        app.buttons["Ночная ВСР"].tap()
        XCTAssertTrue(app.staticTexts["Результат не повторился"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "−4 мс")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Перевыборка календарными неделями, 800 повторов."].exists)
        capture("dynamics-reversed-association")
        app.buttons["comparison.associationInfo"].tap()
        XCTAssertTrue(app.staticTexts["Источник"].waitForExistence(timeout: 5))
        capture("dynamics-method-details")
    }

    func testDynamicsCompactLightAndEmptyStates() throws {
        launch(compact: true)
        app.tabBars.buttons["Динамика"].tap()
        XCTAssertTrue(app.staticTexts["Нужно больше данных"].waitForExistence(timeout: 5))
        capture("dynamics-320-empty-light")
        try app.performAccessibilityAudit(for: [.elementDetection, .sufficientElementDescription])
    }

    func testDynamicsLargeTextAndWeeklyOverview() throws {
        launch(fixtures: true, large: true)
        app.tabBars.buttons["Динамика"].tap()
        capture("dynamics-accessibility3-light")
        try app.performAccessibilityAudit(for: [.elementDetection, .sufficientElementDescription])
        let week = app.buttons["insights.week"]
        reveal(week, attempts: 14); week.tap()
        XCTAssertTrue(app.navigationBars["Итоги недели"].waitForExistence(timeout: 5))
        capture("dynamics-week-accessibility3")
    }

    func testBentoAt320PointsAndResourceEntry() throws {
        launch(fixtures: true, dark: true, compact: true)
        capture("bento-320-dark")
        app.buttons["today.checkIn"].tap()
        app.buttons["event.save"].tap()
        XCTAssertTrue(app.buttons["today.checkIn"].waitForExistence(timeout: 5))
        capture("bento-320-resource")
        try audit()
    }

    func testHealthFirstTabsAndWorkoutNavigation() {
        launch()
        let labels = app.tabBars.buttons.allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(labels, ["Сегодня", "Здоровье", "Динамика", "Тренировки"])
        XCTAssertTrue(app.staticTexts["Ресурс на день"].exists)
        XCTAssertFalse(app.buttons["Начать тренировку"].exists)
        capture("today-health-first")
        app.tabBars.buttons["Тренировки"].tap()
        XCTAssertTrue(app.buttons["Начать тренировку"].waitForExistence(timeout: 5))
        let programs = app.buttons["training.programs"]
        reveal(programs); programs.tap()
        XCTAssertTrue(app.staticTexts["Тренировочные дни"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["training.history"].tap()
        XCTAssertTrue(app.staticTexts["Завершённые тренировки"].waitForExistence(timeout: 5))
        capture("training-history-area")
    }

    func testIndependentAppAndWidgetPalettes() {
        launch(fixtures: true, dark: true)
        capture("bento-dark-lime")
        app.buttons["today.settings"].tap()
        app.buttons["appearance.appColor"].tap()
        let red = app.buttons["color.red"]
        reveal(red); red.tap()
        XCTAssertTrue(red.isSelected)
        capture("palette-red")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["appearance.widgetColor"].tap()
        let mono = app.buttons["color.monochrome"]
        reveal(mono); mono.tap()
        XCTAssertTrue(mono.isSelected)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["appearance.appColor"].tap()
        reveal(red); XCTAssertTrue(red.isSelected)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons["Готово"].tap()
        for _ in 0..<6 { app.swipeDown() }
        capture("bento-dark-red")
    }

    func testCustomExercisePersistsAndCanBeReusedInAWorkout() {
        launch()
        app.tabBars.buttons["Тренировки"].tap()
        app.buttons["training.programs"].tap()
        app.buttons["Каталог упражнений"].tap()
        app.buttons["exercise.create"].tap()
        let name = app.textFields["exercise.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Моя тяга у стены")
        app.navigationBars.buttons["Готово"].tap()
        let saved = app.buttons["exercise.saved.Моя тяга у стены"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        capture("personal-exercise-library")
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["Тренировки"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Тренировки"].tap()
        let free = app.buttons["Свободная тренировка"]
        reveal(free); free.tap()
        let addExercise = app.buttons["Добавить упражнение"]
        XCTAssertTrue(addExercise.waitForExistence(timeout: 5)); addExercise.tap()
        app.buttons["Выбрать из каталога"].tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 5)); saved.tap()
        app.buttons["Выбрать упражнение"].tap()
        XCTAssertEqual(app.textFields["exercise.name"].value as? String, "Моя тяга у стены")
        app.navigationBars.buttons["Готово"].tap()
        XCTAssertTrue(app.staticTexts["Моя тяга у стены"].waitForExistence(timeout: 5))
        capture("personal-exercise-in-workout")
    }

    func testNewHealthWidgetsInSystemGallery() {
        app = XCUIApplication()
        app.launchArguments = ["--ritm-ui-testing", "--ritm-ui-session", UUID().uuidString, "--ritm-widget-fixtures"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Сегодня"].waitForExistence(timeout: 20))
        XCUIDevice.shared.press(.home)
        let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        home.activate()
        XCUIDevice.shared.press(.home)
        home.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.72)).press(forDuration: 1.3)
        let editHome = home.buttons["Edit Home Screen"]
        if editHome.waitForExistence(timeout: 3) { editHome.tap() }
        let edit = home.buttons["Edit"]
        if edit.waitForExistence(timeout: 5) { edit.tap() }
        let add = home.buttons.matching(NSPredicate(format: "label == 'Add Widget' OR label == 'Добавить виджет' OR label == 'Add Widgets'")).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5), home.debugDescription)
        add.tap()
        let search = home.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), home.debugDescription)
        search.tap(); search.typeText("Ритм")
        let catalogue = home.collectionViews["add-sheet-collection-view"]
        let appName = NSPredicate(format: "label BEGINSWITH 'Ритм' OR label BEGINSWITH 'Ritm'")
        var ritm = catalogue.descendants(matching: .any).matching(appName).firstMatch
        if !ritm.waitForExistence(timeout: 10) {
            search.buttons["Clear text"].tap(); search.typeText("Ritm")
            ritm = catalogue.descendants(matching: .any).matching(appName).firstMatch
        }
        XCTAssertTrue(ritm.waitForExistence(timeout: 5), home.debugDescription)
        ritm.tap()
        var found = Set<String>()
        let expected = ["Вода", "Добавки", "Кофеин", "Лента дня", "Ресурс на день", "Дневной свет", "Клетчатка", "Белок", "Вода · неделя", "Эксперимент", "Сон · личная цель", "Последний приём пищи"]
        for _ in 0..<85 {
            for title in expected where !found.contains(title) {
                if home.staticTexts[title].firstMatch.exists && home.staticTexts[title].firstMatch.isHittable {
                    found.insert(title)
                    let shot = XCTAttachment(screenshot: home.screenshot()); shot.name = "widget-\(title)"; shot.lifetime = .keepAlways; self.add(shot)
                }
            }
            if found.count == expected.count { break }
            home.swipeLeft()
        }
        XCTAssertEqual(found, Set(expected), home.debugDescription)
    }
}
