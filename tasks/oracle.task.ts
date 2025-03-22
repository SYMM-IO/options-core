import {task, types} from "hardhat/config"
import {SignerWithAddress} from "@nomicfoundation/hardhat-ethers/signers"

task("deploy:oracle", "Deploys the FakeOracle")
	.setAction(async ({}, {ethers, run}) => {
		console.log("Running deploy:oracle")

		const signers: SignerWithAddress[] = await ethers.getSigners()
		const owner: SignerWithAddress = signers[0]
		console.log("using address: " + JSON.stringify(owner))

		const OracleFactory = await ethers.getContractFactory("FakeOracle")
		const oracle = await OracleFactory.connect(owner).deploy()
		await oracle.waitForDeployment()

		await oracle.deploymentTransaction()!.wait()
		console.log("FakeOracle deployed:", await oracle.getAddress())

		return oracle
	})