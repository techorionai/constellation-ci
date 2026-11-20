# Use the shared workflows

This repository has GitHub reusable workflows for the Constellation repositories. A project repository calls them with a short workflow file.

## Workflows

| Workflow | Use for |
| -------- | ------- |
| `go.yml` | Go modules. Format check, `go vet`, `golangci-lint`, unit tests, integration tests, and `govulncheck`. |
| `typespec.yml` | TypeSpec projects. Compile, and a check that the generated files are current. |
| `frontend.yml` | Frontend projects. Install, lint, test, and build. |
| `compose.yml` | Repositories with Docker Compose files. YAML lint, shell lint, workflow lint, static checks, and a smoke test. |
| `image.yml` | Container images of Go services. A Buildx build for `linux/amd64` and `linux/arm64`, and a push to GHCR on a version tag. |

Each workflow has the permission `contents: read`. The exception is the `build` job of `image.yml`, which also has `packages: write`. No workflow accepts secrets. No workflow has outputs.

## Go workflow

| Input | Default | Use |
| ----- | ------- | --- |
| `working-directory` | `.` | Folder of the Go module. |
| `go-version-file` | `go.mod` | Go version source, relative to `working-directory`. |
| `unit-command` | `go test -race ./...` | Unit test command. |
| `integration-command` | empty | Integration test command. If the input is empty, the `integration` job is skipped. |
| `integration-timeout-minutes` | `30` | Time limit of the `integration` job in minutes. |

Each job has a time limit (`timeout-minutes`): `lint` 15, `unit` 30, `integration` 30 (set by the input), and `vulncheck` 15. The TypeSpec workflow has 15 and the frontend workflow has 30. The Compose workflow has `lint` 15, `unit` 15, and `integration` 30 (set by the input). The image workflow has `build` 45.

Jobs:

1. `lint`: `gofmt -l .` must give no files. Then `go vet ./...`, then `golangci-lint run`.
2. `unit`: the `unit-command`.
3. `integration`: the `integration-command`.
4. `vulncheck`: `govulncheck ./...`.

Integration tests can use testcontainers. The runner has Docker. Put the integration tests behind a build tag, for example `//go:build integration`. Then the unit command does not run them.

### Lint configuration

The `lint` job uses the shared `golangci-lint` configuration of `config/golangci.yml`. If the project has its own configuration file, the job uses that file and not the shared configuration. The job looks for the file in the `working-directory` and then in each parent folder, up to the root of the checked-out repository. The first file that the job finds is used. The accepted names are `.golangci.yml`, `.golangci.yaml`, `.golangci.toml`, and `.golangci.json`. Thus a file at the repository root is used when the `working-directory` is a subfolder.

### Inputs are fixed strings

The jobs run the inputs `unit-command`, `integration-command`, and `generate-command` as shell commands. Thus the value of an input must be a fixed string in the caller workflow. Never put event data in an input, for example `${{ github.head_ref }}` or `${{ github.event.pull_request.title }}`. A person who controls that data can run commands in the job. `scripts/check-repo.sh` rejects the word `github` (in any letter case) inside any `${{ }}` expression in the `with:` values of a job. This includes flow style values and expressions that continue on the next line.

### Caller example

```yaml
name: CI
on:
  pull_request:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  go:
    uses: techorionai/constellation-ci/.github/workflows/go.yml@v0.1.0
    with:
      integration-command: go test -tags=integration ./...
```

## TypeSpec workflow

| Input | Default | Use |
| ----- | ------- | --- |
| `working-directory` | `.` | Folder of the TypeSpec project. |
| `node-version` | `26` | Node.js version. |
| `generate-command` | `npx tsp compile .` | Command that makes the generated files. |

The job runs `npm ci` and the `generate-command`. Then it runs `git status --porcelain` in the `working-directory`, and the `node_modules/` folder is excluded. The job fails if the output is not empty. Thus commit the generated files, and keep them current.

```yaml
name: CI
on:
  pull_request:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  typespec:
    uses: techorionai/constellation-ci/.github/workflows/typespec.yml@v0.1.0
    with:
      working-directory: contracts
```

## Frontend workflow

| Input | Default | Use |
| ----- | ------- | --- |
| `working-directory` | `.` | Folder of the frontend. |
| `node-version` | `26` | Node.js version. |

Rules for the frontend folder:

- It has exactly one lock file. `package-lock.json` gives npm. `pnpm-lock.yaml` gives pnpm. No lock file, or two lock files, make the job fail.
- `package.json` has the scripts `lint`, `test`, and `build`. If one script is missing, the job fails before the install.
- For pnpm, `package.json` has a `packageManager` field, for example `"packageManager": "pnpm@12.18.0"`. The job uses corepack to get this version. If the field is missing, the job fails.

```yaml
name: CI
on:
  pull_request:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  frontend:
    uses: techorionai/constellation-ci/.github/workflows/frontend.yml@v0.1.0
    with:
      working-directory: web
```

## Compose workflow

For repositories that hold Docker Compose files.

| Input | Default | Use |
| ----- | ------- | --- |
| `working-directory` | `.` | Folder of the Compose project. |
| `unit-command` | `bash scripts/check-compose.sh` | Static checks of the Compose files. |
| `integration-command` | empty | Smoke test command. If the input is empty, the `integration` job is skipped. |
| `integration-timeout-minutes` | `30` | Time limit of the `integration` job in minutes. |

Jobs:

