# MaKeep

A macOS menu bar app for quickly adding and editing Google Keep notes and lists.

## Build & run

```sh
make run       # build, install to /Applications/MaKeep.app, and launch
make test      # unit tests
make stop      # quit the running app
```

Requires macOS 14+ and Xcode / Swift 6.2+.

Run `scripts/create-signing-cert.sh` once to create a local "MaKeep Local Signing"
certificate. Builds signed with it keep the same identity, so Keychain "Always Allow"
survives rebuilds. Without it, builds are signed ad-hoc and macOS asks again after every
build. To remove it: `security delete-identity -c "MaKeep Local Signing"`.

Debug builds accept `--debug-window` (the popover UI with sample notes in a regular window)
and `--debug-login` (opens the Google sign-in window): `.build/debug/makeep --debug-window`.

## Releases

MaKeep is distributed outside the App Store as a Developer ID–signed, notarized app.
(The Mac App Store would require sandboxing and would very likely reject the unofficial
Keep API and the Keep-like name and branding.)

```sh
make release-check            # next version + prerequisite check, changes nothing
make release                  # bump version, universal build, sign, notarize, staple → dist/MaKeep-x.y.z.zip
make release ARGS=--publish   # …and commit the bump, tag, push, and create a GitHub release
```

The bump in `Resources/Info.plist` (marketing version patch + build number) is rolled back
if the release is canceled or fails before notarization succeeds. One-time setup (also
documented at the top of `scripts/release.sh`):

1. **Developer ID certificate**: Xcode → Settings → Accounts → your team → Manage
   Certificates → + → *Developer ID Application* (account holder only).
2. **Notarization credentials**:
   `xcrun notarytool store-credentials makeep-notary --apple-id <apple id> --team-id 47K8399UUS`,
   using an app-specific password from account.apple.com.

## Backends

MaKeep talks to Keep through one of two backends behind the `KeepBackend` protocol:

| | Personal (unofficial) | Workspace (official) |
|---|---|---|
| Accounts | Any Google account | Google Workspace only |
| API | Private Android sync API (port of [gkeepapi](https://github.com/kiwiz/gkeepapi)) | [Google Keep API v1](https://developers.google.com/workspace/keep/api) |
| Edit in place | Yes | No: the API has no update call, so edits create a new note and delete the old one |
| Pin | Yes | No |
| Delete | Moves to Keep trash | Permanent |
| Stability | Can break whenever Google changes things | Supported |

### Personal account sign-in

Enter your email and click **Sign in with Google…**. MaKeep opens Google's
`EmbeddedSetup` page in a private web view, captures the one-time `oauth_token`
cookie, and exchanges it for a master token, which is stored in the Keychain.
If Google blocks the embedded sign-in, get a master token another way (for example,
with gpsoauth) and paste it under **Advanced**.

### Workspace sign-in

1. In a Google Cloud project that belongs to your Workspace org, enable the **Google Keep API**.
2. Set up the OAuth consent screen with user type **Internal** and add the scope
   `https://www.googleapis.com/auth/keep`.
3. Create an OAuth client ID of type **Desktop app**.
4. Paste the client ID and secret into MaKeep and click **Sign in with Google…**. Your
   browser finishes the sign-in and redirects back to a temporary local listener.

## Layout

```
Sources/makeep/
  App/            MenuBarExtra entry point
  Model/          Note, NoteStore (UI state + backend selection)
  Backends/
    KeepBackend.swift
    Official/     OAuth (loopback + PKCE) and Keep API v1 client
    Unofficial/   Android token auth, EmbeddedSetup login, sync client, KeepNodeTree
  Support/        Keychain, JSONValue, dates, HTTP helpers
  Views/          Popover screens
```

`KeepNodeTree` is the pure, unit-tested core of the unofficial backend: it maps Keep's
node graph to `Note`s and builds the minimal set of dirty nodes for each change.
