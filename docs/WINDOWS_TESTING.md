# Windows release acceptance

Use the `windows-preview-RUN_ID` artifact from the **Windows packaging check**
workflow. It contains the normal Papyrus app, an installer, a ZIP, `SHA256SUMS`,
and `BUILD-INFO.json` identifying the exact source commit and public API/sync
endpoints. The preview retains the manifest version and may have the same version
as an existing release. Identify test results by commit, not just version.
This is an unsigned test build, not a published release or an automatic update.
The separate `windows-package-validation` artifact contains automated test reports.

Download and extract the artifact. Compare the installer and ZIP hashes with
`SHA256SUMS`, using PowerShell:

```powershell
Get-FileHash .\papyrus-*-windows-x64-setup.exe -Algorithm SHA256
Get-FileHash .\papyrus-*-windows-x64.zip -Algorithm SHA256
```

Record the source commit, Windows version, display scaling, whether WebView2 was
already present, and the result of each check below. Use a disposable Windows
account or VM for clean-install and uninstall checks. Back up valuable local-only
books before testing an upgrade with your usual account.

## Setup and appearance

- Install as a normal user. Confirm the destination is under your user profile.
- Check the Papyrus welcome/completion artwork and header logo at 100%, 150%,
  and 200% display scaling. Text and images should remain readable and proportional.
- Leave **Create a desktop shortcut** unchecked and confirm no desktop shortcut
  appears. Re-run setup with it checked and launch Papyrus from the new shortcut.
- Launch from Start and confirm the window title is **Papyrus**, with the Papyrus
  icon in the title bar/taskbar. Inspect the executable's file description too.
- On a clean VM without WebView2, confirm setup installs the bundled runtime and
  the reader opens. With WebView2 already installed, confirm setup retains it.
  Do not remove the shared runtime from your everyday machine to perform this check.

## Upgrade and data retention

- Install the currently published installer from GitHub in the test account.
  Import an EPUB and PDF, change settings, and save a reading position. Sign in
  if testing credential retention, and keep a guest book in the guest library.
- Close Papyrus and install the preview over it without first uninstalling.
  Verify books, covers, reading positions, settings, and sign-in survive.
- Confirm guest, signed-in, and custom-server libraries remain isolated.
- Uninstall and confirm the app and its shortcuts disappear. Reinstall the
  preview and confirm the saved library and settings remain available.

## Reading, authentication, and ZIP

- Open EPUB and PDF books, turn pages, resize the reader, change fonts, and reopen
  the books to confirm saved positions. Try filenames containing spaces and Unicode.
- Import through the file picker and drag-and-drop. Restart without a network
  connection and confirm local books remain readable.
- Test password login, Google login through the browser, return to Papyrus, and
  sign-out. Reconnect and check sync with another device, including reading progress.
- Close the installed app. Extract the whole Windows ZIP into a new directory
  containing spaces, then launch `papyrus.exe` and repeat the basic reading checks.
  WebView2 must already be installed for the ZIP. ZIP and installer builds share
  the same user-data location, so run only one copy at a time.

Report failures with the commit, the failing step, expected/actual behavior, and
a screenshot where useful. For setup failures, capture a log by running the
installer with `/LOG="C:\path\to\papyrus-setup.log"`. Review logs for personal
paths before sharing. A passing CI run does not replace these interactive checks.
