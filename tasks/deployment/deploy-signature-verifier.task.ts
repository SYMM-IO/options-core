import { task, types } from "hardhat/config"

task("deploy:SignatureVerifier", "Deploys the SignatureVerifier contract").setAction(async ({}, { ethers }) => {
	console.log("Running deploy:SignatureVerifier")

	const verifierFactory = await ethers.getContractFactory("SignatureVerifier")
	const verifier = await verifierFactory.deploy()
	await verifier.waitForDeployment()

	await verifier.deploymentTransaction()!.wait()
	return verifier
})
