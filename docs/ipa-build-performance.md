# IPA build performance

The optimization and measured first-population/warm-cache results are tracked in
[PR #77](https://github.com/goon-123/AnimeCompanion/pull/77). The PR changes CI only;
it is based on `main` commit `0cfab06` and does not change application source or
`project.yml`.

## What was slow

The [27m08s reference run](https://github.com/goon-123/AnimeCompanion/actions/runs/43070296825)
spent 16m compiling the Release app, 4m59s compiling/running the Apple encrypted
startup-cache tests before that build, and 4m15s preparing/testing the native manga
runtime. Restoring its 1.08 GB Cargo cache alone took 1m55s. npm and IPA upload were
only seconds, so they were not the main bottlenecks.

That reference includes the newer app source from PR #75. The
[successful main build](https://github.com/goon-123/AnimeCompanion/actions/runs/42962541413)
provides the same-app-source control: 12m42s Release compilation and a 23m05s
queue-free critical path. It had a long macOS scheduling delay, so its full workflow
wall time is unsuitable as a build-speed baseline.

## What changed

- Run the Apple encrypted-cache tests in a separate macOS job alongside native
  runtime preparation. Both still gate IPA creation, as do core, Safari,
  MangaBaka and extension-runtime checks.
- Cache Xcode intermediates, modules and package checkouts separately from
  runtime artifacts. Restore input timestamps at nanosecond precision **only
  when SHA-256 content matches**. Modified files rebuild normally; new/deleted
  files invalidate directory timestamps. Xcode still executes on every build.
- Key Xcode/SwiftPM caches by platform, architecture, actual toolchain/SDK and
  configuration. A toolchain-compatible fallback also survives version bumps
  in `project.yml`; Xcode still invalidates changed project settings and inputs.
  Compatible fallback caches are build inputs, never a reason to skip validation.
- Cache final native device/simulator libraries plus host-test inputs instead
  of three sets of cross-compiled Cargo intermediates. Native compile bypass
  requires an exact key covering toolchains, Cargo manifests/lockfile, runtime
  sources, headers, patches, fixtures and scripts. Missing libraries rebuild.
  Old cache entries can seed Cargo, but always go through `cargo build`.
- Save caches after successful validation. Cache service failures allow a normal
  build. No account data, root Git credentials, IPA or Payload is cached.
- Disable editor indexing during the Release compile, retain optimization and
  device settings, print build timings, and verify ZIP integrity before upload.
  Save the validated Xcode cache before artifact upload, with a three-minute
  upload timeout so a stuck transfer can be retried without compiling again.

Both simulator library architectures, the generic iOS destination, Safari bundle
and release privacy checks, artifact name/retention and all opt-in UI suites are
preserved. Unsigned IPAs still need signing before installation.

## Reproduce the benchmark

Use the run IDs linked in the PR:

```sh
python3 scripts/benchmark-ipa.py 42962541413 43070296825 FIRST_RUN_ID WARM_RUN_ID
```

The script reads public GitHub Actions timestamps and reports workflow wall time,
time until the IPA is uploaded, job durations and compile/test/package steps. It
also reports a clearly labeled **queue-free critical path**: the longest
prerequisite job plus the IPA build job, including cache restore/save overhead.
This is a scheduling model, not observed wall time. Optional `GH_TOKEN` or
`GITHUB_TOKEN` increases API rate limits; local JSON snapshots are also accepted.

Distinguish first-population runs from unchanged-source cache repeats. A warm
repeat is a best-case measurement, not a promise for every feature change:
Release whole-module compilation can still rebuild an entire changed module.
Toolchain/configuration changes and cache eviction also cause rebuilding.
GitHub scopes pull-request caches to that PR. The first build on `main` after
merging may need to populate its own caches; subsequent PRs can restore `main`'s
caches. The repeat benchmark measures reuse within this PR.

After merging, **Actions → iOS unsigned IPA → Run workflow** offers
`use_build_cache`. Turn it off for a clean build; all validation still runs.
Keep `run_ui_tests` off when comparing with the normal IPA pipeline. The original
longer simulator suites remain available by turning it on.

References: [Apple incremental builds](https://developer.apple.com/documentation/xcode/improving-the-speed-of-incremental-builds),
[GitHub cache matching and scope](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching),
and [artifact compression](https://github.com/actions/upload-artifact#altering-compressions-level-speed-v-size).
