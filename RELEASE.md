# Signed installer releases

## Version management

`VERSION` contains the marketing version and `BUILD_NUMBER` contains the positive
integer build number. Local, XcodeGen, CI, and release builds use these same values.
The copies in `project.yml` and `Packaging/*.plist` are generated settings; CI checks
both numbers for drift. Syncing requires Python 3 from the Xcode developer tools.

Before a release:

1. Update `VERSION` (for example, `1.0.3`) and increment `BUILD_NUMBER` above any
   previously distributed build, including local test builds.
2. Run `./scripts/sync-version.sh` and, if using Xcode, regenerate with `xcodegen`.
3. Run `./scripts/sync-version.sh --check`, `./scripts/test.sh`, and `./build.sh`.
4. Commit the two source files and generated settings. After the commit is merged,
   create and push the matching tag, for example `git tag v1.0.3` followed by
   `git push origin v1.0.3`.

The release workflow rejects a tag that differs from `VERSION` before accessing
signing credentials. Workflow reruns reuse the committed build number; increment it
and create a new version/tag when distributing a different build. Explicit `VERSION`
and `BUILD_NUMBER` environment overrides remain available for local experiments;
they do not update the committed settings or affect the tagged release workflow.

## Release pipeline

The direct-distribution pipeline is `./release.sh`. It builds universal arm64/x86_64
binaries for macOS 12+, signs the two extensions before the host app with hardened
runtime and secure timestamps, notarizes and staples the app, creates a signed
installer, then notarizes, staples, and assesses that installer. The installer
offers two installation destinations: **Install for me only** places the app at
`~/Applications/Peekdown.app` without administrator authorization; **Install for
all users of this computer** places it at `/Applications/Peekdown.app` with
administrator authorization. If Installer skips Destination Select, use
**Change Install Location…** on the Installation Type screen. Upgrades replace
the app in the selected domain rather than relocating to another copy.
It has no privileged registration scripts.
It also creates a ZIP of the signed, stapled app for installing in
`~/Applications` without administrator access.

## One-time certificate setup

Use an active paid Apple Developer Program membership. For locally managed
Developer ID certificates, Apple requires the Account Holder role. The existing
Apple Development and Apple Distribution certificates are different certificate
types and cannot replace these.

1. On the Mac that will sign releases, open **Keychain Access → Certificate
   Assistant → Request a Certificate From a Certificate Authority**. Enter your
   email and name, leave CA Email Address empty, and select **Saved to disk**.
   This creates the private key locally and saves a `.certSigningRequest` file.
2. Sign in to [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/list)
   using the Account Holder account. Select your intended developer team.
3. Click **+**, select **Developer ID Application**, and follow the CSR upload
   instructions. Download the `.cer` and double-click it on the same Mac.
4. Repeat for **Developer ID Installer**. Both certificates must use the same team.
5. In Keychain Access → My Certificates, each certificate must expand to show
   its private key. A downloaded certificate alone is insufficient. If signing on
   another Mac, export each identity with its private key as a password-protected
   `.p12` and import it there. Keep certificates, private keys, and passwords out
   of the repository.
6. Confirm the exact identity names:

   ```bash
   security find-identity -v -p codesigning
   security find-identity -v -p basic
   ```

   Expected names include `Developer ID Application: YOUR_NAME (YOUR_TEAM_ID)`
   and `Developer ID Installer: YOUR_NAME (YOUR_TEAM_ID)`. Use the actual names
   printed on your Mac. If a certificate is not valid, check its private key,
   expiration, and Apple intermediate certificate chain; do not override trust.

