# Agent notes (homeops)

## GitHub auth (multi-account)

This repo may be worked on from environments where multiple `gh` accounts exist (work + personal).

- Do **not** use `gh auth switch` in automation; it mutates global state and agents forget.
- Prefer a per-shell token:
  - Copy `env.example` to `.env.local` and set `GITHUB_USER`
  - Run `source scripts/setup-github-auth.sh` to export `GH_TOKEN` (and `GITHUB_TOKEN` for compatibility)

If `git push` over HTTPS uses the wrong credentials, push with an explicit header:
- `git -c http.extraheader="AUTHORIZATION: basic <base64(x-access-token:GH_TOKEN)>" push`

