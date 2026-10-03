import { verifyContract } from "@nomicfoundation/hardhat-verify/verify"
import hre, { network } from "hardhat"

const { ethers } = await network.getOrCreate()

async function main() {
	const facetName = "PartyBOpenFacet"
	const facet = await (await ethers.getContractFactory(facetName)).deploy()
	await facet.waitForDeployment()
	console.log(`${facetName} deployed: ${await facet.getAddress()}`)
	await verifyContract({ address: await facet.getAddress(), constructorArgs: [] }, hre)
}

main().catch(error => {
	console.error(error)
	process.exitCode = 1
})
