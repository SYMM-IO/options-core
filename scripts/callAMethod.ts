import { ethers } from "hardhat"

async function main() {
	let symmioAddress = "0xF606cccF372683Cf7295726B20cf81552B5af6e1"
	let contract = await ethers.getContractAt("PartyBCloseFacet", symmioAddress)

	try {
		// console.log(await contract.lockOpenIntent(2))

		// console.log(await contract.fillOpenIntent(2, "10000000000000000000", "1000000000000000000", 0))

		console.log(await contract.fillCloseIntent(1, "10000000000000000000", "10000000000000000000"))
	} catch (error: any) {
		if (error.data) {
			try {
				const decodedError = contract.interface.parseError(error.data)!
				console.error(`Custom error: ${decodedError.name}`)
				console.error(decodedError.args)
			} catch (parseError) {
				console.error("Error parsing error data:", parseError)
				console.error("Original error data:", error)
			}
		} else {
			console.error("Unknown error:", error)
		}
	}
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
	console.error(error)
	process.exitCode = 1
})
