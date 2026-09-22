import XCTest
@testable import V_Paste

final class JevRecommendationPolicyTests: XCTestCase {
    private let policy = JevRecommendationPolicy()

    private func makeResponse(
        choice: String = "c0",
        confidence: Double = 0.85,
        probabilities: [String: Double]? = ["c0": 0.85, "none": 0.15],
        usefulMatch: Double = 0.80
    ) -> JevDecisionResponse {
        JevDecisionResponse(
            model: "jev-latest",
            answers: JevDecisionAnswers(
                candidate: JevChoiceAnswer(
                    type: "choice",
                    choice: choice,
                    confidence: confidence,
                    probabilities: probabilities
                ),
                usefulMatch: JevNoulAnswer(type: "noul", noul: usefulMatch)
            ),
            usage: nil
        )
    }

    func testPolicyRecommendsWhenAllThresholdsMet() {
        let itemId = UUID()
        let response = makeResponse(
            choice: "c0",
            confidence: 0.85,
            probabilities: ["c0": 0.85, "none": 0.15],
            usefulMatch: 0.80
        )
        let map = ["c0": itemId]

        let decision = policy.evaluate(response: response, keyToItemIDMap: map)
        if case .recommend(let recID, let key, let conf) = decision {
            XCTAssertEqual(recID, itemId)
            XCTAssertEqual(key, "c0")
            XCTAssertEqual(conf, 0.85)
        } else {
            XCTFail("应评估为采纳推荐，实际为: \(decision)")
        }
    }

    func testPolicyAbstainsWhenChosenNone() {
        let response = makeResponse(choice: "none")
        let decision = policy.evaluate(response: response, keyToItemIDMap: ["c0": UUID()])
        XCTAssertEqual(decision, .abstain(reason: .chosenNone))
    }

    func testPolicyAbstainsWhenUsefulScoreBelowThreshold() {
        let response = makeResponse(usefulMatch: 0.35) // 低于 0.45
        let decision = policy.evaluate(response: response, keyToItemIDMap: ["c0": UUID()])
        XCTAssertEqual(decision, .abstain(reason: .lowUsefulScore))
    }

    func testPolicyAbstainsWhenConfidenceBelowThreshold() {
        let response = makeResponse(
            confidence: 0.40,
            probabilities: ["c0": 0.40, "none": 0.60]
        ) // 低于 0.50
        let decision = policy.evaluate(response: response, keyToItemIDMap: ["c0": UUID()])
        XCTAssertEqual(decision, .abstain(reason: .lowConfidence))
    }

    func testPolicyAbstainsWhenMarginBelowThreshold() {
        // 第一名 0.70，第二名 0.65，差距 0.05 < 0.15，判定模糊
        let response = makeResponse(
            choice: "c0",
            confidence: 0.70,
            probabilities: ["c0": 0.70, "c1": 0.65]
        )
        let map = ["c0": UUID(), "c1": UUID()]
        let decision = policy.evaluate(response: response, keyToItemIDMap: map)
        XCTAssertEqual(decision, .abstain(reason: .ambiguousMargin))
    }

    func testPolicyAbstainsWhenKeyMissingFromLocalMap() {
        let response = makeResponse(choice: "c99")
        let decision = policy.evaluate(response: response, keyToItemIDMap: ["c0": UUID()])
        XCTAssertEqual(decision, .abstain(reason: .missingCandidateKey))
    }
}
