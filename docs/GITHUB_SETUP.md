# GitHub setup and local synchronization

**Canonical repository:** https://github.com/peter-dietrich/vector-divide

For a new local checkout, clone directly from GitHub:

```sh
mkdir -p ~/Documents/GitHub
cd ~/Documents/GitHub
git clone https://github.com/peter-dietrich/vector-divide.git
cd vector-divide
open VectorDivide.xcodeproj
```

For every subsequent update:

```sh
cd ~/Documents/GitHub/vector-divide
git pull --ff-only origin main
open VectorDivide.xcodeproj
```

## If you downloaded the original v0.1.0 Git bundle

The original portable bundle contained two local commits that are not ancestors of the initial GitHub commits. Do **not** run `git pull` with unrelated histories or force-push that bundle to GitHub: it would create an avoidable merge or overwrite the canonical repository.

If your existing `~/Documents/GitHub/vector-divide` directory was cloned from the bundle, and you have no local changes to preserve:

```sh
cd ~/Documents/GitHub
mv vector-divide vector-divide-bundle-backup
git clone https://github.com/peter-dietrich/vector-divide.git
cd vector-divide
open VectorDivide.xcodeproj
```

Retain the backup until you verify the GitHub checkout builds as expected. If you have uncommitted local edits, preserve and review them before replacing the checkout.

## Versioning

Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `VectorDivide.xcodeproj/project.pbxproj` when the visible version changes. Preserve the bundle identifier `io.vectordivide.game`.

Vector Divide is standalone. Build locally and use **ADD GAME** in Fun City to select its `.app` until a built-in launcher cabinet is implemented. Do not make unrelated changes to other games.
