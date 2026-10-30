# nix-substitute-release

Publish signed Nix binary substitutes as GitHub Release assets, without a separate cache server.

This repository provides two composite GitHub Actions:

- `organization/nix-substitute-release@v1`: sign one built store output, export its NAR and narinfo, and upload a workflow artifact.
- `organization/nix-substitute-release/publish@v1`: download that artifact and attach it to an existing GitHub Release. Optionally publish a prepared release flake to a branch.

## Build

Use a Linux runner with Nix (`nix-command` and `flakes` enabled), `jq`, and `zstd` installed. Build the package before calling the action:

```yaml
- run: nix build .#my-package

- uses: organization/nix-substitute-release@v1
  with:
    private-key: ${{ secrets.NIX_CACHE_PRIVATE_KEY }}
    public-key: ${{ vars.NIX_CACHE_PUBLIC_KEY }}
```

Generate a signing key once, and save the secret/public values in the repository's Actions secrets/variables respectively:

```sh
nix key generate-secret --key-name my-project.example-1 > cache-secret.key
nix key convert-secret-to-public < cache-secret.key
```

The action verifies the output's signature before exporting it. The signature name is derived from `public-key`; no project-specific key name is hard-coded.

### Build inputs

| Input | Default | Description |
| --- | --- | --- |
| `private-key` | Required | Secret Nix signing key. |
| `public-key` | Required | Matching public key, including its name. |
| `store-path` | `result` | One built store path or symlink. |
| `cache-directory` | `cache` | Export directory; use a fresh directory for each export. |
| `artifact-name` | `nix-cache` | Uploaded workflow artifact name. |

Outputs: `cache-directory` (absolute path) and `store-path` (resolved store path).

The artifact contains `<store-hash>.nar.zst`, `<store-hash>.narinfo`, and `nix-cache-info`. Asset URLs in the narinfo are relative, so the release download URL works as a binary cache.

Only the requested output is exported, not its dependency closure. Dependencies must be available from the consumer's other substituters or built locally. For multiple systems, use distinct artifact names and call the publish action for each artifact. Outputs using the same store directory can share a release; the common `nix-cache-info` asset is replaced on each upload.

## Publish

Run publication in a job that depends on the build job. It needs `contents: write` and the GitHub CLI (`gh`, preinstalled on GitHub-hosted Ubuntu runners). Nix is not required in this job.

```yaml
permissions:
  contents: write

steps:
  - uses: actions/checkout@v7

  - name: Create draft release
    env:
      GH_TOKEN: ${{ github.token }}
      TAG: ${{ github.ref_name }}
    run: gh release create "$TAG" --draft --generate-notes

  - uses: organization/nix-substitute-release/publish@v1
    with:
      tag: ${{ github.ref_name }}

  - name: Publish release
    env:
      GH_TOKEN: ${{ github.token }}
      TAG: ${{ github.ref_name }}
    run: gh release edit "$TAG" --draft=false
```

Create the release in the caller so it can include other platform binaries, release notes, and prerelease settings. Cache uploads replace existing assets of the same name (`gh release upload --clobber`). The action does not create or finalize the release.

### Publish inputs

| Input | Default | Description |
| --- | --- | --- |
| `tag` | Required | Existing release tag. |
| `token` | `${{ github.token }}` | Token with contents write permission for uploading assets and publishing the flake branch. |
| `repository` | `${{ github.repository }}` | Repository containing the release and flake branch, in `owner/repo` form. |
| `artifact-name` | `nix-cache` | Cache artifact from the current workflow run. |
| `flake-directory` | Empty (disabled) | Prepared flake directory to publish, without a `.git` directory. |
| `flake-branch` | `flakes` | Branch to publish the flake to. |

### Release flake branch

Prepare a self-contained flake directory in the caller. For a split build/publish workflow, upload it as a separate artifact during the build, then download it before publication:

```yaml
- uses: actions/download-artifact@v8
  with:
    name: nix-flake
    path: flakes

- uses: organization/nix-substitute-release/publish@v1
  with:
    tag: ${{ github.ref_name }}
    flake-directory: flakes
```

Flake preparation is project-specific: include the flake, lock file, package/module expressions, and any evaluation-time metadata. If it fetches source code, pin the source revision and hash before building. Build from this prepared flake so consumers evaluate the same derivation that produced the cached output.

Publication uses the `repository` and `token` inputs for both release uploads and flake branch publication. It makes a commit containing exactly the prepared directory, preserving the previous branch tip as its parent. The branch is created if absent. Pushes are fast-forward only. Serialize release jobs in the caller to avoid concurrent publications:

```yaml
concurrency:
  group: release
  cancel-in-progress: false
```

## Consume

```nix
nix.settings = {
  substituters = [ "https://github.com/ORGANIZATION/REPOSITORY/releases/latest/download" ];
  trusted-public-keys = [ "my-project.example-1:PUBLIC_KEY" ];
};
```

For a specific release, use `https://github.com/ORGANIZATION/REPOSITORY/releases/download/v1.2.3`. `latest` follows GitHub's latest stable release; prereleases should use an explicit tag URL.

If publishing a release flake branch, consumers can use `github:ORGANIZATION/REPOSITORY/flakes`. Overrides of the flake's inputs can change the output store path and cause a cache miss.
