import "@nomicfoundation/hardhat-chai-matchers"
import "@nomicfoundation/hardhat-toolbox"
import "@openzeppelin/hardhat-upgrades"
import type {HardhatUserConfig} from "hardhat/config"
import 'solidity-docgen'

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
			// forking: {
			//   url: "",
			// },
			allowUnlimitedContractSize: false,
		},
	},
	paths: {
		artifacts: "./artifacts",
		cache: "./cache",
		sources: "./contracts",
		tests: "./test",
	},
	solidity: {
		version: "0.8.27",
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
		outDir: "src/types",
		target: "ethers-v6",
	},
	mocha: {
		timeout: 100000000,
	}
}

export default config