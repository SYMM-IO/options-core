import { ethers } from "hardhat"

async function main() {
	let symmioAddress = ""
	let contract = await ethers.getContractAt("ViewFacet", symmioAddress)
	console.log(await contract.balanceOf("", ""))
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
	console.error(error)
	process.exitCode = 1
})
