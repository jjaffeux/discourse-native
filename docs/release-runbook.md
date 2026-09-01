# Release runbook

How Linux builds get to users, how to prove a publish is sound, and what to do
when one is not. The app itself does not update Linux installations: dpkg owns
the files under `/usr`, and users receive updates through `apt upgrade`.

## Distribution model

The release workflow builds the production app from the `profiles/full`
compatibility wrapper. It uses the same always-bundled Resenha graph as the
root app, produces one amd64 `.deb`, and publishes it in two places:

- a signed apt repository on the `gh-pages` branch, which is the normal install
  and update path;
- a GitHub Release asset, for direct download.

Stable and canary are separate, self-contained apt repositories. They share one
repository-signing key, but never share a package pool or metadata:

```text
gh-pages/
  .nojekyll
  index.html
  key.asc
  apt/
    stable/
      dists/stable/{InRelease,Release,Release.gpg}
      dists/stable/main/binary-amd64/{Packages,Packages.gz}
      pool/main/d/discourse-native/*.deb
    canary/
      dists/canary/{InRelease,Release,Release.gpg}
      dists/canary/main/binary-amd64/{Packages,Packages.gz}
      pool/main/d/discourse-native/*.deb
```

`InRelease` and `Release.gpg` authenticate the repository metadata. `Packages`
contains the hash and repository-relative path of every `.deb` apt may offer.
The `.deb` therefore has to live on GitHub Pages beside the metadata; a GitHub
Release URL cannot be substituted into `Filename:`.

The workflow keeps the newest three `.deb` files in each current pool. Old
files remain in `gh-pages` git history, and every direct-download Release
remains until somebody explicitly removes it. This is why canary is on demand,
not a build of every push to `main`.

## Channels and versions

The root `pubspec.yaml` holds the canonical next stable version. The workflow
reads only its
`major.minor.patch` part; the `+build` suffix is ignored. Its build number is
the full git commit count at the source revision.

| Channel | Trigger | App/GitHub version | Debian version | GitHub Release |
|---|---|---|---|---|
| stable | push `v<major>.<minor>.<patch>` | `1.0.0` | `1.0.0` | normal release |
| canary | manual workflow dispatch | `1.0.0-canary.26` | `1.0.0~canary26` | prerelease |

The tilde in the Debian canary version is deliberate: dpkg orders
`1.0.0~canary26` before `1.0.0`, so a canary installation can move onto the
same-base stable release with an ordinary upgrade. A semver hyphen in the
Debian version would sort the other way and strand canary users.

The Pages filename contains that tilde. GitHub Releases normalizes it to a dot,
so the same canary bytes appear there as
`discourse-native_1.0.0.canary26_amd64.deb`. Stable filenames need no
normalization.

Manual dispatch has no channel input and always publishes canary. Stable is
selected only for a matching tag-push event; even a manual run whose `--ref`
names a tag remains canary. This trigger boundary is deliberate: a branch named
like `v1.0.0` can never publish stable.

## Signing key and Actions secrets

Apt clients pin the public key at
`https://jjaffeux.github.io/discourse-native/key.asc` with `signed-by=`. Its
fingerprint is:

```text
F904 D947 00FC B60E A7AF  7F8A F76E E5A2 17CD FCD0
```

The workflow uses exactly two user-managed Actions secrets:

| Secret | Contents |
|---|---|
| `APT_GPG_PRIVATE_KEY` | base64 of an ASCII-armored secret-key export |
| `APT_GPG_PASSPHRASE` | passphrase for that secret key |

It base64-decodes and imports the key into an ephemeral `GNUPGHOME`, writes the
passphrase to a mode-0600 file, signs both forms of the Release metadata, and
exports the public half to `key.asc`. The automatic `GITHUB_TOKEN`, granted
`contents: write` by the workflow, pushes `gh-pages` and creates the GitHub
Release; it is not a stored secret.

There are no per-channel signing secrets. In particular, the old `DU_*`
desktop-updater keys are not used by this workflow. It also declares no GitHub
Environment, so the apt secrets must be repository or organization Actions
secrets available to the job; an Environment-only secret is not visible. At
the workflow level there is no separate stable key or approval gate. Protect
who can push matching tags, change the workflow, access release secrets, and
write `gh-pages` in repository settings.

### Backup

GitHub secrets are write-only. Keep the armored private key, its passphrase,
and the GPG revocation certificate with a second custodian. The passphrase is
currently stored as `op://Employee/discourse-native apt/password`; a 1Password
document beside it is a suitable home for the key export and revocation
certificate.

