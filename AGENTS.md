# Agent notes (homeops)

## GitHub auth (multi-account)

This repo may be worked on from environments where multiple `gh` accounts exist (work + personal).

- Do **not** use `gh auth switch` in automation; it mutates global state and agents forget.
- Auth is handled via the zsh profile (dotfiles repo). Ensure the correct profile is loaded.

If `git push` over HTTPS uses the wrong credentials, push with an explicit header:
- `git -c http.extraheader="AUTHORIZATION: basic <base64(x-access-token:GH_TOKEN)>" push`
