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
        XCTAssertFalse(web.staticTexts["Post 4 by brand_account"].exists)
        XCTAssertTrue(web.staticTexts["Post 3 by friend_three"].exists)
    }

    @MainActor
    func testSwitchesInSettingsChangeWhatIsHidden() {
        let web = launch(["-hide_sponsored", "NO", "-hide_reels", "NO", "-hide_suggestions", "NO"])
        XCTAssertTrue(web.staticTexts["Post 4 by brand_account"].exists)
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
}
