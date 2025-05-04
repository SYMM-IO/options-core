import { task, types } from "hardhat/config"
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers"

task("deploy:stablecoin", "Deploys the FakeStablecoin")
	.addParam("name", "The token's name")
  	.addParam("symbol", "The token's symbol")
	.setAction(async ({name,symbol}, {ethers, run}) => {
		console.log("Running deploy:stablecoin")

	const signers: SignerWithAddress[] = await ethers.getSigners()
	const owner: SignerWithAddress = signers[0]
	console.log("using address: " + JSON.stringify(owner))

		const StablecoinFactory = await ethers.getContractFactory("FakeStablecoin")
		const stablecoin = await StablecoinFactory.connect(owner).deploy(name, symbol)
		await stablecoin.waitForDeployment()

	await stablecoin.deploymentTransaction()!.wait()
	console.log("FakeStablecoin deployed:", await stablecoin.getAddress())

	return stablecoin
})