[Apple's Developer ID certificate instructions](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/).

## One-time notarization credentials

Create an app-specific password at [Apple Account](https://account.apple.com/).
Save it in Keychain using the following command, which prompts for the password:

```bash
xcrun notarytool store-credentials Peekdown-notary \
  --apple-id 'YOUR_APPLE_ACCOUNT_EMAIL' \
  --team-id 'YOUR_TEAM_ID'
```

Do not use your regular Apple Account password. The release script reads the
saved profile; it never needs a password in source files or environment variables.
`notarytool` also supports storing App Store Connect API key credentials if your
organization uses those instead.

### Local release build

Run from the repository root on a Mac with Xcode or compatible Command Line Tools
containing `swiftc`, `lipo`, `notarytool`, and `stapler`, plus macOS `pkgbuild` and
`productbuild`. XcodeGen is only needed for
the separate Xcode project workflow, not this pipeline.

Version and build numbers are read from `VERSION` and `BUILD_NUMBER`:

```bash
export APPLICATION_IDENTITY='Developer ID Application: YOUR_NAME (YOUR_TEAM_ID)'
export INSTALLER_IDENTITY='Developer ID Installer: YOUR_NAME (YOUR_TEAM_ID)'
export NOTARY_PROFILE='Peekdown-notary'

./release.sh --check
./release.sh
```

To override the VERSION file, export `VERSION` before running:
```bash
export VERSION='1.0.3'
export BUILD_NUMBER='11'
./release.sh
```

Increase the version/build for subsequent releases. `--check` checks tools,
local signing identities, and notarization credentials using Apple's submission
history service. A real release uploads the signed app and installer to Apple.
Notarization may take time. The script fails on rejected submissions, invalid
signatures, missing timestamps/runtime, mismatched teams, or failed assessments.

Successful output is in `build/releases/<version>-<build>/`:

- `Peekdown-<version>.pkg` — distribute this signed, stapled installer.
- `Peekdown-<version>.zip` — the signed, stapled app for manual user installation.
- `SHA256SUMS` — checksums of the final installer and ZIP.
- `Peekdown.app` — signed and stapled app contained in the installer.
- Submission results and Apple's notarization logs for both submissions.

An existing release directory is not overwritten. Failed release files remain
for diagnosis. A failure after submission may still leave Apple processing the
upload. Use the ID from `app-notary.plist` or `installer-notary.plist`:

```bash
xcrun notarytool info SUBMISSION_ID --keychain-profile Peekdown-notary
xcrun notarytool log SUBMISSION_ID --keychain-profile Peekdown-notary build/notary-log.json
```

After diagnosing a failure, choose a new build number or move the failed release
directory before rerunning. Never distribute an artifact from a failed run.

[Apple's notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

## Local verification without certificates

```bash
./scripts/test.sh
./build.sh
./scripts/package.sh build/local/Peekdown.app build/Peekdown-local.pkg
./scripts/test-package.sh build/Peekdown-local.pkg
```

These commands exercise the parser, compile both architectures, verify ad-hoc
signatures, and create an **unsigned test installer**. Ad-hoc builds are not
release artifacts and do not validate Finder preview activation. If installer
signing is desired, `scripts/package.sh` reads `INSTALLER_IDENTITY` when set.

## Release acceptance

After a successful signed release, test both destinations on a clean Mac or VM
with normal Gatekeeper settings. Use a standard (non-admin) account for **Install
for me only** and confirm there is no administrator prompt, the app is owned by
that user, and no files are written outside their home folder. Confirm **Install
for all users** requests administrator authorization and installs to
`/Applications`. Launch the app once from the selected Applications folder. Enable its
Quick Look extensions in System Settings if macOS requests it. Check Finder Space
previews and thumbnails for each supported extension, dark/light mode, front
matter ending at EOF, and unrelated `.txt` files. Test an upgrade over the previous
version in each domain and verify offline opening after tickets have been stapled.
When switching domains, remove the previous app copy to prevent duplicate
extension registrations; a personal install does not remove a shared installation.
Test Intel
and Apple Silicon machines and the oldest supported macOS version before claiming
that compatibility. Compilation and signature verification alone do not establish
runtime compatibility or successful extension discovery.

## Automated releases with GitHub Actions

Push a tag matching `v*` (e.g., `v1.0.3`) to trigger an automated release. The
workflow validates that the git tag matches the `VERSION` file, imports signing
certificates into a temporary keychain, runs `./release.sh`, publishes a GitHub
Release with the signed `.pkg`, `.zip`, and `SHA256SUMS`, and updates the Homebrew
tap's cask formula. No signing credentials are committed. The workflow uses the committed `BUILD_NUMBER` file for reproducible numbering.

### Required GitHub Actions secrets

Create these secrets at **Settings → Secrets and variables → Actions → New repository secret**:

#### `APPLICATION_CERT_BASE64`
Base64-encoded `.p12` file containing your **Developer ID Application** certificate
and its private key. Export from Keychain Access:
1. In Keychain Access → My Certificates, expand **Developer ID Application: YOUR_NAME (TEAMID)**
2. Select both the certificate and its private key (shown below it)
3. Right-click → Export 2 items, save as `.p12`, and set a strong password
4. Encode: `base64 -i DeveloperIDApplication.p12 | pbcopy`
5. Paste the base64 output into the secret value

#### `INSTALLER_CERT_BASE64`
Base64-encoded `.p12` file containing your **Developer ID Installer** certificate
and its private key. Follow the same export and encoding steps as above for the
**Developer ID Installer** identity.

#### `CERT_PASSWORD`
The password protecting both `.p12` files. Use the same password for both exports
to simplify the workflow.

#### `NOTARY_APPLE_ID`
Your Apple ID email (the Account Holder or admin with notarization access).

#### `NOTARY_APP_PASSWORD`
An app-specific password for notarization. Generate one at
[Apple Account](https://account.apple.com/) → Sign-In and Security → App-Specific Passwords.
**Do not** use your regular Apple Account password.

#### `NOTARY_TEAM_ID`
Your 10-character Apple Developer team ID (the same `TEAMID` shown in your
certificate names, e.g., `A1B2C3D4E5`).

#### `HOMEBREW_TAP_TOKEN`
A GitHub personal access token (classic) with `repo` scope that can push to
`h0ck3ystyx/homebrew-tap`. Create one at **GitHub Settings → Developer settings →
Personal access tokens → Tokens (classic) → Generate new token**. Select only
the `repo` scope. The workflow uses this token to update the cask formula after
each release.

### Cutting a release

Before pushing a release tag, ensure the `VERSION` file matches the desired version:

```bash
echo '1.0.3' > VERSION
echo '11' > BUILD_NUMBER # choose a number above all previously distributed builds
./scripts/sync-version.sh
git add VERSION BUILD_NUMBER project.yml Packaging/*.plist
git commit -m "Bump version to 1.0.3"
git push origin main

git tag v1.0.3
git push origin v1.0.3
```

The workflow validates that the tag matches the `VERSION` file and fails early with
a clear message if they don't match. It derives `VERSION=1.0.3` and `BUILD_NUMBER`
from the tag and committed build-number file, runs the tests and release script, creates the GitHub
Release, and updates the Homebrew tap. Monitor progress at **Actions → Release**.
The release appears at `https://github.com/h0ck3ystyx/peekdown/releases/tag/v1.0.3`.

If notarization or another step fails, delete the tag locally and remotely, fix
the issue, and re-tag:

```bash
git tag -d v1.0.3
git push origin :refs/tags/v1.0.3
```

Do not re-push the same tag after a failed release without cleaning up the
partial GitHub Release and understanding the failure.

## Local releases

The direct-distribution pipeline is `./release.sh`. Use it for local testing or
if GitHub Actions is unavailable. It builds universal arm64/x86_64
binaries for macOS 12+, signs the two extensions before the host app with hardened
runtime and secure timestamps, notarizes and staples the app, creates a signed
installer, then notarizes, staples, and assesses that installer. The installer
offers two installation destinations: **Install for me only** places the app at
`~/Applications/Peekdown.app` without administrator authorization; **Install for
all users of this computer** places it at `/Applications/Peekdown.app` with
administrator authorization. If Installer skips Destination Select, use
**Change Install Location…** on the Installation Type screen. Upgrades replace
the app in the selected domain rather than relocating to another copy.
It has no privileged registration scripts.
It also creates a ZIP of the signed, stapled app for installing in
`~/Applications` without administrator access.