To make a fresh export from the workstation that owns the key:

```sh
export APT_GPG_PASSPHRASE="$(op read 'op://Employee/discourse-native apt/password')"
umask 077
printf '%s\n' "$APT_GPG_PASSPHRASE" |
  gpg --batch --pinentry-mode loopback --passphrase-fd 0 \
    --export-secret-keys --armor \
    F904D94700FCB60EA7AF7F8AF76EE5A217CDFCD0 \
    > apt-signing-key.asc
base64 < apt-signing-key.asc | tr -d '\n'
```

The final command prints the value for `APT_GPG_PRIVATE_KEY`. Do not paste that
value into logs. `*.asc` is not gitignored here, so do not leave the export in
the repository. Also retain the matching file from
`~/.gnupg/openpgp-revocs.d/`.

Losing the private key does not break already-installed packages, but it makes
new metadata impossible to sign. Replacing `key.asc` on Pages alone does not
rotate trust: existing users pinned a local copy and do not fetch it again.
Key rotation therefore needs a planned client-key migration while the old key
is still controlled; it is not just a secret replacement.

## Publish a canary

Canary is the rehearsal path for stable. Merge the intended revision to
`main`, then dispatch one build deliberately:

```sh
git switch main
git pull --ff-only
gh workflow run release.yml --ref main
```

The command prints the run URL when GitHub returns one. Record its run ID and
follow it to completion:

```sh
gh run list --workflow release.yml --event workflow_dispatch --limit 5
gh run watch <run-id> --exit-status
gh run view <run-id> --log-failed
```

Do not dispatch the same source commit again after any publication. The canary
version is derived from that commit's history count, so a rerun reuses the same
Debian version, Git tag, and asset identity. A transient failure is safe to
retry only after confirming that neither Pages nor Releases changed; otherwise
fix the problem in a new commit and dispatch that revision instead.

Exercise the canary on a supported Ubuntu 22.04+ or Debian 12+ amd64 machine
before releasing the same code as stable. In addition to startup and the
changed behavior, test an `apt upgrade` from the previous canary and, when a
same-base stable exists, the transition back to stable after switching the apt
source line.

## Publish stable

Land the version bump in an ordinary reviewed PR and let that exact revision
spend time on canary. From an up-to-date `main`, verify the pubspec base version
and create the tag:

```sh
git switch main
git pull --ff-only
VERSION=1.0.0
test "$(sed -nE 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' pubspec.yaml | head -1)" = "$VERSION"
git tag -a "v$VERSION" -m "Discourse $VERSION"
git push origin "v$VERSION"
```

The workflow accepts a matching lightweight tag too, but an annotated tag
leaves the release intent in git. Stable selection also requires the `push`
event to carry a tag ref; a manual run cannot select it. Any mismatch between
`v$VERSION` and the pubspec base version fails before packaging. Never move or
reuse a published tag; fix forward under a higher version.

Find and watch the tag-triggered run (its event is `push`, not
`workflow_dispatch`):

```sh
gh run list --workflow release.yml --event push --limit 5
gh run watch <run-id> --exit-status
gh run view <run-id> --log-failed
```

Do not announce the release until both the apt repository and the GitHub
Release checks below pass.

## What the workflow validates and publishes

Before publication, the job:

1. resolves the root app, native CallKit bridge, and compatibility-wrapper
   lockfiles; analyzes all three package roots; runs the complete application
   tests; then builds `profiles/full` against
   Ubuntu 22.04/glibc 2.35 and checks that the bundle uses WebKitGTK 4.1;
2. lays the app under `/usr/lib/discourse-native`, adds the
   `/usr/bin/discourse-native` symlink plus desktop and icon files, and builds
   an amd64 `.deb`;
3. checks package metadata, executable and symlink modes, and asks apt to
   resolve the declared dependencies without installing them;
4. copies the `.deb` into the selected Pages pool, prunes that pool to three,
   regenerates `Packages`, `Packages.gz`, `Release`, `InRelease`, and
   `Release.gpg`, then commits and pushes `gh-pages`;
5. creates the GitHub Release and uploads the same `.deb` as a direct-download
   asset.

Publication is serialized per channel. Stable and canary may run concurrently
because they touch different repository trees; a push conflict is rebased and
retried up to three times.

The order in steps 4 and 5 matters during recovery: apt publication completes
before the GitHub Release asset is uploaded. A run can therefore finish red
while the package is already live to apt clients.

## Verify a publication

