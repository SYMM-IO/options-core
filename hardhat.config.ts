import "@nomicfoundation/hardhat-chai-matchers"
import "@nomicfoundation/hardhat-toolbox"
import "@openzeppelin/hardhat-upgrades"
import { config as dotenvConfig } from "dotenv"
import type { HardhatUserConfig } from "hardhat/config"
import "solidity-docgen"
import "solidity-coverage"

import "./tasks"
import { resolve } from "path"

const dotenvConfigPath: string = process.env.DOTENV_CONFIG_PATH || "./.env"
dotenvConfig({ path: resolve(__dirname, dotenvConfigPath) })

const privateKey: string | undefined = process.env.PRIVATE_KEY || "0xec81e00837948239d5927bcb2b785675552bc92f1d2607ee91c540ddb56d6796" // Dummy private key

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
		polygon: {
			url: "https://polygon-rpc.com",
			accounts: [privateKey],
		},
		base: {
			url: "https://mainnet.base.org",
			accounts: [privateKey],
		},
	},
	etherscan: {
		apiKey: {
			base: process.env.BASE_API_KEY || "",
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
