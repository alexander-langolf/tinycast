# Signing

Tinycast uses a **stable self-signed identity** called `Tinycast Self-Signed` by default. Keeping the
same identity and build location across builds lets macOS retain permissions tied to the signed app;
ad-hoc signatures do not provide that stability. A checkout can opt into a local Apple Development
identity for Debug without changing Release or another checkout.

An Apple Developer ID certificate now exists, but nothing is signed with it yet. Why that switch is
staged rather than immediate is [below](#the-developer-id-migration).

You create this identity **once**. The same identity is used for:

- **default local dev builds** — the Xcode project uses it unless this checkout opts in locally, and
- **CI releases** — exported into two GitHub secrets the release workflow imports.

## 1. Create the `Tinycast Self-Signed` identity (once)

Run these in a terminal. They generate a self-signed code-signing certificate and import it into your
login keychain:

```sh
# Generate a self-signed code-signing cert (10-year, codeSigning use).
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout /tmp/tc-key.pem -out /tmp/tc-cert.pem \
  -subj "/CN=Tinycast Self-Signed" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"

# Bundle it as a .p12 (the non-empty password keeps `security import` happy).
openssl pkcs12 -export -inkey /tmp/tc-key.pem -in /tmp/tc-cert.pem \
  -name "Tinycast Self-Signed" -out /tmp/tc.p12 -passout pass:tinycast

# Import into the login keychain so codesign can use it without prompting.
security import /tmp/tc.p12 -k ~/Library/Keychains/login.keychain-db \
  -P tinycast -A -T /usr/bin/codesign

rm -f /tmp/tc-key.pem /tmp/tc-cert.pem /tmp/tc.p12
```

Verify it's there:

```sh
security find-identity -p codesigning | grep "Tinycast Self-Signed"
```

Now default local builds (Xcode, VS Code F5, `xcodebuild`) sign with it. Grant Accessibility for that
identity and build location once.

## Switching a Debug checkout to Apple Development

`Tinycast/DebugSigning.xcconfig` is tracked and defaults to `Tinycast Self-Signed`. It optionally includes
`DebugSigning.local.xcconfig`, which is gitignored. To select an installed Apple Development identity
for this checkout, put its **certificate SHA-1** and its actual **Team ID** in the local file:

```xcconfig
CODE_SIGN_IDENTITY = <certificate SHA-1>
DEVELOPMENT_TEAM = <team ID from certificate subject OU>
```

Find the SHA-1 with `security find-identity -v -p codesigning`; inspect the certificate subject to
find its `OU` for the Team ID. The parenthesized suffix of the identity's display name may differ
from that Team ID. The local file is picked up by ordinary Xcode and
`xcodebuild` Debug builds without command-line overrides or another XcodeGen run. The project-level
Debug config applies to every target, including `TinycastPreviews`, `ClipboardTextHelper`,
`DictationHelper` and `TinycastCLI`; Release still selects `Tinycast Self-Signed`.

Switching from self-signed to Apple Development changes the app's signing requirement. macOS may ask
again for Accessibility, Input Monitoring, Automation or other protected access, even when the bundle
identifier and build path stay fixed. Approve the new Dev app in System Settings when prompted; an
existing grant for the old signature is not proof that the new signature has it. The login Keychain
may also prompt on first access to each existing Tinycast Dev item (automation-client tokens, AI/MCP
credentials, and other saved secrets), because the requesting code identity changed. Choose the
appropriate allow option for the signed app when prompted. Existing Keychain values and app data
remain in place; this setup does not reset TCC, alter Keychain access lists, or migrate secrets.
Once the new identity is used consistently for rebuilds, those decisions can persist.

## 2. Generate the CI secrets

The release workflow needs the same identity as two repo secrets. Export it, base64-encode it, and
pick a password:

```sh
# Pick a random password for the exported bundle.
P12_PASSWORD="$(openssl rand -base64 24)"; echo "password: $P12_PASSWORD"

# Export the identity (approve the keychain dialog if asked) and base64-encode it.
security export -t identities -f pkcs12 \
  -k ~/Library/Keychains/login.keychain-db \
  -P "$P12_PASSWORD" -o /tmp/signing.p12
base64 -i /tmp/signing.p12 | tr -d '\n' > /tmp/signing.p12.base64
rm -f /tmp/signing.p12
```

Then set the two secrets on the repo (via `gh`, authed as the repo owner, or paste them in the GitHub
UI under **Settings → Secrets and variables → Actions**):

```sh
gh secret set SIGNING_P12_BASE64   --repo abue-ammar/tinycast < /tmp/signing.p12.base64
gh secret set SIGNING_P12_PASSWORD --repo abue-ammar/tinycast --body "$P12_PASSWORD"
rm -f /tmp/signing.p12.base64   # holds your private key — delete it
```

If you ever lose the secrets, just re-run this section — as long as the `Tinycast Self-Signed`
identity is still in your keychain, the exported identity is the same, so users are unaffected. If you
lose the identity entirely, recreate it (step 1) and re-do this; existing users will re-grant
Accessibility once on their next update, then it's stable again.

## Hardened runtime

**Release only**, on both targets: `ENABLE_HARDENED_RUNTIME: YES`, which notarization requires. Debug
must stay without it — hardened runtime turns on library validation, and Xcode's
`Tinycast Dev.debug.dylib` is refused at launch because a self-signed identity carries no Team ID for
the loader to match. The flag is not part of the designated requirement, so turning it on costs no
Accessibility grant. Each entitlement in `Tinycast/Tinycast.entitlements` earns its place:

| Entitlement | Without it |
| --- | --- |
| `com.apple.security.cs.allow-jit` | JavaScriptCore cannot JIT, and every extension command runs on the interpreter |
| `com.apple.security.automation.apple-events` | Every Apple event is refused with `-1743` and no prompt — Get Info, the Finder selection an extension reads, and the System Events–driven system actions all die silently |
| `com.apple.security.device.camera` | The camera prompt never appears and access resolves as denied |
| `com.apple.security.personal-information.calendars` | `requestFullAccessToEvents()` returns `false` in milliseconds with no dialog, and Tinycast never appears under System Settings › Calendars |

**A usage string is not enough under the hardened runtime.** `tccd` checks the matching entitlement
*before* it prompts, and without it logs "requires entitlement … but it is missing" and denies on the
spot — no dialog, no error, status still `.notDetermined`. A grant saved before the hardened runtime
arrived keeps working, since `tccd` does not re-check it, which is why this surfaces only on fresh
installs. Adding a protected resource therefore means adding its usage string *and* its entitlement.

`RESOURCE_ENTITLEMENTS` in `Scripts/verify-signature.sh` maps every protected resource's usage string
to its entitlement, including resources Tinycast does not use. That grants nothing — only
`Tinycast.entitlements` does, and a row whose usage string `Info.plist` doesn't declare is skipped. It
is there so a future feature that adds the usage string but forgets the entitlement fails the release
instead of shipping a prompt that can never appear.

Nothing else is needed: the only `dlopen` is Apple's own IOBluetooth, so library validation is left
on, and `node`, `ray` and shell commands are separate processes it never reaches. Bluetooth has no
hardened-runtime entitlement.

`./Scripts/verify-signature.sh <path-to-.app>` asserts all of this — the runtime flag on the app *and*
on `Contents/Helpers/ClipboardTextHelper`, an intact nested seal, no `get-task-allow`, and an
entitlement for every usage string `Info.plist` declares. Both release jobs run it before packaging:
a nested binary missing the runtime flag is the most common notarization rejection, and a usage string
missing its entitlement ships a permission that can never be granted.

## The Developer ID migration

`BundleSignature` already accepts a bundle signed by the Tinycast team under Apple's Developer ID
chain, even though releases are still signed with `Tinycast Self-Signed`. That is deliberate and
staged: the updater compares signatures before it installs, so the code that trusts the new identity
has to reach users *before* the first build carrying it. Until the switch it also accepts the running
app's own leaf, which is the only thing a copy installed earlier knows how to check.

The requirement pins the team rather than the certificate, so a Developer ID renewal strands nobody.
It deliberately omits the `notarized` keyword — that resolves a ticket through `syspolicyd` or the
network, and the updater verifies in a cache directory Gatekeeper has never assessed, so an offline
Mac would refuse a bundle the chain already proves is ours.

**The Developer ID identity stays a CI-only fact.** When the switch happens it is named on the
release workflow's `xcodebuild` line and nowhere else: Release keeps signing with
`Tinycast Self-Signed`. An optional Apple Development identity affects only local Debug builds; it
does not change release signing or the staged Developer ID migration.

**Keep `Tinycast Self-Signed` in the login keychain after the switch.** It is the only way to ship a
build that a copy predating the migration could still install.

## Quarantine (separate from signing)

macOS quarantines anything downloaded from the internet, and Gatekeeper blocks even a correctly
self-signed app with an "unverified developer" warning. The Homebrew cask runs
`xattr -dr com.apple.quarantine` in `postflight`, so **brew users never touch it**. People who
download the DMG directly clear it once by hand.
