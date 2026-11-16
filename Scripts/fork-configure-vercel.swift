#!/usr/bin/swift
import AppKit
import Foundation
import Security

let bundleID = CommandLine.arguments.dropFirst().first ?? "com.tinycast.app.dev"
guard ["com.tinycast.app", "com.tinycast.app.dev"].contains(bundleID) else {
    fatalError("Choose the stable or Dev Tinycast bundle identifier.")
}
guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
    fatalError("Quit Tinycast before configuring its connection.")
}
let root = URL(filePath: FileManager.default.currentDirectoryPath)
guard FileManager.default.fileExists(atPath: root.appending(path: "server/policy/lyra.json").path) else {
    fatalError("Run this script from the Tinycast repository.")
}
let connectionID = "86C3B84F-B072-4E37-A4F6-2A3A4BA128E7"
let model = "anthropic/claude-haiku-5.5"
var credential: Data?
for field in [kSecAttrService, kSecAttrAccount] {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        field as String: "vercel-ai-gateway",
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { continue }
    guard status == errSecSuccess, let data = result as? Data,
          let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { fatalError("Cannot read the Vercel Keychain credential (status \(status)).") }
    credential = Data(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
    break
}
guard let credential else { fatalError("The vercel-ai-gateway Keychain credential is missing.") }
let keyQuery: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "\(bundleID).ai-api-keys",
    kSecAttrAccount as String: connectionID
]
let attributes = [kSecValueData as String: credential]
let updated = SecItemUpdate(keyQuery as CFDictionary, attributes as CFDictionary)
if updated == errSecItemNotFound {
    let added = SecItemAdd(keyQuery.merging(attributes) { _, new in new } as CFDictionary, nil)
    guard added == errSecSuccess else { fatalError("Cannot save the Tinycast credential (status \(added)).") }
} else if updated != errSecSuccess {
    fatalError("Cannot save the Tinycast credential (status \(updated)).")
}
let folder = root.appending(path: ".local/vercel-lyra")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for name in ["policy", "prompts"] {
    let destination = folder.appending(path: name)
    if !FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.copyItem(at: root.appending(path: "server/\(name)"), to: destination)
    }
}
let policyURL = folder.appending(path: "policy/lyra.json")
var policy = try JSONSerialization.jsonObject(with: Data(contentsOf: policyURL)) as! [String: Any]
let modes = policy["modes"] as! [[String: String]]
policy["routing"] = Dictionary(uniqueKeysWithValues: modes.map { ($0["name"]!, connectionID) })
try JSONSerialization.data(withJSONObject: policy, options: [.prettyPrinted, .sortedKeys]).write(to: policyURL, options: .atomic)
let defaults = UserDefaults.standard
var preferences = defaults.persistentDomain(forName: bundleID) ?? [:]
var connections = try (preferences["aiConnections"] as? Data).map {
    try JSONSerialization.jsonObject(with: $0) as! [[String: Any]]
} ?? []
connections.removeAll { $0["id"] as? String == connectionID }
connections.append([
    "id": connectionID, "name": "Vercel Haiku", "provider": "openAICompatible",
    "baseURL": "https://ai-gateway.vercel.sh/v1", "models": [model], "visionModels": [],
    "reasoningOptions": [model: ["efforts": ["none"], "defaultEffort": "none"]]
])
preferences["aiConnections"] = try JSONSerialization.data(withJSONObject: connections)
preferences["fork.policy.directory"] = folder.path
preferences["fork.lyra.enabled"] = true
var overrides = try (preferences["quickActionModelOverrides"] as? Data).map {
    try JSONSerialization.jsonObject(with: $0) as! [String: Any]
} ?? [:]
overrides["rewrite"] = ["api": ["connection": connectionID, "model": model, "effort": "none"]]
preferences["quickActionModelOverrides"] = try JSONSerialization.data(withJSONObject: overrides)
defaults.setPersistentDomain(preferences, forName: bundleID)
guard defaults.synchronize() else { fatalError("Cannot save Tinycast preferences.") }
print("Configured Lyra and Rewrite for Vercel Haiku in \(bundleID). Credentials remain in Keychain.")
