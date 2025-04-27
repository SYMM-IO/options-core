import { ethers } from "hardhat"

async function main() {
	let addr = "0xF606cccF372683Cf7295726B20cf81552B5af6e1"
	let facetAddr = "0xCb26f1ea5EA441E390C1B8ce4B4a1Da6cb495096"
	const diamondCutFacet = await ethers.getContractAt("DiamondCutFacet", addr)
	await diamondCutFacet.diamondCut(
		[
			{
				facetAddress: facetAddr,
				action: 1,
				functionSelectors: ["0x6148ca72"],
			},
		],
		ethers.ZeroAddress,
		"0x",
	)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
	console.error(error)
	process.exitCode = 1
})
