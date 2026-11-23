import XCTest

final class HealthOSUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() { super.setUp(); continueAfterFailure = false }

    private func launch(fixtures: Bool = false, dark: Bool = false, large: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["--ritm-ui-testing", "--ritm-ui-session", UUID().uuidString, "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        if fixtures { app.launchArguments.append("--ritm-ui-fixtures") }
        if dark { app.launchArguments.append("--ritm-ui-dark") }
        if large { app.launchArguments.append("--ritm-ui-large-text") }
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
    private func replace(_ field: XCUIElement, text: String) {
        field.tap()
        if app.buttons["event.clearAmount"].exists {
            app.buttons["event.clearAmount"].tap(); field.tap()
        } else { field.doubleTap() }
        field.typeText(text)
        let typed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", text), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [typed], timeout: 8), .completed)
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
        XCTAssertTrue(app.staticTexts["Сравнить периоды"].waitForExistence(timeout: 5))
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
        let water = app.buttons["water.add.250"]
        reveal(water); water.tap()
        capture("water-accessibility3")
        try app.performAccessibilityAudit(for: [.elementDetection, .sufficientElementDescription, .textClipped])
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
        for _ in 0..<50 {
            for title in ["Вода", "Добавки", "Кофеин", "Лента дня"] where !found.contains(title) {
                if home.staticTexts[title].firstMatch.exists && home.staticTexts[title].firstMatch.isHittable {
                    found.insert(title)
                    let shot = XCTAttachment(screenshot: home.screenshot()); shot.name = "widget-\(title)"; shot.lifetime = .keepAlways; self.add(shot)
                }
            }
            if found.count == 4 { break }
            home.swipeLeft()
        }
        XCTAssertEqual(found, Set(["Вода", "Добавки", "Кофеин", "Лента дня"]), home.debugDescription)
    }
}
