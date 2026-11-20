# Share link: upload a video and copy its link (PF, 2026-11-20)

Branch `pf/share-link` (from `pf/view-mode`). PF wants a **Share link** button in Omacut that turns the finished video into a link on PF's OmaShare server (a self-hosted Cap Web), the same way Loom does.

## The tool it calls

`omashare` (installed at `/usr/bin/omashare`, from github.com/riopierrefrancois/omashare-cli) already does the upload. Omacut only runs it and shows progress:

```
omashare --json --name "TITLE" /abs/path/video.mp4
```

stdout is one JSON object per line:

```json
{"event": "progress", "stage": "preparing", "percent": 37.5}
{"event": "progress", "stage": "uploading", "percent": 81.2}
{"event": "done", "id": "kxed3ytz2z7ht2t", "link": "https://share.example.com/s/kxed3ytz2z7ht2t"}
{"event": "error", "error": "Not signed in. Run: omashare login"}
```

The exit code is 0 or 1, and it copies the link to the clipboard itself (via wl-copy). Never run `omashare login` from the app: it opens a browser. Say what to do instead.

## Rules

- Async `QProcess` only, never `waitForFinished`.
- Don't reuse `m_busy`: sharing must not block loading or editing, and must not make quit say "Exporting".
- Kill a running share in `~Backend`.
- Every visible string is in `src/i18n/en.json` (the test enforces it).
- New backend properties and signals must also be on the QML test stub `ShortcutBackend` (tests/omacut_tests.cpp), or QML warnings fail the tests.
- One commit per task, with an imperative message. Tick the box in the same commit.
- `bin/test` passes before each commit.
- Install nothing. Stop at the gate and report.

## Tasks

### S1: backend
- [x] `Backend` gets:
  - Q_PROPERTYs `sharing` (bool), `shareStage` (QString: `""`, `"preparing"`, `"uploading"`), `sharePercent` (double 0–100) and `lastExport` (QString, the absolute path of the last successful export; set where `exportDone` is emitted).
  - signals `shareDone(QString link)` and `shareFailed(QString message)`
  - `Q_INVOKABLE void share(const QString &path, const QString &title)`
- [x] `share()`:
  - Resolve the tool with `QStandardPaths::findExecutable("omashare")`. The env var `OMACUT_OMASHARE` overrides it, which is the test seam.
  - Missing tool: `shareFailed(tr("Install omashare to share links."))`.
  - Ignore the call while a share is running.
  - Start the process with `--json --name <title> <path>` as separate arguments.
  - Parse stdout lines with `QJsonDocument`, using the line-buffer pattern of `exportClips` (backend.cpp, the `readyReadStandardOutput` handler).
  - On `done`, emit `shareDone(link)`. On `error`, or a non-zero exit with no `done`, emit `shareFailed` with the tool's message. If there is none, use `tr("Couldn't share the video.")`.
  - When the message says "Not signed in", replace it with `tr("Sign in to OmaShare first: run omashare login in a terminal.")`.
- [x] Unit tests with a fake `omashare` shell script (via `OMACUT_OMASHARE`) that prints progress, then done, and another that prints an error. Check the properties and signals, and that `--name` and the path arrive as separate arguments.

### S2: the button
- [x] Add a **share** icon to `IconButton`'s `onPaint`: a simple link (two rounded chain links), drawn like the existing icons.
- [x] **Edit mode:** a Share link button right after Export.
  - Enabled when `backend.lastExport` is set, `!win.unexported` and `!backend.sharing`.
  - Shares `backend.lastExport`.
  - Tooltip: "Share link (L)". When disabled because nothing is exported: "Export first, then share".
- [x] **View mode:** a Share link button next to the pencil.
  - It shares the open file (local path of `backend.source`) when `!win.unexported`.
  - Title: the file name without its extension.
- [x] Shortcut **L** (`Qt.ApplicationShortcut`, same enabled guards as the other bare-letter shortcuts, plus the button's own rule).
  - Add it to the help overlay lists for both modes and to the README Hotkeys section.
- [x] Progress and results:
  - While sharing, the status line shows "Preparing link… 40%" or "Uploading… 80%".
  - `shareDone` → `win.showNotice(qsTr("Link copied: %1").arg(link))`.
  - `shareFailed` → `win.showNotice(message)`.
  - Export progress wins the status line if both run.
- [x] QML tests: the button's enabled rules in both modes, L triggers `share` with the right path, and the notice text on done and failed. Use the stub.

### S3: release
- [ ] `pkg/PKGBUILD`: `pkgver=0.7.2.pf2`, and add `optdepends=('omashare: Share link button')`.
- [ ] Build the package (`cd pkg && makepkg -f`). Don't install it.

## Gate
`bin/test` green, package built. Write the report to the path the orchestrator gives: commits, test output, anything this plan got wrong. Stop.
