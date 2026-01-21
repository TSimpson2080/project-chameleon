import Testing
@testable import Chameleon

struct NumberingServiceTests {
    @Test func firstChangeOrderIs0001() {
        let job = JobModel(clientName: "Client A")
        let next = NumberingService.nextChangeOrderNumber(for: job, using: [])
        #expect(next == "CO-0001")
    }

    @Test func incrementsSequentially() {
        let job = JobModel(clientName: "Client A")
        let existing = [
            ChangeOrderModel(job: job, number: 1, title: "CO 1", details: "d"),
            ChangeOrderModel(job: job, number: 2, title: "CO 2", details: "d"),
        ]

        let next = NumberingService.nextChangeOrderNumber(for: job, using: existing)
        #expect(next == "CO-0003")
    }

    @Test func ignoresMalformedNumbers() {
        let job = JobModel(clientName: "Client A")
        let existing = [
            ChangeOrderModel(job: job, number: 0, title: "Bad", details: "d"),
            ChangeOrderModel(job: job, number: -2, title: "Bad", details: "d"),
            ChangeOrderModel(job: job, number: 5, title: "OK", details: "d"),
        ]

        let next = NumberingService.nextChangeOrderNumber(for: job, using: existing)
        #expect(next == "CO-0006")
    }

    @Test func numberingIsIsolatedPerJob() {
        let jobA = JobModel(clientName: "Client A")
        let jobB = JobModel(clientName: "Client B")

        let existing = [
            ChangeOrderModel(job: jobA, number: 3, title: "A3", details: "d"),
            ChangeOrderModel(job: jobB, number: 10, title: "B10", details: "d"),
        ]

        let nextA = NumberingService.nextChangeOrderNumber(for: jobA, using: existing)
        let nextB = NumberingService.nextChangeOrderNumber(for: jobB, using: existing)

        #expect(nextA == "CO-0004")
        #expect(nextB == "CO-0011")
    }

    @Test func customerPrefixUsesLastWord() {
        let job = JobModel(clientName: "Bob Smith")
        #expect(NumberingService.customerPrefix(for: job) == "Smith")
        #expect(NumberingService.formatChangeOrderDisplay(job: job, number: 1) == "Smith-0001")
    }

    @Test func customerPrefixTrimsAndIgnoresPunctuation() {
        let job = JobModel(clientName: "  Bob   A.  Smith ")
        #expect(NumberingService.customerPrefix(for: job) == "Smith")
    }

    @Test func customerPrefixFallsBackWhenEmpty() {
        let job = JobModel(clientName: "   ")
        #expect(NumberingService.customerPrefix(for: job) == "CO")
    }
}
