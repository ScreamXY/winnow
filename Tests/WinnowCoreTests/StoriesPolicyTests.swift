import Foundation
import Testing

@testable import WinnowCore

@Suite struct StoriesPolicyTests {
    private func cookie(_ name: String, domain: String = ".instagram.com") -> HTTPCookie {
        HTTPCookie(properties: [.name: name, .value: "x", .domain: domain, .path: "/"])!
    }

    private let feed = URL(string: "https://www.instagram.com/?variant=following")!

    @Test func loadsOnTheFeedAfterLogin() {
        let cookies = [cookie("csrftoken"), cookie("sessionid")]
        #expect(StoriesPolicy.mayLoad(mainPage: feed, cookies: cookies))
        #expect(StoriesPolicy.mayLoad(mainPage: URL(string: "https://www.instagram.com/")!, cookies: cookies))
        #expect(StoriesPolicy.mayLoad(mainPage: URL(string: "https://instagram.com")!, cookies: cookies))
    }

    @Test func neverLoadsWhileLoggedOut() {
        #expect(!StoriesPolicy.mayLoad(mainPage: feed, cookies: []))
        #expect(!StoriesPolicy.mayLoad(mainPage: feed, cookies: [cookie("csrftoken"), cookie("mid")]))
        #expect(!StoriesPolicy.mayLoad(mainPage: feed, cookies: [cookie("sessionid", domain: ".example.com")]))
    }

    @Test func neverLoadsAwayFromTheFeed() {
        let cookies = [cookie("sessionid")]
        let pages = [
            "https://www.instagram.com/accounts/login/?next=%2F",
            "https://www.instagram.com/accounts/onetap/?next=%2F",
            "https://www.instagram.com/challenge/action/",
            "https://www.instagram.com/accounts/login/two_factor?next=%2F",
            "https://www.instagram.com/stories/some.friend/123/",
            "https://www.facebook.com/",
            "http://www.instagram.com/",
        ]
        for page in pages {
            #expect(!StoriesPolicy.mayLoad(mainPage: URL(string: page)!, cookies: cookies), "\(page)")
        }
        #expect(!StoriesPolicy.mayLoad(mainPage: nil, cookies: cookies))
    }

    @Test func keepsTheTrayOnOtherPagesWhileLoggedIn() {
        let cookies = [cookie("sessionid")]
        let pages = [
            "https://www.instagram.com/?variant=following",
            "https://www.instagram.com/some.friend/",
            "https://www.instagram.com/p/abc/",
            "https://www.instagram.com/direct/inbox/",
        ]
        for page in pages {
            #expect(StoriesPolicy.mayKeep(mainPage: URL(string: page)!, cookies: cookies), "\(page)")
        }
    }

    @Test func unloadsTheTrayAfterLogoutAndOnAccountPages() {
        #expect(!StoriesPolicy.mayKeep(mainPage: feed, cookies: []))
        #expect(!StoriesPolicy.mayKeep(mainPage: feed, cookies: [cookie("csrftoken")]))
        let cookies = [cookie("sessionid")]
        let pages = [
            "https://www.instagram.com/accounts/login/?next=%2F",
            "https://www.instagram.com/accounts/logout/",
            "https://www.instagram.com/accounts/onetap/?next=%2F",
            "https://www.instagram.com/challenge/action/",
            "https://www.instagram.com/auth_platform/codeentry/",
            "https://www.facebook.com/",
            "http://www.instagram.com/",
        ]
        for page in pages {
            #expect(!StoriesPolicy.mayKeep(mainPage: URL(string: page)!, cookies: cookies), "\(page)")
        }
        #expect(!StoriesPolicy.mayKeep(mainPage: nil, cookies: cookies))
    }

    @Test func recognizesStoryPages() {
        #expect(StoriesPolicy.isStory(URL(string: "https://www.instagram.com/stories/some.friend/123/")!))
        #expect(StoriesPolicy.isStory(URL(string: "https://instagram.com/stories/some.friend/")!))
        #expect(!StoriesPolicy.isStory(URL(string: "https://www.instagram.com/some.friend/")!))
        #expect(!StoriesPolicy.isStory(URL(string: "https://www.instagram.com/")!))
        #expect(!StoriesPolicy.isStory(URL(string: "https://www.example.com/stories/x/")!))
        #expect(!StoriesPolicy.isStory(nil))
    }
}
