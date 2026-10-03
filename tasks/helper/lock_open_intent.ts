import type { HardhatRuntimeEnvironment } from "hardhat/types/hre"
import { loadAddresses } from "../../scripts/utils/file.js"

export default async function ({ intentid }: { intentid: string }, hre: HardhatRuntimeEnvironment) {
	const { ethers } = await hre.network.getOrCreate()
	const [admin] = await ethers.getSigners()
	const partyBOpenFacet = (await ethers.getContractAt("PartyBOpenFacet", String(loadAddresses().symmioAddress))).connect(admin)
	const tx = await partyBOpenFacet.lockOpenIntent(BigInt(intentid))
	console.log("Transaction sent:", tx.hash)
	await tx.wait()
	console.log("Transaction confirmed.")
}
