import XCTest
@testable import Horizon

final class PKCETests: XCTestCase {
    /// RFC 7636 Appendix B test vector.
    func testChallengeMatchesRFCVector() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mJ92K9mGfwPj9fJoyj3-qHfD7zx6Hk")
        XCTAssertEqual(pkce.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(pkce.method, "S256")
    }

    func testRandomVerifierIsURLSafe() {
        let v = PKCE.randomURLSafeString(byteCount: 32)
        XCTAssertGreaterThanOrEqual(v.count, 43)
        XCTAssertNil(v.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")))
    }

    func testFormEncoding() {
        let body = String(data: AuthManager.formEncode(["redirect_uri": "horizonchurch://oauth/callback", "code": "a b"]), encoding: .utf8)
        XCTAssertEqual(body, "code=a%20b&redirect_uri=horizonchurch%3A%2F%2Foauth%2Fcallback")
    }
}

final class DecodingTests: XCTestCase {
    func testDecodesServingOverview() throws {
        let json = """
        {"schedules":[{"id":"1","serviceTypeName":"Main Services","teamName":"Greeters","positionName":"Front Door",
          "dates":"November 9, 2026","shortDates":"Nov 9","sortDate":"2026-11-09T17:30:00Z","timesDescription":"9:30a",
          "status":"U","declineReason":null,"canAcceptPartial":false,"planVisible":true,"respondsTo":"Jane"}],
         "blockouts":[{"id":"5","reason":"Trip","startsAt":"2026-12-01T08:00:00Z","endsAt":"2026-12-03T07:59:00Z","repeatFrequency":"no_repeat"}],
         "positions":[{"id":"9","positionName":"Front Door","schedulePreference":"Every other week (A)","preferredWeeks":[]}],
         "preferences":{"maxPlansPerMonth":2,"maxPlansPerDay":null}}
        """
        let o = try APIClient.decoder.decode(ServingOverview.self, from: Data(json.utf8))
        XCTAssertTrue(o.schedules[0].isPending)
        XCTAssertEqual(o.schedules[0].title, "Greeters · Front Door")
        XCTAssertEqual(o.preferences.maxPlansPerMonth, 2)
        XCTAssertEqual(o.blockouts.count, 1)
    }

    func testDecodesNextStepActions() throws {
        let json = """
        [{"id":"a","title":"Baptism","subtitle":"","systemImage":"drop.fill","action":{"kind":"signup","signupId":"3986196","url":"https://horizoncommunitychurch.churchcenter.com/registrations/events/3986196/reservations/new"}},
         {"id":"b","title":"Groups","subtitle":"","systemImage":"person.3","action":{"kind":"groups"}},
         {"id":"c","title":"Serve","subtitle":"","systemImage":"calendar","action":{"kind":"serve"}}]
        """
        let steps = try APIClient.decoder.decode([NextStep].self, from: Data(json.utf8))
        guard case .signup(let id, _) = steps[0].action else { return XCTFail() }
        XCTAssertEqual(id, "3986196")
        XCTAssertEqual(steps[1].action, .groups(typeID: nil))
        XCTAssertEqual(steps[2].action, .serve)
    }

    func testDecodesFractionalAndDayOnlyDates() throws {
        struct Box: Decodable { let a: Date; let b: Date }
        let box = try APIClient.decoder.decode(Box.self, from: Data(#"{"a":"2026-11-02T17:30:00.000Z","b":"2026-11-02"}"#.utf8))
        XCTAssertEqual(box.a.timeIntervalSince1970, 1793640600, accuracy: 1)
        XCTAssertNotNil(box.b)
    }
}

final class ProfileDiffTests: XCTestCase {
    private func profile() -> Profile {
        Profile(id: "1", firstName: "Sam", lastName: "Lee", nickname: nil, name: "Sam Lee", birthdate: "1990-05-01",
                anniversary: nil, gender: nil, avatarUrl: nil, membership: nil, campus: nil,
                emails: [.init(id: "e1", address: "sam@example.com", location: "Home", primary: true)],
                phoneNumbers: [.init(id: "p1", number: "503-555-0100", location: "Mobile", primary: true)],
                addresses: [], household: nil)
    }

    func testNoChangesProducesEmptyUpdate() {
        let p = profile()
        let u = ProfileUpdate.diff(original: p, draft: p, birthdate: "1990-05-01")
        XCTAssertNil(u.person)
        XCTAssertNil(u.emails)
        XCTAssertNil(u.phoneNumbers)
        XCTAssertNil(u.addresses)
    }

    func testEditsAddsAndDeletes() throws {
        let p = profile()
        var d = p
        d.firstName = "Samuel"
        d.emails[0].address = "samuel@example.com"
        d.emails.append(.init(address: "work@example.com", location: "Work", primary: false))
        d.emails.append(.init(address: "  ", location: "Other", primary: false)) // blank row ignored
        d.phoneNumbers = []
        let u = ProfileUpdate.diff(original: p, draft: d, birthdate: "1990-05-01")
        XCTAssertEqual(u.person?.first_name, "Samuel")
        XCTAssertEqual(u.emails?.count, 2)
        XCTAssertEqual(u.phoneNumbers?.count, 1)
        XCTAssertEqual(u.phoneNumbers?.first?.delete, true)

        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(u)) as! [String: Any]
        let phones = json["phoneNumbers"] as! [[String: Any]]
        XCTAssertEqual(phones[0]["_delete"] as? Bool, true)
        XCTAssertEqual(phones[0]["id"] as? String, "p1")
    }
}
