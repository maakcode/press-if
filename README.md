# Press If

A macOS app that turns a natural-language request into a reviewed, scheduled sequence of app actions. Meta Muse Spark plans the steps, selects visible controls, and checks the result against screen evidence.

Insert button images anywhere in a request, for example: “In 5 seconds, open a music app, click [play image], wait 20 seconds, then click [stop image].”

## Build

Requires macOS 14 or later and Xcode with Swift 6. There are no third-party package dependencies.

```bash
bash scripts/test.sh
PRESS_IF_CODESIGN_IDENTITY=- bash scripts/build.sh
open "dist/Press If.app"
```

Quit Press If before rebuilding. The command above creates an ad hoc development build; rebuilding may invalidate macOS privacy permissions. For a stable development signature, set `PRESS_IF_CODESIGN_IDENTITY` to your signing certificate. When omitted, the script selects a certificate only if exactly one Apple Development identity is available. These scripts do not produce a notarized public release.

## Use

1. In **Settings**, enter your own Meta API key and grant **Accessibility** permission.
2. Write a request. Add reference images with paste, drag and drop, or **Add image**.
3. Review the app, actions, schedule, and completion criteria in **Preview**.
4. Select **Schedule** or **Run**. Check the final status and evidence in the task history.

Image matching requires **Screen Recording** permission and **Send window images to Meta**. Window image transmission is off by default for new installations. A request can contain up to eight reference images.

Supported actions include app activation, clicking, text input, numeric controls, shortcuts, and bounded waits. Schedules support immediate, relative, dated, and daily execution. `Control + Option + Space` opens quick input; `Control + Option + Escape` stops tasks.

## Data and execution

- The API key is stored in macOS Keychain when saved in Settings. Development processes can explicitly supply `MODEL_API_KEY` or `META_API_KEY`. The app does not search for `.env` files.
- Requests, attached reference images, installed app names and IDs, and target app screen elements are sent to `https://api.meta.ai`. Window images are sent only when enabled. Secure accessibility fields are skipped; image content is not automatically redacted. Use requests and app windows whose contents you intend to send.
- Requests, reference images, plans, and execution history are stored in `~/Library/Application Support/PressIfMeta/tasks.json` with file mode `0600` and directory mode `0700`. Captured window images are kept in memory.
- Keep the Mac awake, unlocked, and Press If running. Restarting, sleeping, or locking pauses tasks. Tasks more than 30 seconds late are skipped. Scheduling determines when execution starts; model calls and app navigation add latency.
- The executor checks the foreground app and target again before clicking. Missing or ambiguous image targets and windows stop execution. Stopping cannot undo inputs already delivered.
- Automation can change data in other apps and is not a security sandbox. Review each plan. A model's completion judgment can be wrong; inspect the result before relying on it.

## Checks

`bash scripts/test.sh` runs offline tests for scheduling, plan validation, image matching, window selection, and local storage. Test images are generated in code.

Optional integration checks call the real model API using your credits. They use synthetic observations and do not control other apps:

```bash
.build/debug/press-if-check --live --env-file /path/to/.env
```

The explicit environment file must use `MODEL_API_KEY` or `META_API_KEY`. To generate the image-matching demo, build the project and run `bash scripts/build-fixture.sh`. Its generated images can be checked with `press-if-check --image-live --fixtures verification/image-fixture` and the same explicit credentials.

Build outputs, credentials, screenshots, and local verification reports are excluded from Git. Passing automated checks does not establish reliable operation in every app.

## Source layout

- `Sources/PressIfCore`: plans, schedules, API client, validation, storage.
- `Sources/PressIfImaging`: image import and template matching.
- `Sources/PressIfMeta`: SwiftUI app, permissions, accessibility, execution.
- `Sources/PressIfCheck`, `Sources/PressIfImageFixture`: optional integration tools.
- `Tests`, `scripts`, `Resources`: offline tests, build tools, app metadata.
