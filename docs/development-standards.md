# Development standards

Options Core follows the development conventions in the sibling `perps-core` checkout and uses Hardhat 3, Ethers v6, and OpenZeppelin 5. Contracts compile with Solidity 0.8.25, targeting Cancun, with 200 optimizer runs and `viaIR`.

## Contract structure

Facets expose selectors and apply access, pause, and reentrancy modifiers. Shared business logic belongs in the domain libraries under `contracts/libraries/core/`; model operations belong under `contracts/libraries/models/`. Each storage domain has a `Layout` struct and a `layout()` accessor using its existing Diamond storage slot.

Preserve storage slots, field order, field types, and enum ordinals when upgrading a deployed Diamond. Treat changes to selectors, custom errors, emitted events, or signed payloads as integration changes and update their reference pages alongside the code.

Use named imports and remove unused imports. Keep the existing SYMM Core Business Source License headers. Use the OpenZeppelin 5 implementations already installed for ERC-20 transfers, upgradeable helpers, and signature verification. Diamond-specific guards and storage remain in the existing Options Core libraries.

## Formatting and lint

Prettier formats Solidity with tabs and a 150-character line width. TypeScript uses tabs with a tab width of two and no semicolons. `npm run lint` runs Solidity lint and the TypeScript compiler without emitting files.

The Solidity rules match `perps-core/.solhint.json`. They use the recommended ruleset with project exceptions for assembly, compiler pragmas, NatSpec, and several gas suggestions. Unused imports and `selfdestruct` are errors; advisory warnings do not fail lint.

## Build and test commands

| Command                       | Purpose                                                                      |
| ----------------------------- | ---------------------------------------------------------------------------- |
| `npm run compile`             | Compile, generate TypeChain types, and check deployed contract sizes.        |
| `npm run check:contract-size` | Check existing compiled artifacts and write `artifacts/contract-sizes.json`. |
| `npm run lint`                | Solidity and TypeScript checks.                                              |
| `npm test`                    | Run Mocha with `TEST_MODE=UNIT_TEST`.                                        |
| `npm run coverage`            | Run the same test mode with Hardhat coverage.                                |
| `npm run check:release`       | Compile, lint, run tests, and validate docs.                                 |

The contract size check uses the `perps-core` budgets and checks deployable artifacts under `artifacts/contracts`. It warns when deployed bytecode exceeds 22,528 bytes and fails above 23,552 bytes. That leaves 1,024 bytes below the 24,576-byte EIP-170 limit.

Local builds and tests need no private key. Live deployments and verification resolve Hardhat config variables only when needed. Use environment variables, an ignored `.env`, or `npx hardhat keystore set PRIVATE_KEY` and `npx hardhat keystore set ETHERSCAN_API_KEY`. `.env.example` lists the supported names.

## Git hooks and CI

`npm install` initializes Husky through the `prepare` script. The pre-commit hook formats and re-stages only fully staged paths, skipping files that also have unstaged edits. It compiles and checks contract sizes when Solidity is staged, and checks documentation when docs are staged.

Run the full test suite before submitting contract changes.

GitLab CI uses Node 24 and the committed npm lockfile. It checks formatting, compilation, lint, generated docs, and tests. The GitLab secret-detection template remains enabled.

## Documentation

Open `docs/index.html` in a browser. The site works from a local HTTP server or directly from the HTML files, with the same fonts, reader layout, theme controls, page outline, code controls, and diagram viewer as `perps-core`.

Edit the Markdown chapters and run `npm run docs:build`; do not edit generated chapters directly. One chapter list determines the HTML chapters, catalog, and navigation manifest. `npm run docs:check` rejects stale output, missing local links, duplicate IDs, and broken heading anchors.

Run `npm run docs` for a local server, or `npm run docs -- --no-open --port 4174` to choose a port without launching a browser. Update the relevant chapter in the same change as contract behavior. Research and design proposals under `docs/research/` are separate from the current protocol reference.
