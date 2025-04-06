import {task, types} from "hardhat/config"
import {SignerWithAddress} from "@nomicfoundation/hardhat-ethers/signers"

task("deploy:stablecoin", "Deploys the FakeStablecoin")
	.setAction(async ({}, {ethers, run}) => {
		console.log("Running deploy:stablecoin")

		const signers: SignerWithAddress[] = await ethers.getSigners()
		const owner: SignerWithAddress = signers[0]
		console.log("using address: " + JSON.stringify(owner))

		const StablecoinFactory = await ethers.getContractFactory("FakeStablecoin")
		const stablecoin = await StablecoinFactory.connect(owner).deploy()
		await stablecoin.waitForDeployment()

		await stablecoin.deploymentTransaction()!.wait()
		console.log("FakeStablecoin deployed:", await stablecoin.getAddress())

		return stablecoin
	})