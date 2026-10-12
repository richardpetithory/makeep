# MaKeep

A macOS menu bar app for quickly adding and editing Google Keep notes and lists.

## Build & run

```sh
make run       # build build/MaKeep.app and launch it
make test      # unit tests
make install   # copy to /Applications
```

Requires macOS 14+ and Xcode / Swift 6.2+.

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
Sources/MaKeep/
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
