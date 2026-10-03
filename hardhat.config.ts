import { resolve } from "node:path"

import hardhatToolboxMochaEthers from "@nomicfoundation/hardhat-toolbox-mocha-ethers"
import hardhatUpgrades from "@openzeppelin/hardhat-upgrades"
import { config as dotenvConfig } from "dotenv"
import { configVariable, defineConfig } from "hardhat/config"

import { tasks } from "./tasks/index.js"

dotenvConfig({ path: resolve(import.meta.dirname, process.env.DOTENV_CONFIG_PATH || ".env"), quiet: true })

export default defineConfig({
	plugins: [hardhatToolboxMochaEthers, hardhatUpgrades],
	tasks,
	solidity: {
		version: "0.8.25",
		settings: {
			evmVersion: "cancun",
			metadata: {
				// Not including the metadata hash
				// https://github.com/paulrberg/hardhat-template/issues/31
				bytecodeHash: "none",
			},
			optimizer: {
				enabled: true,
				runs: 200,
			},
			viaIR: true,
		},
	},
	networks: {
		// The in-process chain. Hardhat 3 names it "default"; there is no defaultNetwork key.
		default: {
			type: "edr-simulated",
			chainType: "l1",
			// allowUnlimitedContractSize is left unset on purpose: it defaults to false, and leaving it unset lets
			// `hardhat test --coverage` lift the limit for instrumented bytecode. Setting it explicitly disables that.
		},
		polygon: {
			type: "http",
			chainType: "generic",
			url: "https://polygon-rpc.com",
			accounts: [configVariable("PRIVATE_KEY")],
		},
		base: {
			type: "http",
			chainType: "op",
			url: "https://mainnet.base.org",
			accounts: [configVariable("PRIVATE_KEY")],
		},
	},
	verify: {
		etherscan: {
			apiKey: configVariable("ETHERSCAN_API_KEY"),
		},
	},
	paths: {
		tests: {
			mocha: "tests",
		},
	},
	test: {
		mocha: {
			timeout: 100000000,
		},
	},
	typechain: {
		outDir: "types",
	},
})