First inspect the workflow result and its source revision. Then verify the
published repository independently on a supported Linux machine. Set
`CHANNEL` and the exact **Debian** version that was just released:

```sh
CHANNEL=canary
VERSION='1.0.0~canary26'
BASE=https://jjaffeux.github.io/discourse-native
EXPECTED_FINGERPRINT=F904D94700FCB60EA7AF7F8AF76EE5A217CDFCD0
VERIFY_DIR="$(mktemp -d)"

curl -fsSLo "$VERIFY_DIR/key.asc" "$BASE/key.asc"
ACTUAL_FINGERPRINT="$(gpg --batch --show-keys --with-colons "$VERIFY_DIR/key.asc" |
  awk -F: '$1 == "fpr" { print $10; exit }')"
test "$ACTUAL_FINGERPRINT" = "$EXPECTED_FINGERPRINT"

curl -fsSLo "$VERIFY_DIR/InRelease" \
  "$BASE/apt/$CHANNEL/dists/$CHANNEL/InRelease"
gpg --batch --yes --dearmor --output "$VERIFY_DIR/key.gpg" \
  "$VERIFY_DIR/key.asc"
gpgv --keyring "$VERIFY_DIR/key.gpg" "$VERIFY_DIR/InRelease"

curl -fsSLo "$VERIFY_DIR/Packages.gz" \
  "$BASE/apt/$CHANNEL/dists/$CHANNEL/main/binary-amd64/Packages.gz"
gzip -dc "$VERIFY_DIR/Packages.gz" > "$VERIFY_DIR/Packages"
PACKAGE_PATH="$(awk -v version="$VERSION" '
  $1 == "Version:" { wanted = ($2 == version) }
  wanted && $1 == "Filename:" { print $2; exit }
' "$VERIFY_DIR/Packages")"
EXPECTED_SHA256="$(awk -v version="$VERSION" '
  $1 == "Version:" { wanted = ($2 == version) }
  wanted && $1 == "SHA256:" { print $2; exit }
' "$VERIFY_DIR/Packages")"
test -n "$PACKAGE_PATH" && test -n "$EXPECTED_SHA256"

curl -fsSLo "$VERIFY_DIR/discourse-native.deb" \
  "$BASE/apt/$CHANNEL/$PACKAGE_PATH"
printf '%s  %s\n' "$EXPECTED_SHA256" "$VERIFY_DIR/discourse-native.deb" |
  sha256sum --check -
test "$(dpkg-deb --field "$VERIFY_DIR/discourse-native.deb" Version)" = "$VERSION"
dpkg-deb --info "$VERIFY_DIR/discourse-native.deb"
```

This checks the pinned fingerprint, the metadata signature, the advertised
package hash, and the embedded Debian version. It intentionally does not trust
the key merely because it came from the same server as the metadata.

Finally exercise apt's view and the direct-download Release:

```sh
sudo apt update
apt-cache policy discourse-native
sudo apt-get install --simulate discourse-native
gh release view "v<app-version>"
```

`apt-cache policy` must show the expected candidate from the selected channel.
The GitHub Release must point at the intended source revision and contain the
same package bytes. For canary, remember that its displayed asset filename uses
`.canary26` where the Debian/Pages filename uses `~canary26`. The install and
source-list commands users follow are maintained in the README.

## Failed and partial publishes

Locate the last completed step before retrying anything:

- A failure before **Publish to the apt repository** leaves no public package.
- A failure inside that step may have pushed `gh-pages`; inspect the remote
  channel and run the verification above.
- A failure in **Publish the .deb on Releases** means apt is already live, even
  though the run is red.

If apt is sound but only the GitHub Release asset is missing, recover the exact
`.deb` from the Pages pool and upload that file. Do not rebuild different bytes
under the same version:

```sh
CHANNEL=canary
APP_VERSION=1.0.0-canary.26
DEB_VERSION='1.0.0~canary26'
TAG="v$APP_VERSION"
PAGES_ASSET="discourse-native_${DEB_VERSION}_amd64.deb"
RELEASE_ASSET='discourse-native_1.0.0.canary26_amd64.deb'
curl -fsSLo "$RELEASE_ASSET" \
  "https://jjaffeux.github.io/discourse-native/apt/$CHANNEL/pool/main/d/discourse-native/$PAGES_ASSET"
gh release upload "$TAG" "$RELEASE_ASSET" --clobber
```

If the Release itself was not created, create it at the source SHA recorded in
the `gh-pages` publish commit. Verify the package hash before uploading it:

