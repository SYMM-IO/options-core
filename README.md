# Options Core

Options Core is a Hardhat/Solidity repository for the SYMM options protocol. The core contract is an EIP-2535 Diamond made of account, control, intent, trade, settlement, force-action, liquidation, and view facets.

Documentation starts in [docs/README.md](./docs/README.md).

Useful commands:

```shell
npm install
npx hardhat compile
npx hardhat test
npx hardhat deploy:diamond --network hardhat --log-data true
```
