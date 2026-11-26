# Device sync and portable backups

Open **Settings → Sync & backup → Enable Automatic iCloud** on both devices.
When the installed signing profile enables iCloud Documents, the app obtains its
own iCloud container and creates/reuses its sync directory automatically. No
external folder selection is needed. Use the same iCloud account and app
container on both devices. The app never substitutes local storage when iCloud
access is unavailable.

Unsigned distribution and many sideloading profiles do not grant an iCloud
container. If automatic setup is unavailable, the app explains this and offers
**Use a Files Folder**. Select the same private, writable iCloud Drive folder on
both devices. The system may require navigating into or creating a subfolder
rather than selecting a provider's top-level iCloud Drive location. The app
creates its own `AnimeCompanion Sync` subfolder. It validates reading and writing
before saving the connection; failed selections keep the previous connection.
An `On My iPhone` folder is local storage and cannot sync between devices.
Existing folder connections are retained after upgrading. Avoid editing sync files.

The app checks automatically on launch and each foreground return, after local changes (a two-second debounce)
and every 30 seconds while active. **Sync Now** requests an immediate check.
iCloud Drive controls upload/download delivery; a successful local folder write
does not prove that another device has downloaded it. There is no continuous
background execution guarantee. Sync runs without a blocking overlay and the
local library stays usable. A return during an in-flight pass queues a fresh
check immediately after that pass, rather than waiting for the next timer.
Local preparation is shared across scene changes and does not wait for an
extension catalog download. Local reading works without a network.

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

Automatic setup uses `url(forUbiquityContainerIdentifier: nil)` off the main actor
to obtain the default container granted by the installed signature. It checks
the archived iCloud account identity on restore and before file writes. Account
changes invalidate an in-flight pass and require explicitly enabling the new
account before syncing its data. Temporary iCloud unavailability preserves the
connection for retry.

Files fallback uses the system SwiftUI folder importer, open-in-place support,
minimal security-scoped bookmarks captured before importer dismissal, and
`NSFileCoordinator` off the main actor. It needs a one-time user folder grant
and does not require the app's own iCloud entitlement. Missing or inaccessible
storage is reported rather than mistaken for an empty cloud library.

### Signing automatic iCloud builds

The app target declares iCloud Documents in `App/AnimeCompanion.entitlements`
and publishes the `iCloud.com.animecompanion.ios` Documents container in
`project.yml`. A developer must register that container in Apple Developer,
associate it with the app ID, and sign with a provisioning profile granting
the declared iCloud services and containers. The unsigned CI IPA does not
contain a provisioning profile and cannot turn those capabilities on. A
resigning tool may remove or omit them. Do not claim automatic mode works until
the installed signed copy can obtain its iCloud container on a real device.

If using a different registered container, update both the entitlements and
`NSUbiquitousContainers` metadata. A source build intended only for the Files
fallback can override `CODE_SIGN_ENTITLEMENTS` to an empty value when signing.
No CloudKit database, push-notification permission or custom backend is used.

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

1. On an iCloud-enabled signed iPhone/iPad build, tap Enable Automatic iCloud.
   Verify that no folder picker appears and the app creates/reuses its container.
   On a copy without that capability, verify the clear unavailable message and
   use the Files fallback to select the same private iCloud Drive folder.
2. Change a Home widget order, theme and player on one; save a local manga and
   link a MangaBaka title to a source. Check the other device after delivery.
   Close and reopen the receiving app and verify updates arrive without pressing
   Sync Now, while you can still scroll and open locally saved titles.
3. Read different chapters offline on each. Reconnect and verify both positions.
4. Unsave a title, unpin a source and remove a source link/extension. Reconnect a
   previously offline device and verify the removals are preserved.
5. Export a backup, change a setting, merge the backup and verify its preview,
   restored setting and preservation of unrelated local titles.
6. Disconnect or reset one device. Verify the other device and cloud files are
   kept. Reconnect the reset device to restore its setup.
7. Change the iCloud account with automatic mode enabled. Verify sync pauses
   until the new account is explicitly enabled, with local data kept.
