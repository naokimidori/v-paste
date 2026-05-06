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

By default, app data is stored in the user's Application Support directory under the current bundle identifier, for example:

```text
~/Library/Application Support/io.vpaste.app/
```

The main database is:

```text
history.sqlite3
```

Cached images and thumbnails are stored in sibling asset folders in the same Application Support directory.

## Network Access

When a copied clipboard item is a web URL, V-Paste may fetch that page and its icon URL to create a richer link preview. The request uses a V-Paste user agent and a short timeout.

V-Paste does not need an account, does not upload clipboard history to a V-Paste service, and does not include analytics or telemetry collection in this repository.

## Clearing Data

The app includes storage controls for clearing clipboard history. Users can also remove local data manually by quitting V-Paste and deleting the app's Application Support folder.

## Security Notes

Clipboard managers handle sensitive data by nature. Users should avoid copying secrets while monitoring is enabled, or pause monitoring before copying passwords, tokens, private keys, or other sensitive content.
