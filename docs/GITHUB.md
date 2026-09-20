# Push this project to GitHub

The repository now has an initial commit and an `origin` remote. For this update, use **Later updates** below; do not add the remote again. The first-time setup steps are retained for a fresh repository. A GitHub Release makes the app downloadable.

## 1. Create the empty repository

Sign in at https://github.com/new .

- Repository name: **mac-duo-private** (or your preferred name).
- Choose **Public** if anyone should download it; otherwise **Private**.
- Leave **Add a README**, **Add .gitignore**, and **Choose a license** unchecked. This project already has those files.
- Click **Create repository** and copy the HTTPS repository URL.

## 2. Commit and push

Open Terminal and paste:

```sh
cd '/Users/jiacai/Documents/ChatGPT/mac duo'
git status
swift test
./build.sh
./package.sh
git add .gitignore Package.swift Sources Tests Resources build.sh package.sh README.md PRIVACY.md LICENSE NOTICE docs
git diff --cached --stat
git commit -m "Add Mac Duo Private with automatic lid animation"
git remote add origin https://github.com/YOUR_USERNAME/mac-duo-private.git
git push -u origin main
```

Replace **YOUR_USERNAME** and the repository name with the URL you copied. The existing branch is already `main`; no branch rename or `git init` is needed. `build/`, `.build/`, and `dist/` are ignored intentionally.

If Git asks for your identity, run these first with your actual values, then retry the commit:

```sh
git config user.name "YOUR NAME"
git config user.email "YOUR GITHUB COMMIT EMAIL"
```

Use your GitHub-provided **noreply** email from GitHub Settings → Emails if you do not want to publish your personal email. Do not copy an invented noreply address.

For HTTPS authentication, use the credential/sign-in flow available on your Mac. If Terminal asks for a password, GitHub requires a personal access token with access to this repository, not your account password. Never put a token in the remote URL, source files, or chat. GitHub Desktop's **File → Add Local Repository** followed by **Publish repository** is an alternative if you prefer browser-based authentication; use that instead of creating a second repository.

If `origin` already exists because you followed these steps earlier, inspect `git remote -v` and use the existing correct URL. Do not blindly replace an unrelated remote.

## 3. Add the downloadable installer

After the push:

1. Open your repository on GitHub → **Releases → Draft a new release**.
2. Choose tag **v0.4.8** and create it on **main**.
3. Title: **Mac Duo Private 0.4.8**.
4. Explain that it requires a compatible Apple Silicon MacBook, macOS 14+, and Screen Recording permission; this build is not notarized.
5. Attach these files from the local `dist` folder:
   - **Mac-Duo-Private.dmg** — normal download for users.
   - **Mac-Duo-Private.zip** — alternative app download.
   - **SHA256SUMS.txt** — file integrity checksums.
   - **Mac-Duo-Private-Source.tar.gz** — optional source archive; upload it too if using the supplied checksum list unchanged.
6. Publish the release. Share its release-page URL so people can choose the DMG under Assets.

Keep LICENSE, NOTICE, and the Makito attribution: the renderer derives from Apache-2.0-licensed Mac Duo. Publishing your modified project does not make it an official Apple or upstream release.

## Later updates

```sh
cd '/Users/jiacai/Documents/ChatGPT/mac duo'
git add Sources Tests Resources docs README.md PRIVACY.md NOTICE Package.swift build.sh package.sh .gitignore
git diff --cached --stat
git commit -m "Add soft edge blur while preserving lid animation geometry"
git push
```

Increment the app version before rebuilding, then publish a new tag and release with fresh installer assets.

Official references: [Push an existing project](https://docs.github.com/en/migrations/importing-source-code/using-the-command-line-to-import-source-code/adding-locally-hosted-code-to-github), [create releases](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository).
