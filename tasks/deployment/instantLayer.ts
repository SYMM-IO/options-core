import { task, types } from "hardhat/config"

task("deploy:InstantLayer", "Deploys the InstantLayer contract")
	.addParam("symmioaddress", "The address of the Symmio contract")
	.addParam("admin", "The admin address")
	.addOptionalParam("logData", "Write the deployed addresses to a data file", true, types.boolean)
	.setAction(async ({ symmioaddress, admin, logData }, { ethers, upgrades, run }) => {
		console.log("Running deploy:InstantLayer")

		const [deployer] = await ethers.getSigners()

		console.log("Deploying contracts with the account:", deployer.address)
		const InstantLayerFactory = await ethers.getContractFactory("InstantLayer")
		const instantLayer = await InstantLayerFactory.connect(deployer).deploy(symmioaddress, admin)
		await instantLayer.waitForDeployment()

		await instantLayer.deploymentTransaction()!.wait()
		console.log("InstantLayer deployed:", await instantLayer.getAddress())

		return instantLayer
	})
