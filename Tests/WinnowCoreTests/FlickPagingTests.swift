import Testing

@testable import WinnowCore

@Suite struct FlickPagingTests {
    // A phone screen: 800 high, a 50 bar on top and a 50 bar at the bottom → 700 visible.
    let viewport = 800.0
    // Stories from 50 to 150, then posts of 600, one tall post of 1500, then two more.
    let layout = FeedLayout(
        route: "home",
        posts: [
            .init(top: 150, height: 600),
            .init(top: 750, height: 600),
            .init(top: 1350, height: 1500),
            .init(top: 2850, height: 600),
            .init(top: 3450, height: 600),
        ],
        topInset: 50,
        bottomInset: 50)

    private func target(at scrollY: Double, velocity: Double, proposed: Double? = nil) -> Double? {
        FlickPaging.target(
            layout: layout, scrollY: scrollY, proposedY: proposed ?? scrollY + velocity * 1000,
            viewportHeight: viewport, velocity: velocity)
    }

    @Test func flickFromStoriesGoesToFirstPost() {
        #expect(target(at: 0, velocity: 2) == 100)
    }

    @Test func flickCountsFromWhereTheDragStarted() {
        // At the top, a 300 point drag passes the start of post 1 (100) before the finger lifts.
        // The flick still stops at post 1 and does not skip it.
        let fromTop = FlickPaging.target(
            layout: layout, scrollY: 300, proposedY: 1300, viewportHeight: viewport, velocity: 2, dragStartY: 0)
        #expect(fromTop == 100)
        // At post 1, a long drag past the start of post 2 still stops at post 2.
        let long = FlickPaging.target(
            layout: layout, scrollY: 800, proposedY: 1800, viewportHeight: viewport, velocity: 2, dragStartY: 100)
        #expect(long == 700)
        // Back from post 2 with a long drag stops at post 1, not at the top.
        let back = FlickPaging.target(
            layout: layout, scrollY: 200, proposedY: -800, viewportHeight: viewport, velocity: -2, dragStartY: 700)
        #expect(back == 100)
        // A slow release settles from where the finger lifted.
        let slow = FlickPaging.target(
            layout: layout, scrollY: 650, proposedY: 660, viewportHeight: viewport, velocity: 0.1, dragStartY: 100)
        #expect(slow == 700)
    }

    @Test func flickMovesExactlyOnePost() {
        // Post 1 starts at 150, so its start position is 150 - 50 = 100.
        #expect(target(at: 100, velocity: 3) == 700)
        #expect(target(at: 130, velocity: 0.5) == 700)
        #expect(target(at: 700, velocity: 9) == 1300)
    }

    @Test func flickBackMovesOnePostOrToCurrentStart() {
        #expect(target(at: 700, velocity: -2) == 100)
        // Inside post 2: first go back to its start.
        #expect(target(at: 900, velocity: -2) == 700)
        // At the first post: back to the stories at the top.
        #expect(target(at: 100, velocity: -2) == 0)
        // Above the first post: normal scrolling.
        #expect(target(at: 20, velocity: -2) == nil)
    }

    @Test func tallPostScrollsUntilItsEnd() {
        // Tall post starts at 1350 (start position 1300) and ends at 2850.
        // Its end is on screen when scrollY + 750 >= 2850, so at 2100.
        #expect(target(at: 1300, velocity: 1, proposed: 1700) == 1700)
        #expect(target(at: 1300, velocity: 4, proposed: 5000) == 2100)
        // End of the tall post is on screen: the next flick goes to the next post.
        #expect(target(at: 2100, velocity: 1) == 2800)
        // Going back inside a tall post scrolls freely but stops at its start.
        #expect(target(at: 2000, velocity: -1, proposed: 1600) == 1600)
        #expect(target(at: 2000, velocity: -4, proposed: 0) == 1300)
    }

