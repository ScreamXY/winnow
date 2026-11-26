import Foundation

/// The feed layout that the page script reports. All values are CSS pixels in page
/// coordinates (0 is the top of the page).
struct FeedLayout: Equatable, Sendable, Decodable {
    struct Post: Equatable, Sendable, Decodable {
        var top: Double
        var height: Double
        var bottom: Double { top + height }
    }

    /// The page type, for example `home`. Flick mode only runs on `home`.
    var route: String
    var posts: [Post]
    /// Height of the fixed bar at the top of the page (0 if there is none).
    var topInset: Double
    /// Height of the fixed bar at the bottom of the page (0 if there is none).
    var bottomInset: Double
    /// The empty space above the first post where the app shows the stories tray, if any.
    var stories: StoriesSlot?

    /// Page position and width of the stories space, in CSS pixels.
    struct StoriesSlot: Equatable, Sendable, Decodable {
        var top: Double
        var left: Double
        var width: Double
    }
}

/// Flick mode: one flick moves exactly one post, like the full-screen feed that Instagram
/// tested in 2022. Posts taller than the screen can still be read with normal scrolling.
enum FlickPaging {
    /// Release speed (points per millisecond) that counts as a flick.
    static let flickVelocity = 0.25
    /// Small distance that still counts as "at the start of a post".
    static let tolerance = 2.0
    /// A post counts as long only when it is this much taller than the free space between the bars.
    /// Most Instagram posts on a phone are a little taller than that space (measured on an iPhone 15
    /// Pro: about 665 points free, posts 680–760); they still move one per flick.
    static let longPostFactor = 1.3

    /// Where a scroll should come to rest after the finger lifts.
    ///
    /// - Parameters:
    ///   - layout: The latest post positions.
    ///   - scrollY: The page position now (top of the screen).
    ///   - proposedY: Where the scroll would stop without flick mode.
    ///   - viewportHeight: Visible page height.
    ///   - velocity: Release speed in points per millisecond. Positive means "towards newer posts".
    /// - Returns: The page position to stop at, or nil to keep normal scrolling.
    static func target(
        layout: FeedLayout, scrollY: Double, proposedY: Double, viewportHeight: Double, velocity: Double
    ) -> Double? {
        guard
            let scroll = Scroll(
                layout: layout, scrollY: scrollY, proposedY: proposedY, viewportHeight: viewportHeight)
        else {
            return nil
        }
        if velocity > flickVelocity {
            return scroll.forward()
        }
        if velocity < -flickVelocity {
            return scroll.back()
        }
        return scroll.settle()
    }
}

/// One finger lift: the posts and where the screen is now.
private struct Scroll {
    let posts: [FeedLayout.Post]
    let layout: FeedLayout
    let scrollY: Double
    let proposedY: Double
    let viewportHeight: Double
    let visibleHeight: Double
    /// The line just below the top bar.
    let topLine: Double
    /// The line just above the bottom bar.
    let bottomLine: Double
    /// The post at the top of the screen, or nil above the first post (stories).
    let current: Int?

    init?(layout: FeedLayout, scrollY: Double, proposedY: Double, viewportHeight: Double) {
        posts = layout.posts.filter { $0.height > 1 }.sorted { $0.top < $1.top }
        visibleHeight = viewportHeight - layout.topInset - layout.bottomInset
        guard !posts.isEmpty, visibleHeight > 0 else {
            return nil
        }
        self.layout = layout
        self.scrollY = scrollY
        self.proposedY = proposedY
        self.viewportHeight = viewportHeight
        topLine = scrollY + layout.topInset
        bottomLine = scrollY + viewportHeight - layout.bottomInset
        let line = topLine
        current = posts.lastIndex { $0.top <= line + FlickPaging.tolerance }
    }

    private var tolerance: Double { FlickPaging.tolerance }

    private func start(_ index: Int) -> Double {
        max(0, posts[index].top - layout.topInset)
    }

    /// The position where the end of the post meets the bottom bar.
    private func endShown(_ post: FeedLayout.Post) -> Double {
        post.bottom - (viewportHeight - layout.bottomInset)
    }

    private func isLong(_ post: FeedLayout.Post) -> Bool {
        post.height > visibleHeight * FlickPaging.longPostFactor
    }

    private func isTallerThanScreen(_ post: FeedLayout.Post) -> Bool {
        post.height > visibleHeight + tolerance
    }

    /// A flick towards newer posts.
    func forward() -> Double? {
        guard let index = current else {
            return start(0)
        }
        let post = posts[index]
        if isLong(post), post.bottom > bottomLine + tolerance {
            // Keep reading the long post, but stop at its end.
            return min(proposedY, endShown(post))
        }
        // After the last loaded post, scroll freely so Instagram can load more.
        return index + 1 < posts.count ? start(index + 1) : nil
    }

    /// A flick back towards the top.
    func back() -> Double? {
        guard let index = current else {
            return nil
        }
        let post = posts[index]
        if topLine > post.top + tolerance {
            // Inside a post: go back to its start first.
            return isLong(post) ? max(proposedY, start(index)) : start(index)
        }
        // At the first post, go back to the very top (stories).
        return index > 0 ? start(index - 1) : 0
    }

    /// A slow release settles on the nearest post start, but stays put while the rest of a post
    /// that is taller than the screen is being read.
    func settle() -> Double? {
        guard let index = current else {
            return nil
        }
        let post = posts[index]
        var candidates = [start(index)]
        if isTallerThanScreen(post) {
            if scrollY > start(index) + tolerance, scrollY < endShown(post) - tolerance {
                return nil
            }
            candidates.append(endShown(post))
        }
        if index + 1 < posts.count {
            candidates.append(start(index + 1))
        }
        return candidates.min { abs($0 - scrollY) < abs($1 - scrollY) }
    }
}
