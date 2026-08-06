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

**Done:** steps 1 and 2. Both key profiles exist and their public halves are
pinned in the app.

```bash
# stable
dart run desktop_updater:release keygen \
  --base-url https://jjaffeux.github.io/discourse-native/stable \
  --key-profile desktop_updater.keys.stable.json
# canary
dart run desktop_updater:release keygen \
  --base-url https://jjaffeux.github.io/discourse-native/canary \
  --key-profile desktop_updater.keys.canary.json
```

Keygen binds a profile to that channel's archive URL, which is why there are
two — and why a leaked canary key still cannot sign a stable release. The
`desktop_updater.keys.*.json` files hold **public material only** and are
committed. The private halves live in a 0600 file under
`~/Library/Application Support/desktop_updater/release-keys` (on Linux,
`$XDG_DATA_HOME/desktop_updater/release-keys`) and never leave it.

Their public halves are copied verbatim into `AppRelease.trustedReleaseKeys`,
both channels in one map, because the channel is chosen at runtime and a build
has to verify whichever one the user switches to.

**Still to do:**

3. **Back both private keys up — today.** There is no recovery. A lost key
   orphans every install and every user has to re-download by hand.

   ```bash
   export DU_PASSPHRASE='…20+ chars from a password manager…'
   dart run desktop_updater:release keys export \
     --output release-key-stable.dukey \
     --passphrase-env DU_PASSPHRASE \
     --base-url https://jjaffeux.github.io/discourse-native/stable
   ```

   and the same for canary. The passphrase is read from the named variable and
   is never accepted as an argument, so it cannot land in a shell history or a
   process listing. Put the bundle somewhere with a second custodian.

4. **Put the bundles in CI**, base64 of the `.dukey` file:

   | Secret | Value |
   |---|---|
   | `DU_KEY_STABLE` | `base64 -w0 release-key-stable.dukey` |
   | `DU_PASSPHRASE_STABLE` | the passphrase |
   | `DU_KEY_CANARY` | `base64 -w0 release-key-canary.dukey` |
   | `DU_PASSPHRASE_CANARY` | the passphrase |

   The workflow restores them with `keys import --passphrase-env`.

5. **Put the stable secrets behind a GitHub Environment with required
   reviewers.** Anyone who can push a workflow file to `main` can otherwise
   read them, and that key is what lets you install arbitrary code on every
   user's machine. Highest-value control here. Canary can stay repo-level.

6. **Rehearse a yank** against canary with a deliberately broken build.

### Rotation

`keys rotate` mints a pending key while the current one keeps signing; `keys
activate` switches over. The gap between them is the whole point: ship a
release whose `trustedReleaseKeys` carries **both** before activating, or every
client that missed it is stranded permanently. For a desktop app with no forced
updates, think months — so start the rotation you might need long before you
need it.

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
