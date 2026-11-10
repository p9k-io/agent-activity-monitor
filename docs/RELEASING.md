# Releasing

A release is built, signed and notarized on the maintainer's Mac. CI builds and tests; it holds no secret and publishes nothing.

## Once

1. A `Developer ID Application` certificate in the login keychain.
2. An App Store Connect API key in `~/.appstoreconnect/private_keys/AuthKey_<key id>.p8`.
3. The identifier of the key's issuer, from [Users and Access → Integrations](https://appstoreconnect.apple.com/access/integrations/api), in a file:

   ```sh
   mkdir -p ~/.config/agent-activity-monitor
   pbpaste > ~/.config/agent-activity-monitor/asc-issuer-id
   ```

4. The key that signs updates. Sparkle keeps the private half in the login keychain and prints the public half, which goes into `App/Info.plist` as `SUPublicEDKey`:

   ```sh
   scripts/sparkle-tool.sh generate_keys
   ```

   The private half exists only in that keychain. Export a copy with `scripts/sparkle-tool.sh generate_keys -x <file>` and keep it somewhere safe: without it, the copies people have installed can never be updated.

## Every release

1. Merging pull requests into `main` keeps the release pull request up to date. It carries the version and the changelog. Do not merge it yet.
2. Check out the release pull request's branch and build what it describes:

   ```sh
   scripts/release.sh
   ```

   The script archives the app, adds the command line tool, signs everything from the inside out, has Apple notarize the app and the disk image, staples both, and writes the update feed. It ends with the path of the disk image and its checksum. `--no-notarize` stops short of Apple, for a dry run.
3. Open the disk image on a clean account or another Mac and try the app.
4. Merge the release pull request. That creates the tag and the GitHub Release.
5. Attach `dist/Agent-Activity-Monitor-<version>.dmg` and `dist/appcast.xml` to the release.
6. Put the version and the checksum into `Casks/agent-activity-monitor.rb` in [p9k-io/homebrew-tap](https://github.com/p9k-io/homebrew-tap).

Steps 4 to 6 are the ones other people see. Everything before them can be repeated.

## Checking a build by hand

```sh
codesign --verify --deep --strict --verbose=2 "dist/Agent Activity Monitor.app"
spctl --assess --verbose=2 "dist/Agent Activity Monitor.app"
xcrun stapler validate dist/Agent-Activity-Monitor-*.dmg
```
