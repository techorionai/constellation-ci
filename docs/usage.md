# Use the shared workflows

This repository has GitHub reusable workflows for the Constellation repositories. A project repository calls them with a short workflow file.

## Workflows

| Workflow | Use for |
| -------- | ------- |
| `go.yml` | Go modules. Format check, `go vet`, `golangci-lint`, unit tests, integration tests, and `govulncheck`. |
| `typespec.yml` | TypeSpec projects. Compile, and a check that the generated files are current. |
| `frontend.yml` | Frontend projects. Install, lint, test, and build. |

Each workflow has the permission `contents: read`. No workflow accepts secrets. No workflow has outputs.

## Go workflow

| Input | Default | Use |
| ----- | ------- | --- |
| `working-directory` | `.` | Folder of the Go module. |
| `go-version-file` | `go.mod` | Go version source, relative to `working-directory`. |
| `unit-command` | `go test -race ./...` | Unit test command. |
| `integration-command` | empty | Integration test command. If the input is empty, the `integration` job is skipped. |
| `integration-timeout-minutes` | `30` | Time limit of the `integration` job in minutes. |

Each job has a time limit (`timeout-minutes`): `lint` 15, `unit` 30, `integration` 30 (set by the input), and `vulncheck` 15. The TypeSpec workflow has 15 and the frontend workflow has 30.

Jobs:

1. `lint`: `gofmt -l .` must give no files. Then `go vet ./...`, then `golangci-lint run`.
2. `unit`: the `unit-command`.
3. `integration`: the `integration-command`.
4. `vulncheck`: `govulncheck ./...`.

Integration tests can use testcontainers. The runner has Docker. Put the integration tests behind a build tag, for example `//go:build integration`. Then the unit command does not run them.

### Lint configuration

The `lint` job uses the shared `golangci-lint` configuration of `config/golangci.yml`. If the project has its own configuration file, the job uses that file and not the shared configuration. The job looks for the file in the `working-directory` and then in each parent folder, up to the root of the checked-out repository. The first file that the job finds is used. The accepted names are `.golangci.yml`, `.golangci.yaml`, `.golangci.toml`, and `.golangci.json`. Thus a file at the repository root is used when the `working-directory` is a subfolder.

### Inputs are fixed strings

The jobs run the inputs `unit-command`, `integration-command`, and `generate-command` as shell commands. Thus the value of an input must be a fixed string in the caller workflow. Never put event data in an input, for example `${{ github.head_ref }}` or `${{ github.event.pull_request.title }}`. A person who controls that data can run commands in the job. `scripts/check-repo.sh` rejects `${{ github.` in the `with:` values of a job.

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
