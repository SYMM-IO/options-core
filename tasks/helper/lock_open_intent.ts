import type { HardhatRuntimeEnvironment } from "hardhat/types/hre"
import { loadAddresses } from "../../scripts/utils/file.js"
import { requireArg } from "../utils/args.js"

export default async function ({ intentid }: { intentid: string }, hre: HardhatRuntimeEnvironment) {
	// Validate before connecting, so a missing option never reaches a live network or a keystore prompt.
	const intentId = BigInt(requireArg(intentid, "intentid"))

	const { ethers } = await hre.network.getOrCreate()
	const [admin] = await ethers.getSigners()
	const partyBOpenFacet = (await ethers.getContractAt("PartyBOpenFacet", String(loadAddresses().symmioAddress))).connect(admin)
	const tx = await partyBOpenFacet.lockOpenIntent(intentId)
	console.log("Transaction sent:", tx.hash)
	await tx.wait()
	console.log("Transaction confirmed.")
}
