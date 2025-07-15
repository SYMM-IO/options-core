import { task } from "hardhat/config"
import { loadAddresses } from "../../scripts/utils/file"
import { HardhatRuntimeEnvironment } from "hardhat/types"

task("fill-open-intent", "Calls fillOpenIntent on the contract")
	.addParam("intentid", "ID of the intentId")
	.addParam("quantity", "Quantity of the quantity")
	.addParam("price", "Price of the price")
	.setAction(async (args, hre: HardhatRuntimeEnvironment) => {
		const { ethers } = hre
		const admin = (await ethers.getSigners())[0]
		const symmioAddress = loadAddresses().symmioAddress

		const partyBOpenFacet = (await ethers.getContractAt("PartyBOpenFacet", String(symmioAddress))).connect(admin)
		const { intentid, quantity, price } = args

		const tx = await partyBOpenFacet.fillOpenIntent(BigInt(intentid), BigInt(quantity), BigInt(price))
		console.log("Transaction sent:", tx.hash)
		await tx.wait()
		console.log("Transaction confirmed.")
	})