1. `lint`: installs `yamllint` 1.38.0, `actionlint` 1.7.12, and `shellcheck` 0.11.0. Then it runs `yamllint --strict .` and `shellcheck` on each `*.sh` file in the `working-directory`. Then it runs `actionlint` at the repository root.
2. `unit`: prints `docker compose version`, then runs the `unit-command`.
3. `integration`: runs the `integration-command`.

The `lint` and `unit` jobs have a time limit of 15 minutes. The `integration` job has the time limit of the input. The workflow does not start containers. The scripts of the caller start them.

Rules for the caller:

- `yamllint` uses the config file of the caller (`.yamllint`, `.yamllint.yml`, or `.yamllint.yaml`). Without a config file, `yamllint` uses its default rules, and these rules fail on `on:` in workflow files. Thus add a config file. To keep a bad YAML fixture in the repository, add its path to the `ignore:` key of the config file.
- The `Shell lint` step has no input to exclude a path. Do not commit a `*.sh` file that `shellcheck` rejects. A test that needs a bad shell file makes the file at run time in a temporary folder outside the repository.
- The `Workflow lint` step runs `actionlint` at the repository root. `actionlint` runs `shellcheck` 0.11.0 on each `run:` script of all workflows of the caller. Thus a `run:` script that `shellcheck` 0.11.0 rejects makes the step fail.
- Call the scripts through `bash`, for example `bash scripts/smoke-test.sh`. Then the Git file mode of a script has no effect.
- Each command input is a fixed string. See "Inputs are fixed strings".
- A Compose file with relative bind mounts (for example `./config:/cfg:ro`) does not work under `act` with a Docker Desktop host. The daemon of the host resolves the mount path, and this path is not the path in the `act` container. For a local test, run the integration command directly on the host. On a GitHub runner, bind mounts work.

```yaml
name: CI
on:
  pull_request:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  compose:
    uses: techorionai/constellation-ci/.github/workflows/compose.yml@v0.2.0
    with:
      integration-command: bash scripts/smoke-test.sh
```

## Image workflow

For Go services that ship as a container image. The workflow builds the image with Docker Buildx for the platforms of the input. On a version tag, it pushes the image to GitHub Container Registry (GHCR) with an SBOM and a provenance attestation.

| Input | Default | Use |
| ----- | ------- | --- |
| `context` | `.` | Build context folder. |
| `dockerfile` | empty | Path of the Dockerfile, relative to the repository root. If the input is empty, the workflow uses `<context>/Dockerfile`. |
| `image-name` | empty | Image name without the registry. If the input is empty, the workflow uses the repository name in lowercase, for example `techorionai/constellation-identity`. |
| `platforms` | `linux/amd64,linux/arm64` | Buildx platforms. |
| `push` | `false` | Push the image to `ghcr.io`. |

Rules:

- Push rule: the workflow pushes only if the `push` input is true and `github.ref` starts with `refs/tags/v`. On a pull request or a branch, the workflow builds and does not push, also if the caller sets `push: true`. The `Resolve` step writes the result `push=true` or `push=false` to the job summary.
- Permission rule: the caller job must have the permissions `contents: read` and `packages: write`. A called workflow cannot get more permissions than its caller. Do not give `id-token: write`. The workflow does not need it. `scripts/check-repo.sh` allows `packages: write` only in the `build` job of `image.yml` and in a caller job of `image.yml`. Any other write permission fails the check.
- Tag rule: the tags are `<version>`, `<major>.<minor>`, and `sha-<short sha>`. The workflow never makes a `latest` tag. The step `No latest tag` fails if a tag ends in `:latest`.
- Dockerfile cross-compile rule: the `arm64` build runs under QEMU and is slow. Thus compile Go on the build platform. Use `FROM --platform=$BUILDPLATFORM` for the build stage and set `GOARCH=$TARGETARCH`. Then QEMU runs only the final stage.
- GHCR visibility: a new GHCR package is private. After the first push, the owner sets the package to public in the package settings on GitHub.
- The workflow does not scan the image and does not sign it. It makes no GitHub artifact attestation.

```yaml
name: Image
on:
  pull_request:
  push:
    tags: ["v*"]
permissions:
  contents: read
jobs:
  image:
    uses: techorionai/constellation-ci/.github/workflows/image.yml@v0.3.0
    permissions:
      contents: read
      packages: write
    with:
      push: true
```

## Update to a new version

The caller uses an exact version tag. To update, change the `@vX.Y.Z` ref in each `uses: techorionai/constellation-ci/.github/workflows/<file>@vX.Y.Z` line of `.github/workflows/*.yml`. Use the `bump-dependency` skill of the planner repository. The tags and releases of this repository cannot be moved or deleted.

## Rulesets for a public repository

A free GitHub account cannot use branch protection on a private repository. For a public project repository, add a branch ruleset on the base branch that:

- requires the status check of the caller workflow,
- blocks force pushes and deletion,
- has no bypass actors.

## Run the tests of this repository

The tests need Docker, `actionlint`, and the `gh-act` extension of `gh`.

```sh
actionlint
scripts/check-repo.sh .
scripts/self-test.sh testdata/callers
gh act pull_request -W .github/workflows/self-test.yml --var SELF_TEST_LOCAL=true
```

`scripts/self-test.sh` runs each caller in a folder with `act`. A caller must fail at the job and step that its `# expect-fail: <job>/<step>` header names. The `.actrc` file sets the runner image and runs one job at a time, because parallel jobs of `act` share one tool cache.
