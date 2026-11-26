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
