# Privacy

V-Paste is a local-first clipboard manager. Its core feature is remembering clipboard content, so users should understand exactly what is stored and when the app touches the network.

## Data Stored Locally

V-Paste may store the following data on the user's Mac:

- Clipboard text
- Copied file URLs and file paths
- Image assets and generated thumbnails
- Link preview titles and cached favicons
- Source application name and bundle identifier
- Clipboard item timestamps, favorites, groups, and retention metadata
- Optional Jev request/token counters and local estimated cost records

By default, app data is stored in the user's Application Support directory under the current bundle identifier, for example:

```text
~/Library/Application Support/io.vpaste.app/
```

The main database is:

```text
history.sqlite3
```

When Jev is configured, its API key is stored in the macOS Keychain rather than the clipboard database. Jev usage estimates are stored locally in `jev_usage.sqlite3`, and bounded diagnostic logs may be stored in `jev.log` with automatic rotation.

Cached images and thumbnails are stored in sibling asset folders in the same Application Support directory.

## Network Access

When a copied clipboard item is a web URL, V-Paste may fetch that page and its icon URL to create a richer link preview. The request uses a V-Paste user agent and a short timeout.

V-Paste does not upload clipboard history to a V-Paste service and does not include analytics or telemetry collection in this repository.

### Optional Jev Contextual Recommendations

Jev is an experimental, off-by-default feature that uses TypeSafe SystemOne. It becomes available only after the user enables Experimental Features, supplies their own TypeSafe API key, and enables Jev Recommendations.

For a recommendation request, V-Paste may send:

- The destination application name and limited focused-control metadata
- A length-limited window title, placeholder, selected-text excerpt, or value excerpt
- Up to 40 locally ranked clipboard candidate summaries containing an anonymous session key, content type, redacted and truncated preview, source application name, age bucket, and favorite state

Before transmission, V-Paste blocks known credential formats and high-entropy secret-like values, masks supported email addresses and phone numbers, replaces the local home-directory prefix, and limits field lengths. It does not send local clipboard UUIDs, absolute file paths, image binaries, or cached asset paths. If the destination is a secure field, its security classification is unknown, the destination application is ignored, or a detected secret is present, the request is not sent.

TypeSafe processes data sent through this optional integration under its own terms and privacy practices. Local token and cost values are estimates for reference only; official usage and charges are available at [TypeSafe Usage](https://console.typesafe.ai/usage).

## Clearing Data

The app includes storage controls for clearing clipboard history and local Jev usage statistics. Removing the Jev API key deletes it from the macOS Keychain and disables Jev. Users can also remove local data manually by quitting V-Paste and deleting the app's Application Support folder.

## Security Notes

Clipboard managers handle sensitive data by nature. Users should avoid copying secrets while monitoring is enabled, or pause monitoring before copying passwords, tokens, private keys, or other sensitive content.
