import XCTest
@testable import OLCVPN

final class OLCUriTests: XCTestCase {
    private let key = String(repeating: "a", count: 64)

    func testFullURI() throws {
        let raw = "olcrtc://jitsi?vp8channel@room-42#\(key)$Мой сервер"
        let (p, k) = try OLCUri.parse(raw)
        XCTAssertEqual(p.carrier, .jitsi)
        XCTAssertEqual(p.transport, .vp8channel)
        XCTAssertEqual(p.roomID, "room-42")
        XCTAssertEqual(k, key)
        XCTAssertEqual(p.note, "Мой сервер")
    }

    func testTransportPayload() throws {
        let raw = "olcrtc://telemost?vp8channel<fps=30&batch=8>@r1#\(key)"
        let (p, _) = try OLCUri.parse(raw)
        XCTAssertEqual(p.carrier, .telemost)
        XCTAssertEqual(p.transportParams["fps"], "30")
        XCTAssertEqual(p.transportParams["batch"], "8")
    }

    func testMissingScheme() {
        XCTAssertThrowsError(try OLCUri.parse("http://x")) { e in
            XCTAssertEqual(e as? OLCUri.ParseError, .missingScheme)
        }
    }

    func testInvalidKey() {
        let raw = "olcrtc://jitsi?vp8channel@r1#short"
        XCTAssertThrowsError(try OLCUri.parse(raw)) { e in
            XCTAssertEqual(e as? OLCUri.ParseError, .invalidKey)
        }
    }

    func testUnknownCarrier() {
        let raw = "olcrtc://zoom?vp8channel@r1#\(key)"
        XCTAssertThrowsError(try OLCUri.parse(raw)) { e in
            XCTAssertEqual(e as? OLCUri.ParseError, .unknownCarrier("zoom"))
        }
    }
}
