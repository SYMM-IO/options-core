import "@nomicfoundation/hardhat-chai-matchers"
import "@nomicfoundation/hardhat-toolbox"
import "@openzeppelin/hardhat-upgrades"
import { config as dotenvConfig } from "dotenv"
import type { HardhatUserConfig } from "hardhat/config"
import "solidity-docgen"

import "./tasks"
import { resolve } from "path"

const dotenvConfigPath: string = process.env.DOTENV_CONFIG_PATH || "./.env"
dotenvConfig({ path: resolve(__dirname, dotenvConfigPath) })

const privateKey: string | undefined = process.env.PRIVATE_KEY
if (!privateKey) throw new Error("Please set your PRIVATE_KEY in .env file")

const config: HardhatUserConfig = {
	defaultNetwork: "hardhat",
	gasReporter: {
		currency: "USD",
		enabled: true,
		excludeContracts: [],
		src: "./contracts",
	},
	networks: {
		hardhat: {
			allowUnlimitedContractSize: false,
		},
	},
	paths: {
		artifacts: "./artifacts",
		cache: "./cache",
		sources: "./contracts",
		tests: "./tests",
	},
	solidity: {
		version: "0.8.19",
		settings: {
			metadata: {
				// Not including the metadata hash
				// https://github.com/paulrberg/hardhat-template/issues/31
				bytecodeHash: "none",
			},
			// Disable the optimizer when debugging
			// https://hardhat.org/hardhat-network/#solidity-optimizer-support
			optimizer: {
				enabled: true,
				runs: 200,
			},
			viaIR: true,
		},
	},
	typechain: {
		outDir: "types",
		target: "ethers-v6",
	},
	mocha: {
		timeout: 100000000,
	},
}

export default config
