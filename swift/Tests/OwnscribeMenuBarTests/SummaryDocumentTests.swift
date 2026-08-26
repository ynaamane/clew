import XCTest
@testable import OwnscribeMenuBar

final class SummaryDocumentTests: XCTestCase {
    private let realShape = """
    # Meeting Summary

    ## Summary
    The meeting focused on technical aspects of a project.

    ## Key Points
    - Discussion about sharing an HTML file on Zoom.
    - Architecture section mentioned Lambda and security involving JWT.

    ## Action Items
    None mentioned.
    """

    func testParsesTheThreeSectionsOfARealSummary() throws {
        let doc = try SummaryDocument(markdown: realShape)

        XCTAssertEqual(doc.prose, "The meeting focused on technical aspects of a project.")
        XCTAssertEqual(doc.keyPoints.count, 2)
        // XCTAssertEqual above is non-fatal: execution continues even when it fails, so a
        // direct doc.keyPoints[1] traps the whole xctest process (Fatal error: Index out of
        // range) on any regression that shrinks the array, instead of reporting one clean
        // failure -- XCTUnwrap throws, which a `throws` test function turns into a normal
        // failure. Reproduced live: mutating bullets(in:) to always filter every bullet
        // crashed the process here and silently dropped every other test's result in the run.
        let secondKeyPoint = try XCTUnwrap(doc.keyPoints.dropFirst().first)
        XCTAssertTrue(secondKeyPoint.contains("JWT"))
    }

    func testNoneMentionedIsPreservedRatherThanTurnedIntoAnEmptyList() throws {
        let doc = try SummaryDocument(markdown: realShape)

        XCTAssertTrue(doc.actionItems.isEmpty)
        XCTAssertEqual(
            doc.actionItemsPlaceholder, "None mentioned.",
            "\"None mentioned.\" is the anti-hallucination guard: it means the model was asked and found nothing, which is different from a section that was never produced. Showing a blank list loses that distinction")
    }

    func testRealActionItemsAreListed() throws {
        let doc = try SummaryDocument(markdown: """
        ## Summary
        Short.

        ## Action Items
        - Sam checks the JWT bug tomorrow.
        - Yanis sends the PPTX.
        """)

        XCTAssertEqual(doc.actionItems.count, 2)
        let firstItem = try XCTUnwrap(doc.actionItems.first)
        XCTAssertTrue(firstItem.hasPrefix("Sam"))
    }

    func testMissingSectionsDoNotThrow() throws {
        let doc = try SummaryDocument(markdown: "# Meeting Summary\n")

        XCTAssertEqual(doc.prose, "")
        XCTAssertTrue(doc.keyPoints.isEmpty)
        XCTAssertTrue(doc.actionItems.isEmpty)
    }

    func testBulletedNoneMentionedIsFilteredFromActionItems() throws {
        let doc = try SummaryDocument(markdown: """
        ## Summary
        Short.

        ## Action Items
        - None mentioned.
        """)

        XCTAssertTrue(doc.actionItems.isEmpty, "A bulleted \"None mentioned.\" must not count as an action item")
        XCTAssertEqual(doc.actionItemsPlaceholder, "None mentioned.")
    }

    func testOtherNoneFamilyPlaceholdersAreAlsoFilteredWhenBulleted() throws {
        for placeholder in ["None.", "N/A", "Aucune.", "Aucun."] {
            let doc = try SummaryDocument(markdown: """
            ## Action Items
            - \(placeholder)
            """)

            XCTAssertTrue(doc.actionItems.isEmpty, "\"\(placeholder)\" must not count as an action item")
        }
    }

    func testALegitimateActionItemStartingWithNoneIsKept() throws {
        let doc = try SummaryDocument(markdown: """
        ## Action Items
        - None of the proposals were accepted — revisit next week.
        """)

        XCTAssertEqual(doc.actionItems.count, 1, "A real action item must not be dropped just because it starts with \"None\"")
        XCTAssertEqual(doc.actionItems.first, "None of the proposals were accepted — revisit next week.")
    }
}
