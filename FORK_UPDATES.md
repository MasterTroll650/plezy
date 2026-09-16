# Pleazy fork updates

This fork follows official Plezy releases only. It does not continuously merge
or rebase onto `upstream/main`.

- `upstream-release` points to the Plezy release used as the fork base.
- `main` contains the Pleazy-specific patch commits on top of that base.
- `origin` is `MasterTroll650/plezy`.
- `upstream` is `edde746/plezy`.

## Update to a new release

Wait until Plezy publishes a release tag, then run:

```powershell
.\update-from-upstream-release.ps1 -NewRelease 2.21.0
```

The script fetches only the requested release tag, rebases the commits between
`upstream-release` and `main` onto it, and advances `upstream-release` only after
a successful rebase.

If Git reports conflicts, resolve them and continue with:

```powershell
git add <resolved-files>
git rebase --continue
```

After validation, publish the updated branches:

```powershell
git push origin upstream-release
git push --force-with-lease origin main
```

Use `--force-with-lease`, never an unconditional force push, for `main`.
