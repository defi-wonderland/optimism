# Repository Guidelines

## Project Structure & Module Organization
Core Go services live under directories prefixed with `op-` (for example `op-node`, `op-batcher`, `op-proposer`), while shared libraries sit in `op-service`. Smart contracts and Solidity tooling are in `packages/contracts-bedrock`. Testing harnesses reside in `op-e2e` and `op-acceptance-tests`. Operational scripts and automation live in `ops/`, and documentation is consolidated under `docs/`.

## Build, Test, and Development Commands
Install and pin toolchains with `mise trust mise.toml` followed by `mise install`. Build all primary Go binaries and contracts via `make build`; use `make op-node` or `make op-proposer` for targeted builds. Run Solidity contract builds with `just build` inside `packages/contracts-bedrock`. Execute repo-wide Go unit tests with `go test ./...` from the desired module, and invoke `just test` within `packages/contracts-bedrock` for contract tests. `make lint-go` runs `golangci-lint` and checks `go.mod` hygiene.

## Coding Style & Naming Conventions
Go contributions must compile with `go1.x` from `mise` and stay `gofmt`-clean; prefer descriptive CamelCase for exported symbols and snake_case for file names. Solidity contracts follow 4-space indentation and rely on Foundry’s `forge fmt`; run `just lint-check` inside `packages/contracts-bedrock` before committing. Keep configuration and scripts in lowercase with hyphenated file names. Run `make lint-go` or the relevant Foundry formatters before opening a PR.

## Testing Guidelines
Unit test files mirror the target using `_test.go` for Go and `.t.sol` for Solidity. Group scenarios logically and avoid cross-package dependencies unless essential. Acceptance and E2E suites live in `op-e2e` and `op-acceptance-tests`; follow their READMEs for longer runs. Aim to cover new behaviors and include regression tests whenever fixing a bug. Prefer running smoke tests (`go test ./...` or `just test`) before pushing.

## Commit & Pull Request Guidelines
History shows Conventional Commit prefixes (`fix:`, `feat:`, `chore:`) for clarity—match that style and keep subjects under 72 characters. Reference related issues in the body when applicable. Target PRs at `develop` unless coordinating a release branch, and describe rationale, configuration changes, and test evidence. Include screenshots or logs when altering user-visible behavior.

## Security & Configuration Tips
Review `SECURITY.md` before reporting vulnerabilities; never post sensitive findings publicly. Keep secrets out of version control—use `.env` templates or the `ops/` scripts for local secrets management. Regenerate artifacts such as contract deployments through the provided scripts to maintain deterministic builds.
