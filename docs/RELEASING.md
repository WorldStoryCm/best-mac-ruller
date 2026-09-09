# Releasing Ruller

Direct downloads use Sparkle 2.9.6, GitHub Releases for ZIPs, and GitHub Pages for the signed appcast. No application server is needed. Releases are built on the maintainer's Mac, so the private signing key stays in its login Keychain.

## Day-to-day development

```sh
cd /Users/x11/work/ruller
make run       # rebuild and open the local app
make test      # unit tests plus AppKit smoke checks
make share     # universal ZIP in dist/
```

Quit a running copy before rebuilding it. The app keeps guides in `~/Library/Application Support/Ruller/guides.json`; replacing the app does not replace that file. Build tools require macOS 13+, Swift command-line tools, and internet access for the pinned Sparkle dependency on the first build.

## Publish the next version

1. Write `releases/1.2.1.md` with user-facing release notes.
2. Commit your source changes and notes, then push `main`.
3. Run:

   ```sh
   make release VERSION=1.2.1
   ```

Use a new `major.minor.patch` version greater than the current one. The script updates the app version and increments `CFBundleVersion`, runs tests, builds both architectures, signs and packages the app, generates signed metadata, commits the release, tags it, and publishes the ZIP. It pushes the feed commit to `main` only after the archive is publicly available. GitHub Pages then deploys `docs/appcast.xml`.

The release command needs a clean checkout on `main`, matching `origin/main`, GitHub write access through `gh auth login`, and the matching Sparkle key in Keychain. macOS can ask to allow `generate_keys`, `generate_appcast`, or `sign_update` to access that key. Review and allow the official Sparkle tools. Archives are immutable: never replace the ZIP of an existing release, change published build numbers, or force-push release tags.

For the first release only, the committed source already has version 1.2.0 and build 4; `make release` publishes that version without another bump.

## Signing key

- Keychain account: **WorldStoryCm.Ruller**.
- Public key embedded in `Resources/Info.plist`: `JaJHnhs0L7dvYXEso5tSO3casgBsGTCi4ilMz8ksZTY=`.
- Only the public key belongs in Git. Never commit or upload the private key, signing certificates, or notarization credentials.
- Back up the private key securely before replacing or erasing this Mac. Use Sparkle's documented key export/import process and encrypted storage outside this repository. Losing it can require a manual reinstall for users. Do not generate a replacement key to work around a missing-key error.

The app requires signed feeds and verifies archive signatures before extraction. Signed-feed failures never fall back to unsigned metadata. Do not edit `docs/appcast.xml` by hand after signing; regenerate it with `scripts/prepare-update.sh`. Five recent release entries are retained; full ZIP updates are used without deltas.

## GitHub hosting

- Repository: `WorldStoryCm/best-mac-ruller` (public).
- Pages source: branch `main`, folder `/docs`, deploy from branch.
- Feed: `https://worldstorycm.github.io/best-mac-ruller/appcast.xml`.
- Download: `https://github.com/WorldStoryCm/best-mac-ruller/releases/latest`.

After publishing, check the release asset and wait for the Pages deployment to finish. Choose **Check for Updates…** on an older installed copy. Apps at 1.1.0 or earlier need one manual installation of 1.2.0 or newer. Automatic checks can be disabled from the ruler menu; installation always requires the user's choice.

If publication stops after creating a tag, inspect the tag, release, and asset before continuing. Resume uploading the **same tested ZIP**, publish the draft, then push the existing release commit on `main`. If the release is already public, do not recreate it. If no remote tag was created, resolve the error and inspect the local version changes before retrying. The script refuses existing tags to prevent accidental replacement.

## Update integration tests

```sh
make build
make test-updates
```

This launches a separate test harness and Sparkle's real installer against disposable app bundles. It checks a signed installation and that tampering with either the ZIP or feed is rejected while the old app remains intact. It uses a random test key, never the production Keychain key. A temporary HTTP server listens only on loopback. Run in a logged-in graphical macOS session. Re-run these tests when changing Sparkle, packaging, signing, or update policy; ordinary geometry changes only need `make test`.

## Apple signing and notarization later

Current releases are ad-hoc signed and **not notarized by Apple**. Sparkle's Ed25519 signatures authenticate updates, but do not replace Apple's Developer ID verification for first installation.

Once a Developer ID Application certificate and a `notarytool` Keychain profile are available:

```sh
RULLER_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
RULLER_NOTARY_PROFILE='ruller-notary' \
make release VERSION=1.3.0
```

The script signs embedded helpers and the app in order, enables the hardened runtime, submits the ZIP for notarization, staples the ticket, then repackages and signs the final archive for Sparkle. It stops if notarization fails. Certificate/profile setup is a separate step; the current repository contains no Apple credentials.

For a future Mac App Store edition, create a separate distribution target without Sparkle and its update menus, configure App Sandbox and Apple signing, and test overlay/hotkey behavior under that target. Store updates would be managed by Apple. The current direct-download build is not an App Store submission.

References: [Sparkle setup and key custody](https://sparkle-project.org/documentation/), [publishing updates](https://sparkle-project.org/documentation/publishing/), [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
