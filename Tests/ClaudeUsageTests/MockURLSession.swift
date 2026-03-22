import Foundation
@testable import ClaudeUsageCore

final class MockURLSession: HTTPSession, @unchecked Sendable {
    private let handler: @Sendable (URLRequest) -> (Data, HTTPURLResponse)

    init(handler: @escaping @Sendable (URLRequest) -> (Data, HTTPURLResponse)) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let (data, response) = handler(request)
        return (data, response)
    }
}

final class ThrowingMockSession: HTTPSession, @unchecked Sendable {
    private let error: any Error

    init(error: any Error) {
        self.error = error
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        throw error
    }
}
