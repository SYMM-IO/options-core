import { task } from "hardhat/config"
import { loadAddresses } from "../../scripts/utils/file"
import { HardhatRuntimeEnvironment } from "hardhat/types"

task("lock-open-intent", "Calls fillOpenIntent on the contract")
	.addParam("intentid", "ID of the intentId")
	.setAction(async (args, hre: HardhatRuntimeEnvironment) => {
		const { ethers } = hre
		const admin = (await ethers.getSigners())[0]
		const symmioAddress = loadAddresses().symmioAddress

		const partyBOpenFacet = (await ethers.getContractAt("PartyBOpenFacet", String(symmioAddress))).connect(admin)
		const { intentid } = args

		const tx = await partyBOpenFacet.lockOpenIntent(BigInt(intentid))
		console.log("Transaction sent:", tx.hash)
		await tx.wait()
		console.log("Transaction confirmed.")
	})
