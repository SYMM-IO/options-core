import { verifyContract } from "@nomicfoundation/hardhat-verify/verify"
import hre, { network } from "hardhat"
import { OPEN_INTENT_FUNDING_LIBRARY, OPEN_INTENT_FUNDING_LIBRARY_NAME } from "../common/constants.js"
import { deployOpenIntentFunding } from "../tasks/deployment/deploy-lib.js"
import { writeData } from "../tasks/utils/fs.js"

const { ethers } = await network.getOrCreate()

async function main() {
	const fundingLibrary = await deployOpenIntentFunding(ethers)
	const facetName = "PartyBOpenFillFacet"
	const libraries = { [OPEN_INTENT_FUNDING_LIBRARY_NAME]: fundingLibrary.address }
	const facet = await (await ethers.getContractFactory(facetName, { libraries })).deploy()
	await facet.waitForDeployment()
	const address = await facet.getAddress()
	writeData("facet-deployed.json", [fundingLibrary, { name: facetName, address, constructorArguments: [], libraries }])
	console.log(`${facetName} deployed: ${address}`)
	await verifyContract({ address: fundingLibrary.address, constructorArgs: [], contract: OPEN_INTENT_FUNDING_LIBRARY }, hre)
	await verifyContract({ address, constructorArgs: [], libraries }, hre)
}

main().catch(error => {
	console.error(error)
	process.exitCode = 1
})
