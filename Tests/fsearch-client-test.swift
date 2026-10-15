// Pins the fsearch stdio contract: id pairing, bad lines, child death and relaunch, rejection.
import Foundation

@main
struct FSearchClientTest {
    nonisolated(unsafe) static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static let directory = FileManager.default.temporaryDirectory
        .appending(path: "fsearch-client-\(UUID().uuidString)")

    /// A stand-in child: `behavior` picks what it answers, one JSON line per request.
    static func fakeChild(_ name: String, body: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name)
        let script = """
            #!/usr/bin/env python3
            import sys, json
            for line in sys.stdin:
                req = json.loads(line)
            \(body.split(separator: "\n").map { "    " + $0 }.joined(separator: "\n"))
            """
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    static func main() async {
        defer { try? FileManager.default.removeItem(at: directory) }
        protocolLines()
        await MainActor.run {}
        await clientBehaviour()
        print(failures == 0 ? "fsearch client tests passed" : "\(failures) fsearch client tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func protocolLines() {
        let line = FSearchProtocol.requestLine(id: 3, query: "a \"b\"", limit: 5)
        let object = line.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        expect(
            object?["id"] as? Int == 3 && object?["q"] as? String == "a \"b\""
                && object?["limit"] as? Int == 5,
            "a request carries id, query and limit")
        expect(line?.last == 0x0A, "a request is one line")
        let reply =
            #"{"hits":[{"kind":"dir","path":"/a","mtime":1,"size":0,"score":3},{"kind":"file","path":"/b"}],"id":4,"ok":true,"took_us":9}"#
        expect(
            FSearchProtocol.decode(Data(reply.utf8))
                == .hits(
                    id: 4,
                    [FSearchHit(path: "/a", isDirectory: true), FSearchHit(path: "/b", isDirectory: false)]),
            "hits decode with their kind")
        expect(
            FSearchProtocol.decode(Data(#"{"ok":false,"id":2,"error":"unknown type x"}"#.utf8))
                == .failure(id: 2, message: "unknown type x"), "a rejection keeps its id and message")
        expect(FSearchProtocol.decode(Data("garbage".utf8)) == nil, "a malformed line decodes to nothing")
    }

    @MainActor
    static func clientBehaviour() async {
        do {
            let echo = try fakeChild(
                "echo",
                body:
                    "print(json.dumps({'ok': True, 'id': req['id'], 'hits': [{'kind': 'file', 'path': '/x/' + req['q']}]}), flush=True)"
            )
            let client = FSearchClient(executable: { echo })
            let first = try? await client.fetchHits(for: "one", limit: 5)
            let second = try? await client.fetchHits(for: "two", limit: 5)
            expect(
                first?.first?.path == "/x/one" && second?.first?.path == "/x/two",
                "replies pair with their requests")
            async let a = client.fetchHits(for: "left", limit: 5)
            async let b = client.fetchHits(for: "right", limit: 5)
            let both = try? await (a, b)
            expect(
                both?.0.first?.path == "/x/left" && both?.1.first?.path == "/x/right",
                "concurrent requests pair by id")
            client.stop()

            let rejecting = try fakeChild(
                "reject",
                body: "print(json.dumps({'ok': False, 'id': req['id'], 'error': 'nope'}), flush=True)")
            let rejected = FSearchClient(executable: { rejecting })
            do {
                _ = try await rejected.fetchHits(for: "x", limit: 1)
                expect(false, "ok:false throws")
            } catch FSearchClient.Failure.rejected(let message) {
                expect(message == "nope", "the rejection message surfaces")
            } catch { expect(false, "ok:false throws rejected, got \(error)") }
            rejected.stop()

            let noisy = try fakeChild(
                "noisy",
                body: """
                    if req['id'] == 1:
                        print('not json', flush=True)
                    else:
                        print(json.dumps({'ok': True, 'id': req['id'], 'hits': []}), flush=True)
                    """)
            let bad = FSearchClient(executable: { noisy })
            do {
                _ = try await bad.fetchHits(for: "x", limit: 1)
                expect(false, "an undecodable line fails the request")
            } catch FSearchClient.Failure.rejected {
            } catch { expect(false, "undecodable fails as rejected, got \(error)") }
            let next = try? await bad.fetchHits(for: "y", limit: 1)
            expect(next != nil, "the next request still works after a bad line")
            bad.stop()

            let dying = try fakeChild("dying", body: "sys.exit(0)")
            let dead = FSearchClient(executable: { dying })
            do {
                _ = try await dead.fetchHits(for: "x", limit: 1)
                expect(false, "a dying child fails the request")
            } catch FSearchClient.Failure.exited {
            } catch { expect(false, "child death throws exited, got \(error)") }

            let missing = FSearchClient(executable: { nil })
            do {
                _ = try await missing.fetchHits(for: "x", limit: 1)
                expect(false, "a missing executable throws")
            } catch FSearchClient.Failure.unavailable {
            } catch { expect(false, "missing throws unavailable, got \(error)") }

            let flaky = try fakeChild(
                "flaky",
                body:
                    "print(json.dumps({'ok': True, 'id': req['id'], 'hits': [{'kind': 'file', 'path': '/ok'}]}), flush=True)\nsys.exit(0)"
            )
            let relaunching = FSearchClient(executable: { flaky })
            _ = try? await relaunching.fetchHits(for: "a", limit: 1)
            try? await Task.sleep(for: .milliseconds(200))
            let again = try? await relaunching.fetchHits(for: "b", limit: 1)
            expect(again?.first?.path == "/ok", "a child that exited is relaunched for the next request")
            relaunching.stop()
        } catch {
            expect(false, "harness setup failed: \(error)")
        }
    }
}
