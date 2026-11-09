# Cinematic reading and simple setup — 0.52.0 (115)

## MangaBaka series

The enlarged cover provides a cinematic, softened backdrop; the real cover and typeset title stay clear in front. Read / More Info / Similar tabs organize the existing reading source, publication, anime adaptations, chapter coverage, tags, covers, external links and recommendations. A linked source opens Continue reading directly; an unlinked manga opens source search. Novels retain their reading-options guidance.

The adjacent plus/check opens the reading-status editor or API-key connection. Section hiding/order, publisher navigation, image enlargement, account switching, attribution and reading progress remain available.

## First launch

Four optional stages replace the eight-step wizard: Welcome → Libraries → Preferences → Ready. Users can enter MangaBaka's API key directly, follow the link to create one, or continue without accounts. Appearance and adult-content preferences stay simple; reading sources, TorBox and streaming add-ons can be configured from the optional final link or Settings. Existing installations do not have onboarding forced again, and unfinished older wizards resume in the corresponding short stage.

New MangaBaka connections use API keys only. The former bundled MangaBaka OAuth application ID and browser sign-in UI are removed. Existing saved OAuth accounts can still restore/refresh through their own stored client ID. Each key is validated against its account before saving. Accounts and keys are stored in the device-only Keychain, with separate account caches.

## Shareable build checks

- Source scanning checks credential literals without printing matched values.
- The actual compiled Release app is checked before IPA packaging. Credential patterns, private device/database files, debug account markers and bundled MangaBaka OAuth app configuration fail the build.
- App data is created at runtime for each installation. The IPA is assembled from a clean CI build; device Keychain, preferences, user libraries, source links and private add-on configurations are not copied into it.
- DEBUG previews use neutral owned fixtures and are excluded from Release. The audit checks their sensitive marker strings as a packaging guard.

The source currently has no bundled **public AniList app client ID**. Existing users with their own configured ID retain sign-in. Fresh users can browse and connect MangaBaka; one-tap AniList sign-in for friends requires adding the registered public client ID to the build. A client ID identifies the app; it is not a user's access token. No ID or secret is guessed or borrowed.

## Focused device checks

1. On a fresh test installation, complete setup without accounts. Confirm the library starts empty and there are no saved profiles, keys or private add-ons. Do not delete an existing installation with reading history merely to run this check; use a separate device/test installation.
2. Connect with your own MangaBaka API key. Confirm profile validation, saved-account switching, reopening the app and invalid-key feedback. No browser OAuth app registration is involved.
3. Open manga, manhwa and a novel. Check the cinematic top edge, Read / More Info / Similar, library editing, a linked source's Continue reading, publisher navigation and cover enlargement.
4. Reopen the welcome guide from Settings and verify existing accounts/progress are retained. Revisit section customization and check a hidden Read or Similar tab stays hidden.

Reference for the key-creation link and `x-api-key` transport: https://mangabaka.org/developers/guides/authenticate-with-a-token
