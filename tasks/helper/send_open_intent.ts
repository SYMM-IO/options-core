import type { HardhatRuntimeEnvironment } from "hardhat/types/hre"
import { loadAddresses } from "../../scripts/utils/file.js"

interface SendOpenIntentArgs {
	symbolid: string
	price: string
	quantity: string
	strikeprice: string
	expiration: string
	mm: string
	tradeside: string
	margintype: string
	exercisefeerate: string
	exercisefeecap: string
	solverfeeopen: string
	solverfeeclose: string
	deadline: string
	feetoken: string
	affiliate: string
	userdata: string
	whitelist: string
}

export default async function (args: SendOpenIntentArgs, hre: HardhatRuntimeEnvironment) {
	const { ethers } = await hre.network.getOrCreate()
	const [admin] = await ethers.getSigners()
	const partyAOpenFacet = (await ethers.getContractAt("PartyAOpenFacet", String(loadAddresses().symmioAddress))).connect(admin)

	const partyBsWhiteList = args.whitelist ? args.whitelist.split(",").map(addr => addr.trim()) : []
	const tx = await partyAOpenFacet.sendOpenIntent(
		partyBsWhiteList,
		BigInt(args.symbolid),
		BigInt(args.price),
		BigInt(args.quantity),
		BigInt(args.strikeprice),
		BigInt(args.expiration),
		BigInt(args.mm),
		Number(args.tradeside),
		Number(args.margintype),
		{ rate: BigInt(args.exercisefeerate), cap: BigInt(args.exercisefeecap) },
		{ openFee: BigInt(args.solverfeeopen), closeFee: BigInt(args.solverfeeclose) },
		BigInt(args.deadline),
		args.feetoken,
		args.affiliate,
		args.userdata,
	)
	console.log("Transaction sent:", tx.hash)
	await tx.wait()
	console.log("Transaction confirmed.")
}
