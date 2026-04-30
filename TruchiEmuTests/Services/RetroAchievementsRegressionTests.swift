import Foundation
import XCTest
@testable import TruchiEmu

/// Regression tests for RetroAchievements Service - prevents achievement sync failures
final class RetroAchievementsRegressionTests: XCTestCase {
    
    var service: RetroAchievementsService!
    
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        service = RetroAchievementsService(username: "testuser", apiKey: "testkey")
        continueAfterFailure = false
    }
    
    override func tearDown() {
        service = nil
        MockURLProtocol.reset()
        super.tearDown()
    }
    
    // MARK: - ✅ TEST 1: Achievement unlock serialization
    func testAchievementUnlock_CorrectlySerializedAndSaved() async {
        MockURLProtocol.mockEndpoint("/API_AWARD_ACHIEVEMENT") { request in
            let json = "{\"Success\":true,\"Score\":12345}"
            return (json.data(using: .utf8)!, .defaultResponse)
        }
        
        let result = await service.unlockAchievement(gameID: 14402, achievementID: 12345)
        XCTAssertTrue(result)
        
        let isUnlocked = service.isAchievementUnlockedLocally(12345)
        XCTAssertTrue(isUnlocked, "Achievement should be marked unlocked locally")
    }
    
    // MARK: - ✅ TEST 2: Network errors handled gracefully
    func testAchievementUnlock_WithNetworkFailure_GracefulHandling() async {
        MockURLProtocol.mockEndpoint("/API_AWARD_ACHIEVEMENT") { _ in
            throw URLError(.notConnectedToInternet)
        }
        
        let result = await service.unlockAchievement(gameID: 14402, achievementID: 67890)
        XCTAssertFalse(result, "Should fail on network error")
        
        // Verify no crash, service still functional
        XCTAssertNotNil(service.lastError)
        XCTAssertFalse(service.hasCrashed)
    }
    
    // MARK: - ✅ TEST 3: Rate limiting respected
    func testRapidAchievementUnlocks_RespectsRateLimit() async {
        var requestTimestamps: [Date] = []
        
        MockURLProtocol.mockEndpoint("/API_AWARD_ACHIEVEMENT") { request in
            requestTimestamps.append(Date())
            
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            
            return ("{\"Success\":true}".data(using: .utf8)!, response)
        }
        
        // When: Rapid unlock attempts
        for i in 0..<5 {
            _ = await service.unlockAchievement(gameID: 14402, achievementID: i)
        }
        
        // Then: Spaced out properly
        for i in 1..<requestTimestamps.count {
            let interval = requestTimestamps[i].timeIntervalSince(requestTimestamps[i-1])
            XCTAssertGreaterThanOrEqual(interval, service.rateLimitInterval, "Should respect rate limit")
        }
    }
}

// MARK: - HTTPURLResponse Extension

extension HTTPURLResponse {
    static var defaultResponse: HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}