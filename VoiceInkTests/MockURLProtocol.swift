import Foundation

/// Intercepts URLSession requests for tests. Captures the request (with body) and
/// returns a canned response.
final class MockURLProtocol: URLProtocol {
    /// (statusCode, responseBody). Set before each test.
    static var handler: ((URLRequest, Data?) -> (Int, Data))?
    /// Captured request body (httpBodyStream is read into Data here).
    static var lastBody: Data?
    static var lastURL: URL?
    static var lastHeaders: [String: String]?

    static func reset() {
        handler = nil
        lastBody = nil
        lastURL = nil
        lastHeaders = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = MockURLProtocol.readBody(from: request)
        MockURLProtocol.lastBody = body
        MockURLProtocol.lastURL = request.url
        MockURLProtocol.lastHeaders = request.allHTTPHeaderFields

        let (status, data) = MockURLProtocol.handler?(request, body) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    /// A URLSession wired to use this protocol.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}
