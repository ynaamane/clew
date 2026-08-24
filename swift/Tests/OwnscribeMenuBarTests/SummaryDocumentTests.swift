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
        XCTAssertTrue(doc.keyPoints[1].contains("JWT"))
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
        XCTAssertTrue(doc.actionItems[0].hasPrefix("Sam"))
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
