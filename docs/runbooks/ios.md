# The iOS build

ADR-0001 (`docs/decisions/0001-engine-and-language.md`) promises one project that
exports both the browser build and a native iOS app. This runbook is the second
half: how a build is produced, installed on a phone before any paid account
exists, and what changes when the account arrives.

## What exists today

- `app/export_presets.cfg` — one `iOS` preset, `application/export_project_only=true`.
- `infra/export_ios.py` — checks the host, the templates and the preset; exports
  the Xcode project; builds it with signing disabled; packages the ipa.
- `codemagic.yaml` — the`ios-unsigned` workflow, one macOS instance.
- `codemagic.yaml` is read by Codemagic only; GitHub Actions and the batch gate
  do not touch it.

## One-time Codemagic setup (a person does this, not the repository)

1. Sign in to Codemagic with the GitHub account that owns the repository.
2. **Add application** → pick `liberalluz/lethebar` → choose **codemagic.yaml**
   as the configuration source.
3. Team and billing: the free tier includes a limited number of macOS minutes;
   the first build may wait in a queue.
4. Start the `ios-unsigned` workflow. The artifact is
   `build/ios/Lethebar-unsigned.ipa`.

## Install it on a phone without a paid account

1. Download the artifact from Codemagic.
2. On Windows or macOS install **Sideloadly** and connect the iPhone by cable.
3. Drag the `.ipa` into Sideloadly, enter the Apple ID, start.
4. On the phone: **Settings → General → VPN & Device Management → Developer App**
   → trust the certificate.
5. The app runs for **7 days**. After that, sign and install again; nothing in
   the app is lost, saves live in the app's own `user://`.

A free Apple ID can only sign for its own devices: this path is for testing by
the owner, not for handing builds to other people.

## What the build can do

- The built-in `duel` pack is playable; saves and memory live in `user://`.
- Installing another pack works through the in-app dialog (address + digest),
  because the iOS file picker cannot see a phone's Downloads. The digest is the
  `sha256` from the package's release.
- `OS.get_locale()` supplies the language; `zh_CN` and `en_*` map to the two
  shipped catalogues.

## When the paid account arrives

Three changes, all outside this repository:

1. In Codemagic, add the App Store Connect integration (API key) and a
   distribution certificate; the workflow then signs instead of passing
   `CODE_SIGNING_ALLOWED=NO`.
2. In App Store Connect: create the app record (bundle id
   `com.liberalluz.lethebar`, SKU, privacy policy URL, screenshots, age rating,
   export compliance).
3. Replace `application/app_store_team_id="TEAMID"` with the real team id.
   TestFlight becomes available for internal testers first; external testers
   need Beta App Review. The App Store release is a separate App Review.

## Device checklist

- [ ] Cold start reaches the landing screen in under ten seconds.
- [ ] A Chinese phone shows Chinese; the switch changes it and it survives a restart.
- [ ] Start `duel`, act once, save, quit, resume — the run continues.
- [ ] Install a pack from a URL and its digest; the sheet appears above the keyboard.
- [ ] Rotate the phone; the layout survives.
- [ ] Send the app to the background mid-run and return.