    @Test func flickInsideALongPostNeverMovesAgainstItsDirection() {
        // A long post (1000 high, 665 visible) at the top. The drag starts at 0 and moves 400 points,
        // past the point where the end of the post shows (335). The flick must not jump back to 335.
        let long = FeedLayout(
            route: "home", posts: [.init(top: 0, height: 1000), .init(top: 1000, height: 600)], topInset: 0,
            bottomInset: 0)
        let forward = FlickPaging.target(
            layout: long, scrollY: 400, proposedY: 1400, viewportHeight: 665, velocity: 2, dragStartY: 0)
        #expect(forward == 1000)
        // Tall post in the main layout (start 1300, end shown at 2100): a drag from its start that
        // stays before the end still stops at the end.
        let reading = FlickPaging.target(
            layout: layout, scrollY: 1700, proposedY: 3000, viewportHeight: viewport, velocity: 2, dragStartY: 1300)
        #expect(reading == 2100)
        // A forward flick that would stop behind the finger stays where the finger lifted.
        let short = FlickPaging.target(
            layout: layout, scrollY: 1700, proposedY: 1600, viewportHeight: viewport, velocity: 0.3, dragStartY: 1300)
        #expect(short == 1700)
        // Back from inside the tall post, with a drag that already passed its start: the previous post.
        let back = FlickPaging.target(
            layout: layout, scrollY: 1250, proposedY: 0, viewportHeight: viewport, velocity: -2, dragStartY: 2000)
        #expect(back == 700)
        // Back inside the tall post: never further forward than where the finger lifted.
        let backShort = FlickPaging.target(
            layout: layout, scrollY: 1500, proposedY: 1600, viewportHeight: viewport, velocity: -0.3, dragStartY: 2000)
        #expect(backShort == 1500)
    }

    @Test func lastPostScrollsFreelySoMorePostsLoad() {
        #expect(target(at: 3400, velocity: 2) == nil)
    }

    @Test func slowReleaseSettlesOnNearestPost() {
        #expect(target(at: 300, velocity: 0) == 100)
        #expect(target(at: 500, velocity: 0.1) == 700)
        // Reading inside a tall post: no snapping.
        #expect(target(at: 1700, velocity: 0) == nil)
        // In the stories area: no snapping.
        #expect(target(at: 40, velocity: 0) == nil)
    }

    @Test func postsALittleTallerThanTheScreenStillMoveOnePerFlick() {
        // Measured on an iPhone 15 Pro: 793 high, top bar 44, bottom bar 84 → 665 free.
        let phone = FeedLayout(
            route: "home",
            posts: [
                .init(top: 100, height: 679),
                .init(top: 779, height: 760),
                .init(top: 1539, height: 694),
            ],
            topInset: 44,
            bottomInset: 84)
        func target(_ scrollY: Double, _ velocity: Double, proposed: Double? = nil) -> Double? {
            FlickPaging.target(
                layout: phone, scrollY: scrollY, proposedY: proposed ?? scrollY + velocity * 1000,
                viewportHeight: 793, velocity: velocity)
        }
        // One flick, one post, even though each post is taller than 665.
        #expect(target(56, 3.5) == 735)
        #expect(target(735, 3.5) == 1495)
        #expect(target(735, -3.5) == 56)
        // A slow drag inside a post stays there, to read the rest of the caption.
        #expect(target(60, 0) == nil)
        // A slow drag a bit past the end of a post shows the whole end of that post.
        #expect(target(100, 0) == 70)
        // A slow drag far past the end of a post settles on the next one.
        #expect(target(700, 0) == 735)
    }

    @Test func noPostsMeansNormalScrolling() {
        let empty = FeedLayout(route: "home", posts: [], topInset: 0, bottomInset: 0)
        #expect(FlickPaging.target(layout: empty, scrollY: 0, proposedY: 500, viewportHeight: 800, velocity: 3) == nil)
    }

    @Test func hiddenPostsAreIgnored() {
        var withHidden = layout
        withHidden.posts.insert(.init(top: 750, height: 0), at: 1)
        #expect(
            FlickPaging.target(layout: withHidden, scrollY: 100, proposedY: 3000, viewportHeight: viewport, velocity: 3)
                == 700)
    }
}
