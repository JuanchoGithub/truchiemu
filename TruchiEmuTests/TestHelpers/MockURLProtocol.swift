import Foundation
@testable import TruchieEmu

/// Mock URLProtocol for network testing - intercepts network requests and provides mock responses
/// Used for RetroAchievements, BoxArt, Core downloads, and other external API calls
class MockURLProtocol: URLProtocol {
    
    // MARK: - Mock Storage
    
    private static var mockEndpoints: [String: MockEndpoint] = [:]
    private static var requestHistory: [URLRequest] = []
    private static var responseDelays: [String: TimeInterval] = [:]
    
    // MARK: - Configuration
    
    /// Configures a mock response for a specific URL pattern
    static func mockEndpoint(_ pattern: String, response: @escaping (URLRequest) -> (Data, HTTPURLResponse)) {
        mockEndpoints[pattern] = MockEndpoint(responseBuilder: response)
    }
    
    /// Sets a delay for a specific endpoint (simulates slow networks)
    static func setDelay(for pattern: String, delay: TimeInterval) {
        responseDelays[pattern] = delay
    }
    
    /// Clears all mock endpoints
    static func reset() {
        mockEndpoints.removeAll()
        requestHistory.removeAll()
        responseDelays.removeAll()
    }
    
    /// Returns all intercepted requests
    static var requests: [URLRequest] {
        return requestHistory
    }
    
    /// Finds the first request matching a pattern
    static func request(for pattern: String) -> URLRequest? {
        return requestHistory.first { req in
            req.url?.absoluteString.contains(pattern) == true
        }
    }
    
    // MARK: - URLProtocol Overrides
    
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        // Record the request
        MockURLProtocol.requestHistory.append(request)
        
        // Find matching endpoint
        guard let url = request.url?.absoluteString,
              let (data, response) = getMockResponse(for: url) else {
            // No mock found - return error
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        
        // Start loading
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        
        // Apply delay if configured
        if let delay = MockURLProtocol.responseDelays.first(where: { url.contains($0.key) })?.value {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.client?.urlProtocol(self!, didLoad: data)
                self?.client?.urlProtocolDidFinishLoading(self!)
            }
        } else {
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    
    override func stopLoading() {
        // Nothing to stop
    }
    
    // MARK: - Private Helpers
    
    private func getMockResponse(for url: String) -> (Data, HTTPURLResponse)? {
        for (pattern, endpoint) in MockURLProtocol.mockEndpoints {
            if url.contains(pattern) {
                let request = self.request
                guard let requestURL = request.url else { return nil }
                
                let response = HTTPURLResponse(
                    url: requestURL,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                
                let (data, _) = endpoint.responseBuilder(request)
                return (data, response)
            }
        }
        return nil
    }
}

// MARK: - Mock Endpoint

class MockEndpoint {
    let responseBuilder: (URLRequest) -> (Data, HTTPURLResponse)
    
    init(responseBuilder: @escaping (URLRequest) -> (Data, HTTPURLResponse)) {
        self.responseBuilder = responseBuilder
    }
}

// MARK: - Common Mock Response Builders

extension MockURLProtocol {
    
    /// Mock RetroAchievements API responses
    static func mockAchievements(success: Bool, points: Int = 0) {
        mockEndpoint("/API_GetGameInfoAndUserProgress") { _ in
            let json = """
            {
                "Success": \(success),
                "UserProgress": {
                    "NumAchieved": \(success ? 5 : 0),
                    "TotalPoints": \(points),
                    "GameID": 14402
                },
                "Achievements": [
                    {"ID": 123, "Title": "Test Achievement", "Description": "Test", "Points": 10}
                ]
            }
            """
            return (json.data(using: .utf8)!, HTTPURLResponse())
        }
    }
    
    /// Mock BoxArt service responses
    static func mockBoxArt(imageData: Data = Data("FAKE_IMAGE_DATA".utf8)) {
        mockEndpoint("/thumbnails.libretro.com") { _ in
            return (imageData, HTTPURLResponse())
        }
    }
    
    /// Mock core download
    static func mockCoreDownload(version: String, checksum: String) {
        mockEndpoint("core_download") { _ in
            var data = Data()
            data.append(Data("CORE_BINARY_DATA".utf8))
            data.append(Data(checksum.utf8))
            
            let response = HTTPURLResponse(
                url: URL(string: "https://libretro.com/core.zip")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Length": "\(data.count)"]
            )!
            
            return (data, response)
        }
    }
    
    /// Mock network failure
    static func mockNetworkFailure(error: URLError.Code = .notConnectedToInternet) {
        mockEndpoint("network_failure") { _ in
            throw URLError(error)
        }
    }
    
    /// Mock rate limiting
    static func mockRateLimit(retryAfter: Int = 60) {
        mockEndpoint("rate_limit") { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.example.com")!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: ["Retry-After": "\(retryAfter)"]
            )!
            return (Data("Rate limited".utf8), response)
        }
    }
}

// MARK: - Convenience Extensions

struct HTTPURLResponse {
    static var defaultResponse: HTTPURLResponse {
        return HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}