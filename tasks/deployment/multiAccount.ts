import { task, types } from "hardhat/config"

task("deploy:multiAccount", "Deploys the SymmioPartyB")
	.addParam("symmioaddress", "The address of the Symmio contract")
	.addParam("admin", "The admin address")
	.addOptionalParam("logData", "Write the deployed addresses to a data file", true, types.boolean)
	.setAction(async ({ symmioaddress, admin, logData }, { ethers, upgrades, run }) => {
		console.log("Running deploy:symmioPartyB")

		const [deployer] = await ethers.getSigners()

		console.log("Deploying contracts with the account:", deployer.address)
		const SymmioPartyA = await ethers.getContractFactory("SymmioPartyA")

		// Deploy MultiAccount as upgradeable
		const SymmioPartyBFactory = await ethers.getContractFactory("MultiAccount")
		const symmioPartyB = await upgrades.deployProxy(SymmioPartyBFactory, [admin, symmioaddress, SymmioPartyA.bytecode], { initializer: "initialize" })
		await symmioPartyB.waitForDeployment()

		const addresses = {
			proxy: await symmioPartyB.getAddress(),
			admin: await upgrades.erc1967.getAdminAddress(await symmioPartyB.getAddress()),
			implementation: await upgrades.erc1967.getImplementationAddress(await symmioPartyB.getAddress()),
		}
		console.log("MultiAccount deployed to", addresses)

		return symmioPartyB
	})
