# Device sync and portable backups

Open **Settings → Sync & backup**. In Files, create a private folder in iCloud
Drive (for example `Next Sync`), then select that same folder on each device.
An `On My iPhone` folder is local storage and cannot sync between devices.
The app creates its own `AnimeCompanion Sync` subfolder. Avoid editing its files.

The app checks on foreground arrival, after local changes (a two-second debounce)
and every 30 seconds while active. **Sync Now** requests an immediate check.
iCloud Drive controls upload/download delivery; a successful local folder write
does not prove that another device has downloaded it. There is no continuous
background execution guarantee. Local reading works without a network.

Included data:

- Appearance, navigation, Home widgets, Explore layouts, library defaults,
  display preferences, content/discovery filters, schedule and news preferences.
- Local manga titles, saved membership, per-chapter reading positions/read flags,
  recent/pinned sources and reader preferences.
- MangaBaka account-scoped links to reading sources (sign in to the matching
  MangaBaka account to use those links).
- Installed manga extension descriptors, enabled status and repository setup.
  Each receiving device downloads packages again using the original repository
  allowlist, GitHub release digest validation and runtime package inspection.
  At most three packages are downloaded per pass. Unavailable versions remain
  pending and show a notice; update/reinstall those manually if removed upstream.
- Video player selection, tracking preferences and local video resume positions.

Account tokens, API keys, private source settings, configured Stremio/Seanime
add-ons, website cookies, active player callbacks and offline downloads are not
exported. Those stay in their existing device-local secure stores. Sign in and
configure private connections separately on each device. AniList/MangaBaka online
library sync continues through those providers.

**Export Backup** creates a portable JSON snapshot for Files or AirDrop.
**Merge a Backup** validates it, previews its date/counts and asks before applying
it. Included values replace matching local values; unrelated local books remain.
When folder sync is connected, restored values also sync. Backups and sync files
contain reading titles and preferences, so select a private folder.

Disconnecting keeps local data and remote files. Reset App disconnects this
device and erases its local journal without publishing a deletion of the shared
library. Reconnect the same folder after setup to restore synced data.

## Implementation and limits

Directory access uses the system document picker, minimal security-scoped
bookmarks and `NSFileCoordinator` off the main actor. This works with file
providers exposed in Files, without a CloudKit container, special signing
entitlements or a custom backend. It suits unsigned IPA distribution followed
by ordinary sideload signing.

Each installation writes a separate UUID-named `.nextsync` file. Reads merge all
device snapshots and unresolved file versions. Individual settings, title
metadata, saved flags, history, chapter positions, pins, links and extensions
have independent registers. Logical clocks advance beyond observed remote
clocks; simultaneous conflicts have a deterministic author tie break. Changing
the same field offline on two devices resolves to one value, while independent
fields merge. Deletions retain tombstones. Accurate device clocks are helpful.

First connection uses existing folder values for overlapping fields and merges
unique local titles. New local edits thereafter carry normal change stamps.
Local journals retain pending remote values separately from actually applied
values, so a failed package download cannot become an accidental uninstall.
Storage-actor patches recheck captured values to preserve concurrent reader
saves. Reset epochs invalidate local and external writes from an old session.

Files are validated before any section applies; unknown versions/keys,
malformed identities, oversized collections and inaccessible files stop the
pass. Existing local data remains available. Limits include 48 MB per sync or
backup file, 64 device files, 5,000 manga records/source links and 64 extensions,
plus the existing 16 MB reading/link store limits. Sync does not prune device
snapshots or deletion records automatically.

## Focused device check

1. Connect an iPhone and iPad to the same private iCloud Drive folder.
2. Change a Home widget order, theme and player on one; save a local manga and
   link a MangaBaka title to a source. Check the other device after delivery.
3. Read different chapters offline on each. Reconnect and verify both positions.
4. Unsave a title, unpin a source and remove a source link/extension. Reconnect a
   previously offline device and verify the removals are preserved.
5. Export a backup, change a setting, merge the backup and verify its preview,
   restored setting and preservation of unrelated local titles.
6. Disconnect or reset one device. Verify the other device and cloud files are
   kept. Reconnect the reset device to restore its setup.
