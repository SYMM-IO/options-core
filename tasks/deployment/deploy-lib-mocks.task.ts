import { task, types } from "hardhat/config"

task("deploy:mocks", "Deploys the Mock contract")
	.addParam("logData", "Write the deployed addresses to a data file", true, types.boolean)
	.setAction(async ({ logData }, { ethers }) => {
		const FacetNames = ["CloseIntentOpsMock"]

		const mocks: Map<string, string> = new Map<string, string>()

		console.log("Deploying Mock: ", FacetNames)
		for (const facetName of FacetNames) {
			const FacetFactory = await ethers.getContractFactory(facetName)
			const facet = await FacetFactory.deploy()
			await facet.waitForDeployment()
			mocks.set(facetName, await facet.getAddress())
			console.log(`${facetName} deployed: ${await facet.getAddress()}`)
		}

		return mocks
	})
