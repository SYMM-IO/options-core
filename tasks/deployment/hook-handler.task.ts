import { task, types } from "hardhat/config"
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers"

task("deploy:hookHandler", "Deploys the Hook Handler").setAction(async ({}, { ethers, run }) => {
	console.log("Running deploy:HookHandler")

	const signers: SignerWithAddress[] = await ethers.getSigners()
	const owner: SignerWithAddress = signers[0]
	console.log("using address: " + JSON.stringify(owner))

	const hookHandlerFactory = await ethers.getContractFactory("MockHookHandler")
	const hookHandler = await hookHandlerFactory.connect(owner).deploy()
	await hookHandler.waitForDeployment()

	await hookHandler.deploymentTransaction()!.wait()
	console.log("HookHandler deployed:", await hookHandler.getAddress())

	return hookHandler
})
