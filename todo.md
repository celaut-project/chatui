# TODO chatui

Improvements to the app's distribution and UI.

- [x] **Remove the PIN.** The user does not want it. Done in code (not compiled or tested here: no Flutter or Rust toolchain). Wallets unlock with the fingerprint or the screen lock of the phone; old wallets give their PIN one last time.
- [x] **Simplify the main Ergo wallet view to the minimum.** It shows only the ERG the wallet holds and the latest transactions, nothing else. Everything else goes inside a details section. Inside it the theme must always change, to show that we are in the Ergo part.
- [x] **Chat: fade the text at the top and bottom** where it reaches the header and the input.
- [x] **Chat: fix the long-press menu on a message.** Pressing a message selects its text instead of opening the dropdown menu. Fix it, and add "Select text" as one of the menu options.
- [x] **File-loading animation.** Replace the current rocket-taking-off animation with one that shows the rocket being raised on the launch pad (from horizontal to vertical). Use the same rocket as the current one if possible.
- [x] **Chat: on entering a chat, show the end** (the latest messages), not the start.
- [x] **Chat: show the time of each message** (timestamp).
- [x] **Service selection list: improve the UI.** It carries too much information now. Reason about how to reduce it.
