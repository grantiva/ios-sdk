import Foundation

/// A `URLProtocol` subclass that intercepts every request made through a session
/// configured with it, records the request (headers + body), and replies with a
/// caller-supplied stub.
///
/// Zero external dependencies — this is the only mocking machinery in the package.
///
/// Usage:
/// ```swift
/// StubURLProtocol.reset()
/// StubURLProtocol.enqueue(.json(#"{"challenge":"abc"}"#))
/// let client = GrantivaAPIClient(teamId: "T", session: StubURLProtocol.makeSession())
/// ```
final class StubURLProtocol: URLProtocol {

    // MARK: - Stub description

    enum Stub {
        /// An HTTP response with a status code and raw body.
        case http(status: Int, body: Data, headers: [String: String])
        /// A transport-level failure (e.g. `URLError(.notConnectedToInternet)`).
        case failure(Error)
        /// A non-HTTP `URLResponse`, to exercise the `invalidResponse` path.
        case nonHTTPResponse

        static func json(_ string: String, status: Int = 200) -> Stub {
            .http(status: status, body: Data(string.utf8), headers: ["Content-Type": "application/json"])
        }

        static func status(_ status: Int) -> Stub {
            .http(status: status, body: Data(), headers: [:])
        }
    }

    /// A request as it was seen by the protocol, with the body stream already drained.
    struct RecordedRequest {
        let url: URL?
        let method: String?
        let headers: [String: String]
        let body: Data

        func header(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }

        var bodyJSON: [String: Any]? {
            try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        }
    }

    // MARK: - Shared state

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stubs: [Stub] = []
    nonisolated(unsafe) private static var recorded: [RecordedRequest] = []
    /// Used when the stub queue runs dry — every request gets this instead.
    nonisolated(unsafe) private static var fallback: Stub = .status(200)

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        stubs = []
        recorded = []
        fallback = .status(200)
    }

    static func enqueue(_ stub: Stub) {
        lock.lock()
        defer { lock.unlock() }
        stubs.append(stub)
    }

    /// Reply to every request (unbounded) with this stub.
    static func setFallback(_ stub: Stub) {
        lock.lock()
        defer { lock.unlock() }
        fallback = stub
    }

    static var requests: [RecordedRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    static var requestCount: Int { requests.count }

    private static func nextStub() -> Stub {
        lock.lock()
        defer { lock.unlock() }
        if stubs.isEmpty { return fallback }
        return stubs.removeFirst()
    }

    private static func record(_ request: RecordedRequest) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(request)
    }

    /// A session whose only protocol handler is this stub.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.record(
            RecordedRequest(
                url: request.url,
                method: request.httpMethod,
                headers: request.allHTTPHeaderFields ?? [:],
                body: Self.drainBody(of: request)
            )
        )

        switch StubURLProtocol.nextStub() {
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)

        case .nonHTTPResponse:
            let response = URLResponse(
                url: request.url!,
                mimeType: "application/json",
                expectedContentLength: 0,
                textEncodingName: nil
            )
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)

        case .http(let status, let body, let headers):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !body.isEmpty {
                client?.urlProtocol(self, didLoad: body)
            }
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    /// `URLProtocol` moves `httpBody` into `httpBodyStream`, so read whichever is set.
    private static func drainBody(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
