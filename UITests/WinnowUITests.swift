import XCTest

/// Runs the app against the hand-written test page `Fixtures/fixture-feed.html`.
/// It never loads instagram.com and never needs an account.
final class WinnowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ arguments: [String] = []) -> XCUIElement {
        let app = XCUIApplication()
        // `-key value` arguments override UserDefaults, so tests can set the Settings switches.
        app.launchArguments = ["-WinnowFixture", "feed"] + arguments
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.staticTexts["Post 1 by friend_one"].waitForExistence(timeout: 20))
        return web
    }

    @MainActor
    func testHidesReelsTabSuggestionsAndAppBanner() {
        let web = launch()
        XCTAssertTrue(web.links["Home"].exists)
        XCTAssertTrue(web.links["Explore"].exists)
        XCTAssertFalse(web.links["Reels"].exists)
        XCTAssertFalse(web.staticTexts["Suggested for you"].exists)
        XCTAssertFalse(web.links["See all"].exists)
        XCTAssertFalse(web.links["Open app"].exists)
        // The back arrow in the title leads to the "For you" feed, which Winnow never shows.
        XCTAssertFalse(web.images["Back"].exists)
        XCTAssertFalse(web.staticTexts["Post 4 by brand_account"].exists)
        // Post 3 has the ad labels only in its caption and a comment, not in its header.
        XCTAssertTrue(web.staticTexts["Post 3 by friend_three"].exists)
    }

    @MainActor
    func testSwitchesInSettingsChangeWhatIsHidden() {
        let web = launch([
            "-hide_sponsored", "NO", "-hide_reels", "NO", "-hide_suggestions", "NO", "-force_following", "NO",
        ])
        XCTAssertTrue(web.staticTexts["Post 4 by brand_account"].exists)
        XCTAssertTrue(web.images["Back"].exists)
        XCTAssertTrue(web.links["Reels"].exists)
        XCTAssertTrue(web.staticTexts["Suggested for you"].exists)
    }

    @MainActor
    func testFlickMovesOnePostAtATime() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "The phone layout has the bars this test measures.")
        let web = launch()
        let brand = web.staticTexts["Fixture feed"]
        XCTAssertTrue(brand.exists)
        // The top bar is 56 points high and the title is centred in it.
        let barBottom = brand.frame.midY + 28

        waitForTray()

        // From the top (stories), the first flick shows post 1 and never skips it.
        web.swipeUp(velocity: .fast)
        assertPost("Post 1 by friend_one", isBelow: barBottom, in: web)
        web.swipeUp(velocity: .fast)
        assertPost("Post 2 by friend_two", isBelow: barBottom, in: web)
        web.swipeUp(velocity: .fast)
        assertPost("Post 3 by friend_three", isBelow: barBottom, in: web)
        web.swipeDown(velocity: .fast)
        assertPost("Post 2 by friend_two", isBelow: barBottom, in: web)
    }

    @MainActor
    func testSlowDragSettlesOnNearestPost() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "The phone layout has the bars this test measures.")
        let web = launch()
        let barBottom = web.staticTexts["Fixture feed"].frame.midY + 28
        waitForTray()
        web.swipeUp(velocity: .fast)
        web.swipeUp(velocity: .fast)
        assertPost("Post 2 by friend_two", isBelow: barBottom, in: web)
        // Drag a little and stop before lifting the finger: the feed goes back to the post start.
        slowDrag(web, by: 150)
        assertPost("Post 2 by friend_two", isBelow: barBottom, in: web)
    }

    @MainActor
    func testFlickModeCanBeTurnedOff() {
        let web = launch(["-flick_mode", "NO"])
        let post = web.staticTexts["Post 2 by friend_two"]
        let before = post.frame.midY
        slowDrag(web, by: 150)
        waitForScrollToStop()
        // Without flick mode the page stays where the finger stopped.
        XCTAssertEqual(before - post.frame.midY, 150, accuracy: 30)
    }

    @MainActor
    private func slowDrag(_ web: XCUIElement, by distance: CGFloat) {
        let start = web.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        let end = start.withOffset(CGVector(dx: 0, dy: -distance))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
    }

    @MainActor
    func testStoriesTraySitsAboveTheFirstPostAndScrollsAway() {
        let web = launch()
        let story = XCUIApplication().buttons["Story by tray_one, not seen"]
        XCTAssertTrue(story.waitForExistence(timeout: 20), "The tray did not appear")
        let placed = NSPredicate(format: "isHittable == true")
        expectation(for: placed, evaluatedWith: story)
        waitForExpectations(timeout: 10)
        let firstPost = web.staticTexts["Post 1 by friend_one"]
        // The tray sits in the room above the first post, not on top of it.
        XCTAssertLessThanOrEqual(story.frame.maxY, firstPost.frame.minY)

        web.swipeUp(velocity: .fast)
        waitForScrollToStop()
        XCTAssertFalse(story.isHittable, "The tray should scroll away with the feed")
    }

    @MainActor
    func testStoriesTrayScrollsSideways() {
        _ = launch()
        let first = XCUIApplication().buttons["Story by tray_one, not seen"]
        XCTAssertTrue(first.waitForExistence(timeout: 20), "The tray did not appear")
        XCTAssertTrue(wait { first.isHittable }, "The tray is not placed")
        let last = XCUIApplication().buttons["Story by tray_twelve, seen"]
        XCTAssertFalse(last.isHittable, "The last story should start off screen")

        for _ in 0..<3 where !last.isHittable {
            first.swipeLeft(velocity: .fast)
            waitForScrollToStop()
        }
        XCTAssertTrue(last.isHittable, "The tray did not scroll sideways")
    }

    @MainActor
    func testStoriesTrayHidesWhileADialogIsOpen() {
        let web = launch()
        let story = XCUIApplication().buttons["Story by tray_one, not seen"]
        XCTAssertTrue(story.waitForExistence(timeout: 20), "The tray did not appear")
        XCTAssertTrue(wait { story.exists && story.isHittable }, "The tray is not placed")

        // The tray is a native view above the page. It must not cover Instagram's menus and sheets.
        web.buttons["More options"].tap()
        XCTAssertTrue(web.buttons["Cancel"].waitForExistence(timeout: 5))
        XCTAssertTrue(wait { !story.exists || !story.isHittable }, "The tray covers the dialog")

        web.buttons["Cancel"].tap()
        XCTAssertTrue(wait { story.exists && story.isHittable }, "The tray did not come back")
    }

    @MainActor
    private func assertPost(
        _ title: String, isBelow barBottom: CGFloat, in web: XCUIElement, line: UInt = #line
    ) {
        waitForScrollToStop()
        let post = web.staticTexts[title]
        XCTAssertTrue(post.exists, "\(title) is missing", line: line)
        // The post header is 48 points high; its title is centred in it.
        let headerTop = post.frame.midY - 24
        XCTAssertEqual(headerTop, barBottom, accuracy: 12, "\(title) is not at the top", line: line)
    }

    private func waitForScrollToStop() {
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
    }

    /// Waits until the stories tray is placed above the feed, so every test starts from the same page.
    @MainActor
    private func waitForTray() {
        let story = XCUIApplication().buttons["Story by tray_one, not seen"]
        XCTAssertTrue(story.waitForExistence(timeout: 20), "The tray did not appear")
        XCTAssertTrue(wait { story.isHittable }, "The tray is not placed")
    }

    /// Checks `condition` again and again until it is true or the time is up.
    private func wait(timeout: TimeInterval = 10, until condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return condition()
    }
}
