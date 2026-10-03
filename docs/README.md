# Options Core documentation

Open [the documentation site](./index.html), or serve it locally with `npm run docs`. The static HTML reader is shared with `perps-core`. It supports chapter search, page outlines, light and dark themes, code controls, and diagrams.

## Reading paths

Start with [architecture](./architecture.md) and [open intents](./flows/open-intents.md) for the trade lifecycle. Integrators can look up selectors in [facets](./reference/facets.md), then check [events](./reference/events.md) and [errors](./reference/errors.md). Reviewers should read [security](./security.md) alongside the relevant flow. Operators should use [deployment and operations](./deployment-and-operations.md) and [roles and pauses](./reference/roles-and-pauses.md).

## Chapters

| Area         | Chapters                                                                                                                                                                                                                                                                    |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Development  | [Development standards](./development-standards.md), [testing](./testing.md), [deployment and operations](./deployment-and-operations.md)                                                                                                                                   |
| Architecture | [Architecture](./architecture.md), [security](./security.md)                                                                                                                                                                                                                |
| Flows        | [Account balances](./flows/account-balances.md), [open intents](./flows/open-intents.md), [close and settlement](./flows/close-and-settlement.md), [instant actions](./flows/instant-actions.md), [liquidation and force actions](./flows/liquidation-and-force-actions.md) |
| Concepts     | [Glossary](./concepts/glossary.md), [margin modes](./concepts/margin-modes.md), [fee model](./concepts/fee-model.md), [oracle and signatures](./concepts/oracle-and-signatures.md), [scheduled release](./concepts/scheduled-release.md)                                    |
| Reference    | [Facets](./reference/facets.md), [events](./reference/events.md), [errors](./reference/errors.md), [types and storage](./reference/types-and-storage.md), [roles and pauses](./reference/roles-and-pauses.md)                                                               |

## Maintaining the site

Edit the Markdown chapters, build them with `npm run docs:build`, and validate the result with `npm run docs:check`. The generated HTML, catalog, and chapter manifest are committed, allowing readers to open the site without building it. Keep documentation changes with the contract changes they describe.

Research under `docs/research/` contains proposed designs and references. It is separate from the current protocol chapters.
