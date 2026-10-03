# Options Core

Options Core is a Hardhat/Solidity repository for the SYMM options protocol. The core contract is an EIP-2535 Diamond made of account, control, intent, trade, settlement, force-action, liquidation, and view facets.

Open [docs/index.html](./docs/index.html) for the documentation site, or run `npm run docs` to serve it locally. It uses the same static reader as `perps-core`.

Useful commands:

```shell
npm install
npm run compile
npm run lint
npm test
npm run docs:check
npx hardhat deploy:diamond
```

Compilation generates TypeChain types and enforces the contract size budget. Local compilation and tests need no credentials. Live networks read `PRIVATE_KEY`, and source verification reads `ETHERSCAN_API_KEY`. Both can come from the environment, an ignored `.env`, or the Hardhat keystore.

See [development standards](./docs/development-standards.md) for contract conventions, checks, and documentation maintenance.
