import Foundation

struct ForkPolicyFailure: Error, Sendable {
    let file: String
    let reason: ForkEvent.PolicyFailure
}
