# Release Procedure

## 1. Bump the version

Edit `cloudcut_exporter.rb` and update the `EXTENSION.version` string:

```ruby
EXTENSION.version = "X.Y.Z"
```

## 2. Build the RBZ

```bash
./build_rbz.sh
```

This outputs `build/cloudcut_exporter_vX.Y.Z.rbz`.

## 3. Commit and push

```bash
git add -A
git commit -m "vX.Y.Z: description of changes"
git push
```

## 4. Create a GitHub Release

```bash
gh release create vX.Y.Z build/cloudcut_exporter_vX.Y.Z.rbz \
  --target <branch> \
  --title "vX.Y.Z" \
  --notes "Description of changes."
```

The `.rbz` file must be attached as a release asset — the in-app updater (`updater.rb`) checks the latest GitHub Release for an `.rbz` asset and prompts users to install it.

## How the updater works

- On first use each session, the extension hits the GitHub Releases API for this repo
- If the latest release tag is newer than the installed version, the user is prompted to download and install
- Checks are throttled to once per hour
