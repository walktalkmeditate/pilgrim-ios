import Foundation

/// Answers `URLSession` requests from a table, so a spec can drive a service
/// that streams bytes without a network. Registered through
/// `URLSessionConfiguration.protocolClasses`, which `URLSession.bytes(from:)`
/// goes through like every other transfer.
final class StubURLProtocol: URLProtocol {

    struct Response {
        let status: Int
        let body: Data
        let headers: [String: String]
    }

    private static let lock = NSLock()
    private static var responses: [String: Response] = [:]
    private static var seen: [URL] = []

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        responses = [:]
        seen = []
    }

    static func stub(url: URL, status: Int = 200, body: Data, headers: [String: String]? = nil) {
        lock.lock(); defer { lock.unlock() }
        responses[url.absoluteString] = Response(
            status: status, body: body,
            headers: headers ?? ["Content-Length": String(body.count), "Content-Type": "application/json"])
    }

    static var requestedURLs: [URL] {
        lock.lock(); defer { lock.unlock() }
        return seen
    }

    /// An ephemeral session that only this protocol answers.
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.lock.lock()
        Self.seen.append(url)
        let stub = Self.responses[url.absoluteString]
        Self.lock.unlock()
        guard let stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: stub.status,
                                       httpVersion: "HTTP/1.1", headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