```sh
SOURCE_SHA=<source-sha-from-the-gh-pages-commit>
gh release create "$TAG" "$RELEASE_ASSET" --target "$SOURCE_SHA" \
  --title "Discourse $APP_VERSION" --generate-notes --prerelease
```

Omit `--prerelease` for stable. A stable tag already exists and must still
point at `SOURCE_SHA`.

## Yank or roll back a bad package

Removing a release from GitHub does not affect apt: apt downloads its separate
copy from Pages. Stop new discovery at the apt repository first.

### 1. Restore the channel to a known-good signed state

Clone `gh-pages`, find the last good commit for the affected channel, and
restore only that channel's tree. Reusing its already-signed metadata avoids
needing the private key on the incident machine and preserves changes made to
the other channel.

```sh
git clone --branch gh-pages --single-branch \
  git@github.com:jjaffeux/discourse-native.git discourse-native-pages
cd discourse-native-pages
CHANNEL=canary
git log --oneline -- "apt/$CHANNEL"
GOOD=<last-good-gh-pages-commit>
git restore --source="$GOOD" -- "apt/$CHANNEL"
git add -A -- "apt/$CHANNEL"
git diff --cached --stat
git commit -m "$CHANNEL: roll back bad package"
git push origin gh-pages
```

Verify the restored `InRelease` before pushing when possible, then repeat the
remote verification after the push. GitHub Pages currently serves these files
with `cache-control: max-age=600`, so allow up to ten minutes for an edge cache
to expire. Clients also need to run `apt update` before their local package list
reflects the rollback.

Restoring the tree removes the bad `.deb` as well as its metadata entry. That
means clients holding stale Packages metadata fail closed with a 404 once the
file disappears, instead of completing a new bad installation. Git history
still retains the artifact for forensics.

### 2. Hide the direct-download release

Draft the GitHub Release so it is no longer advertised:

```sh
gh release edit "v<app-version>" --draft
```

For a package that will not launch, corrupts data, or is compromised, also
delete its direct-download asset after recording its hash and preserving an
incident copy:

```sh
gh release delete-asset "v<app-version>" \
  "<asset-name-shown-by-gh-release-view>" --yes
```

Deleting the GitHub asset does not remove the git tag. Do not move the tag or
publish a different artifact under the same version.

### 3. Roll forward under a higher version

Repository rollback only protects users who have not installed the bad build.
Already-updated clients require a higher version:

- for stable, revert or fix the code, bump `pubspec.yaml` to a higher patch
  version, and publish a new matching stable tag;
- for canary, land the fix as a new commit and dispatch a new canary so its git
  history count, and therefore its Debian version, increases.

Never rerun the bad source revision or reuse its version. Apt and intermediary
caches assume one immutable artifact per package name and version.

If an affected user must downgrade before the fixed release exists, first
confirm that the restored repository advertises the known-good version, then
make the downgrade explicit:

```sh
apt-cache policy discourse-native
sudo apt install --allow-downgrades discourse-native=<known-good-debian-version>
```

Treat this as incident guidance, not the normal recovery path; application data
written by a newer build may not be backward compatible.

## Key compromise and repository recovery

If the signing key may be compromised, remove the Actions secrets and revoke
the attacker's repository access immediately, preserve the suspect metadata
and artifacts, and restore each affected channel to a known-good signed state.
The index rollback alone is not sufficient while an attacker still has both a
trusted key and Pages write access.

Generate a replacement key only after access is contained. Existing users must
replace their pinned `/usr/share/keyrings/discourse-native.asc`; publishing a
new `key.asc` does not update that local file. Communicate the new fingerprint
over an independently trusted channel. If the old key remains trustworthy,
plan a transition before switching signatures rather than discovering this
during an incident.

If `gh-pages` is damaged but the key is safe, the channel-restore procedure
above is the fastest recovery because every historical publish is a complete,
signed repository snapshot. Direct-download `.deb` files can also be recovered
from GitHub Releases. Prefer a new, higher release after restoration; rebuilding
an old version risks assigning different bytes to an identity clients have
already cached.

## Known limits

- GitHub Pages' observed 600-second cache TTL is not controlled by the
  workflow. If ten minutes is unacceptable, put a purgeable CDN in front of
  Pages before the first urgent incident, not during it.
- Pruning the current pool does not shrink `gh-pages` history. If the branch
  becomes large, rebuilding it as an orphan is a separate, planned maintenance
  operation; preserve the current signed repositories before rewriting it.
- Canary storage is still permanent in GitHub history and Releases. Publish it
  when there is something worth exercising, and require a successful canary
  before stable.
