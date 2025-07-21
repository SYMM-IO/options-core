import { ZeroAddress } from "ethers"
import { task, types } from "hardhat/config"

task("deploy:multiAccount", "Deploys the MultiAccount")
	.addParam("symmioaddress", "The address of the Symmio contract")
	.addParam("admin", "The admin address")
	.addParam("tradenftaddress", "The trade NFT address")
	.addOptionalParam("logData", "Write the deployed addresses to a data file", true, types.boolean)
	.setAction(async ({ symmioaddress, admin, tradenftaddress, logData }, { ethers, upgrades, run }) => {
		console.log("Running deploy:MultiAccount")

		const [deployer] = await ethers.getSigners()

		console.log("Deploying contracts with the account:", deployer.address)
		const SymmioPartyA = await ethers.getContractFactory("SymmioPartyA")

		// Deploy MultiAccount as upgradeable
		const symmioMultiAccountFactory = await ethers.getContractFactory("MultiAccount")
		const symmioMultiAccount = await upgrades.deployProxy(symmioMultiAccountFactory, [admin, symmioaddress, SymmioPartyA.bytecode, tradenftaddress], {
			initializer: "initialize",
		})
		await symmioMultiAccount.waitForDeployment()

		const addresses = {
			proxy: await symmioMultiAccount.getAddress(),
			admin: await upgrades.erc1967.getAdminAddress(await symmioMultiAccount.getAddress()),
			implementation: await upgrades.erc1967.getImplementationAddress(await symmioMultiAccount.getAddress()),
		}
		console.log("MultiAccount deployed to", addresses)

		return symmioMultiAccount
	})
