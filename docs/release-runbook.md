# Release runbook

How builds get to users, and what to do when one of them is bad.

**Status: not yet exercised.** `.github/workflows/release.yml` has never had a
green run. Everything below the setup section is written from the design, not
from having done it. Rehearse it once against canary — deliberately — before
trusting it in an incident.

## Shape

| | |
|---|---|
| Artifacts | GitHub Releases. No bandwidth cap, no repo bloat. |
| Manifests | GitHub Pages, `gh-pages` branch. KB-scale and versioned in git, so a bad publish is one `git revert`. |
| Stable | An annotated tag `v1.3.0`, cross-checked against `pubspec.yaml`. |
| Canary | Every push to `main`, versioned `1.3.0-canary.<commits>`. |

```
gh-pages/
  index.html                                   download page + runtime deps
  stable/app-archive.json                      index of every stable release
  stable/releases/1.3.0/linux/release.json     signed descriptor
  canary/app-archive.json
  canary/releases/1.3.0-canary.412/linux/release.json
```

`app-archive.json` is an **index of every release**, not just the latest, which
is why CI merges into it with `app_archive upsert` rather than writing it fresh.

`pubspec.yaml` holds the *next unreleased* version. A human bumps it in a normal
PR; CI derives everything else, so no bot commit ever races a branch.

## One-time setup

None of this is done yet. In order:

1. **Generate a signing key per channel**, on a trusted workstation, never in
   CI. `desktop_updater.yaml`'s `updates.baseUrl` has to point at that channel's
   feed first, because keygen binds the profile to the archive URL:

   ```bash
   dart run desktop_updater:release keygen --base-url https://jjaffeux.github.io/discourse-native/stable
   ```

2. **Copy the public key map** it prints into `AppRelease.trustedReleaseKeys`
   in `lib/src/data/app_release.dart`, both channels in the one map — the
   channel is chosen at runtime, so a build has to be able to verify whichever
   one the user switches to. Public material only; safe to commit. Until this
   is done `AppRelease.canVerifyReleases` is false and the whole feature stays
   off, which is deliberate.

3. **Put the private keys in CI.** 3.1.1 stores them as local files and has no
   export command, so the secret is a tarball of the key directory:

   ```bash
   tar -czf - -C ~/.local/share/desktop_updater release-keys | base64 -w0
   ```

   into `DU_KEYS_STABLE` and `DU_KEYS_CANARY`. On macOS the directory is
   `~/Library/Application Support/desktop_updater/release-keys`, and CI restores
   it to the Linux path, so tar it from inside its parent as above.

4. **Put `DU_KEYS_STABLE` behind a GitHub Environment with required reviewers.**
   Anyone who can push a workflow file to `main` can otherwise read it, and that
   key is what lets you install arbitrary code on every user's machine. It is
   the highest-value control here. Canary can stay repo-level.

5. **Rehearse a yank** against canary with a deliberately broken build.

Two things to internalise while it is cheap: a lost private key is
unrecoverable and orphans every install, and there is no rotation command in
3.1.1 — so back the key up somewhere with a second custodian, today.

## Yanking a bad release

GitHub Pages sits behind Fastly with `cache-control: max-age=600`. That cuts
both ways: a bad index propagates in ten minutes, and so does its removal.

The thing to internalise before you need it:

> Removing the index entry stops **new** discovery. Only a **higher version**
> reaches anyone who already updated.

### 1. Stop the bleeding

```bash
git clone --branch gh-pages git@github.com:jjaffeux/discourse-native.git
cd discourse-native
git log --oneline -5 -- stable/app-archive.json
git revert --no-edit <sha-of-the-bad-publish>
git push
```

A revert rather than checking out an old blob, because it is itself a
reviewable, attributable commit in the same history. Pages rebuilds in about
thirty seconds; Fastly expires within ten minutes.

### 2. Decide about the artifact, deliberately

Do **not** reflexively delete the release.

- **Will not launch, or corrupts data** — delete the zip asset. Clients
  mid-download get a 404 and fail closed, which is what you want.
- **Merely buggy** — leave it. Mark the release a draft so people stop finding
  it, but let in-flight downloads finish: a half-downloaded update that starts
  404ing is a worse experience than the bug.
- **Compromised signing key** — delete everything and generate a new key. The
  index revert does not help you here, because the attacker's `release.json`
  carries a valid signature. Every existing install has to be replaced by hand.

### 3. Roll forward — this is the step people skip

It is the only one that reaches users who already updated.

```bash
git revert --no-edit <the-bad-code-commit>
# bump pubspec to 1.3.1
git commit && git tag v1.3.1 && git push --tags
```

Ship the previous good code under a **higher** version. Never re-publish the
same version against a different artifact hash — that ambiguity is exactly what
the signing scheme exists to prevent, and clients already on the bad build will
refuse a downgrade anyway.

## Known limits

- **The 600s TTL is not tunable.** Pages sets it and you cannot send
  `no-cache`. If ten minutes is ever unacceptable, put Cloudflare in front of
  the Pages origin and purge on deploy — worth doing before the first stable
  release rather than during an incident.
- **Measure the real propagation once**, with a throwaway canary version, and
  replace the theoretical ten minutes here with what you actually observed.
- **Canary is the pressure valve.** Every stable release should have spent time
  on canary. This runbook is the thing you hope never to run; canary is what
  keeps it that way.
