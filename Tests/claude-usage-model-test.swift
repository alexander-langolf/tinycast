import Foundation

@main
@MainActor
struct ClaudeUsageModelTests {
    static var passes = 0
    static var failures = 0
    static let locale = Locale(identifier: "en_US")

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func decode(_ json: String) -> ClaudeUsageSnapshot? {
        try? JSONDecoder().decode(ClaudeUsageSnapshot.self, from: Data(json.utf8))
    }

    static func limit(_ kind: String, _ percent: String,
        reset: String = "2026-11-02T14:30:00.125+00:00",
        scope: String = "null") -> String
    {
        """
        {"kind":"\(kind)","percent":\(percent),"resets_at":"\(reset)","scope":\(scope),
         "group":"usage","severity":"normal","is_active":true}
        """
    }

    static func main() {
        decodesObservedResponse()
        decodesAndOrdersWindows()
        usesFallbackOnlyWhenLimitsAreAbsent()
        rejectsMalformedBodies()
        formatsValues()
        schedulesPolls()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func decodesObservedResponse() {
        let body = #"""
            {
              "five_hour": {"utilization": 4.0, "resets_at": "2026-11-02T14:30:00.184503+00:00"},
              "seven_day": {"utilization": 83.0, "resets_at": "2026-11-03T16:00:00.184520+00:00"},
              "seven_day_opus": null,
              "extra_usage": {"is_enabled": true, "used_credits": 0.0, "utilization": null},
              "limits": [
                {"kind": "session", "group": "session", "percent": 5, "severity": "normal",
                 "resets_at": "2026-11-02T14:30:00.219442+00:00", "scope": null, "is_active": false},
                {"kind": "weekly_all", "group": "weekly", "percent": 83, "severity": "warning",
                 "resets_at": "2026-11-03T16:00:00.219466+00:00", "scope": null, "is_active": true},
                {"kind": "weekly_scoped", "group": "weekly", "percent": 0, "severity": "normal",
                 "resets_at": "2026-11-03T16:00:00.219649+00:00",
                 "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}, "is_active": false}
              ]
            }
            """#
        guard let snapshot = decode(body) else {
            expect(false, "the exact observed endpoint response decodes")
            return
        }
        expect(snapshot.windows.count == 3, "the observed response yields every reported limit")
        expect(snapshot.session?.percent == 5, "limits session percent overrides fallback utilization of four")
        expect(snapshot.weekly?.percent == 83, "the observed weekly percentage is retained")
        expect(snapshot.windows[2].percent == 0, "an inactive scoped window with zero usage is retained")
        expect(snapshot.windows[2].modelName == "Fable", "null model metadata leaves the display name intact")
        expect(ClaudeUsageFormat.windowTitle(snapshot.windows[2], locale: locale) == "Fable weekly",
            "the observed model-scoped window is identified as weekly")
        expect(ClaudeUsageFormat.label(snapshot: snapshot, display: .sessionAndWeek, locale: locale)
            == "5% · 83%", "the observed response formats values from limits rather than fallback objects")
    }

    static func decodesAndOrdersWindows() {
        let scoped = limit("weekly_scoped", "19",
            scope: #"{"model":{"display_name":"Fable"}}"#)
        let body = """
            {"limits":[\(limit("future_window", "4")),\(scoped),
             \(limit("weekly_all", "18")),\(limit("session", "42"))],
             "seven_day_opus":null,"extra_usage":null,"unrelated":{"anything":true}}
            """
        guard let snapshot = decode(body) else {
            expect(false, "the endpoint-shaped fixture decodes")
            return
        }
        expect(snapshot.windows.map(\.kind) == ["session", "weekly_all", "weekly_scoped", "future_window"],
            "known windows precede unknown windows regardless of response order")
        expect(snapshot.session?.percent == 42, "session percentages are already in whole-percent units")
        expect(snapshot.weekly?.percent == 18, "the all-models window supplies the weekly value")
        expect(snapshot.windows[2].modelName == "Fable", "the model display name survives decoding")
        expect(ClaudeUsageFormat.windowTitle(snapshot.windows[2], locale: locale) == "Fable weekly",
            "the scoped window identifies the weekly limit and preserves its model display name")
        expect(ClaudeUsageFormat.windowTitle(snapshot.windows[3], locale: locale) == "future_window",
            "an unknown window keeps its raw kind")
        let equivalent = decode("""
            {"limits":[\(limit("session", "42", reset: "2026-11-02T16:30:00.125+02:00"))]}
            """)
        expect(equivalent?.session?.resetsAt == snapshot.session?.resetsAt,
            "fractional seconds and explicit offsets identify the same instant")
        let wholeSecond = decode("""
            {"limits":[\(limit("session", "42", reset: "2026-11-02T14:30:00Z"))]}
            """)
        guard let fractionalDate = snapshot.session?.resetsAt,
            let wholeDate = wholeSecond?.session?.resetsAt
        else {
            expect(false, "fractional and whole-second timestamps both decode")
            return
        }
        expect(abs(fractionalDate.timeIntervalSince(wholeDate) - 0.125) < 0.001,
            "fractional timestamp precision is retained")
    }

    static func usesFallbackOnlyWhenLimitsAreAbsent() {
        let fallback = #"{"utilization":42.5,"resets_at":"2026-11-02T14:30:00Z"}"#
        let snapshot = decode("{\"five_hour\":\(fallback),\"seven_day\":\(fallback),\"other\":null}")
        expect(snapshot?.windows.map(\.kind) == ["session", "weekly_all"], "legacy windows decode in display order")
        expect(snapshot?.session?.percent == 42.5, "fallback utilization retains fractional percentages")
        expect(decode("{\"five_hour\":\(fallback)}")?.weekly == nil, "a missing weekly window stays missing")
        expect(decode("{\"seven_day\":\(fallback)}")?.session == nil, "a missing session window stays missing")
        let preferred = decode("{\"limits\":[\(limit("session", "7"))],\"five_hour\":false}")
        expect(preferred?.session?.percent == 7, "limits take precedence even over malformed fallback objects")
        expect(decode("{\"limits\":null,\"five_hour\":\(fallback)}") == nil,
            "a present null limits array is malformed and never invokes the fallback")
        expect(decode("{\"limits\":[]}")?.windows.isEmpty == true, "an explicit empty array reports no windows")
    }

    static func rejectsMalformedBodies() {
        for json in ["{}", "null", "[]", "{", #"{"limits":{}}"#,
            #"{"five_hour":{"utilization":42}}"#,
            #"{"limits":[{"kind":"session","percent":42}]}"#] {
            expect(decode(json) == nil, "malformed response fails closed: \(json)")
        }
        for percent in ["-0.1", "100.1", "null", "true", #""42""#, "1e999"] {
            expect(decode("{\"limits\":[\(limit("session", percent))]}") == nil,
                "rejects invalid percentage \(percent)")
        }
        for percent in ["0", "100"] {
            expect(decode("{\"limits\":[\(limit("session", percent))]}") != nil,
                "accepts percentage boundary \(percent)")
        }
        for reset in ["yesterday", "2026-11-02T14:30:00.125", ""] {
            expect(decode("{\"limits\":[\(limit("session", "42", reset: reset))]}") == nil,
                "rejects invalid or offset-free reset date")
        }
        expect(decode("{\"limits\":[\(limit("", "42"))]}") == nil, "rejects an empty kind")
        expect(decode("{\"limits\":[\(limit("session", "42")),\(limit("weekly_all", "101"))]}") == nil,
            "one invalid window prevents a partial snapshot")
        expect(decode(#"{"five_hour":{"utilization":42,"resets_at":"2026-11-02T14:30:00Z"},"seven_day":false}"#) == nil,
            "one invalid fallback window also prevents a partial snapshot")
    }

    static func formatsValues() {
        let snapshot = decode("{\"limits\":[\(limit("session", "42.5")),\(limit("weekly_all", "18.49"))]}")
        expect(ClaudeUsageFormat.label(snapshot: snapshot, display: .sessionPercent, locale: locale) == "43%",
            "session label rounds ties away from zero")
        expect(ClaudeUsageFormat.label(snapshot: snapshot, display: .sessionAndWeek, locale: locale) == "43% · 18%",
            "combined label uses the session and all-models weekly values")
        expect(ClaudeUsageFormat.percent(0.5, locale: locale) == "1%", "a half-percent rounds upward")
        expect(ClaudeUsageFormat.percent(99.5, locale: locale) == "100%", "the upper rounding boundary is whole")
        let french = Locale(identifier: "fr_FR")
        expect(ClaudeUsageFormat.percent(42, locale: french) == 0.42.formatted(
            .percent.precision(.fractionLength(0)).locale(french)), "percentage spacing follows the injected locale")
        for display in ClaudeUsageMenuBarDisplay.allCases {
            expect(ClaudeUsageFormat.label(snapshot: nil, display: display, locale: locale).isEmpty,
                "every mode falls back to the icon without a snapshot")
        }
        expect(ClaudeUsageFormat.label(snapshot: snapshot, display: .usageIcon, locale: locale).isEmpty,
            "icon mode carries no numeric label")
        expect(ClaudeUsageFormat.label(snapshot: snapshot, display: .disabled, locale: locale).isEmpty,
            "disabled mode carries no numeric label")
        let sessionOnly = decode("{\"limits\":[\(limit("session", "42"))]}")
        expect(ClaudeUsageFormat.label(snapshot: sessionOnly, display: .sessionAndWeek, locale: locale) == "42%",
            "an absent weekly window is omitted instead of fabricated")
        let now = Date(timeIntervalSince1970: 1_000)
        expect(ClaudeUsageFormat.updated(now, now: now.addingTimeInterval(119), locale: locale)
            == "Updated 1 min ago", "last-updated minutes use the injected clock and truncate")
        expect(ClaudeUsageFormat.updated(now, now: now.addingTimeInterval(-1), locale: locale)
            == "Updated 0 min ago", "a clock moving backwards never gives a negative age")
        let utc = TimeZone(secondsFromGMT: 0)!
        let east = TimeZone(secondsFromGMT: 7_200)!
        expect(ClaudeUsageFormat.reset(now, locale: locale, timeZone: utc)
            != ClaudeUsageFormat.reset(now, locale: locale, timeZone: east), "reset time uses the injected time zone")
        expect(ClaudeUsageMenuBarDisplay.allCases.map(\.rawValue)
            == ["disabled", "usageIcon", "sessionPercent", "sessionAndWeek"], "display preference values stay stable")
    }

    static func schedulesPolls() {
        let now = Date(timeIntervalSince1970: 1_000)
        let deadline = ClaudeUsagePollPolicy.nextPoll(after: now)
        expect(deadline.timeIntervalSince(now) == 300, "the poll interval is five minutes")
        for inserted in [false, true] {
            for signedIn in [false, true] {
                expect(ClaudeUsagePollPolicy.isEnabled(inserted: inserted, signedIn: signedIn)
                    == (inserted && signedIn), "insertion and sign-in must both allow polling")
                for trigger in [ClaudeUsagePollPolicy.Trigger.activation, .timer, .wake, .manual] {
                    expect(ClaudeUsagePollPolicy.shouldFetch(trigger: trigger, inserted: inserted,
                        signedIn: signedIn, now: deadline, nextPoll: deadline, rateLimitedUntil: nil)
                        == (inserted && signedIn), "all triggers respect both lifecycle gates")
                }
            }
        }
        expect(!ClaudeUsagePollPolicy.shouldFetch(trigger: .timer, inserted: true, signedIn: true,
            now: deadline.addingTimeInterval(-0.001), nextPoll: deadline, rateLimitedUntil: nil),
            "a timer never polls before its deadline")
        expect(!ClaudeUsagePollPolicy.shouldFetch(trigger: .timer, inserted: true, signedIn: true,
            now: deadline, nextPoll: nil, rateLimitedUntil: nil), "stopping a schedule leaves no timer fetch")
        for trigger in [ClaudeUsagePollPolicy.Trigger.activation, .wake, .manual] {
            expect(ClaudeUsagePollPolicy.shouldFetch(trigger: trigger, inserted: true, signedIn: true,
                now: now, nextPoll: deadline, rateLimitedUntil: nil), "activation, wake and manual bypass the timer deadline")
            expect(!ClaudeUsagePollPolicy.shouldFetch(trigger: trigger, inserted: true, signedIn: true,
                now: now, nextPoll: deadline, rateLimitedUntil: deadline), "429 blocks immediate trigger retries")
        }
        expect(ClaudeUsagePollPolicy.shouldFetch(trigger: .timer, inserted: true, signedIn: true,
            now: deadline, nextPoll: deadline, rateLimitedUntil: deadline),
            "429 allows the next scheduled poll at its boundary")
    }
}
