import type { HardhatRuntimeEnvironment } from "hardhat/types/hre"
import { loadAddresses } from "../../scripts/utils/file.js"
import { requireArg } from "../utils/args.js"

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
	// Validate before connecting, so a missing option never reaches a live network or a keystore prompt.
	// solverfeeopen, solverfeeclose and whitelist were optional under Hardhat 2 and keep their defaults.
	const symbolId = BigInt(requireArg(args.symbolid, "symbolid"))
	const price = BigInt(requireArg(args.price, "price"))
	const quantity = BigInt(requireArg(args.quantity, "quantity"))
	const strikePrice = BigInt(requireArg(args.strikeprice, "strikeprice"))
	const expiration = BigInt(requireArg(args.expiration, "expiration"))
	const mm = BigInt(requireArg(args.mm, "mm"))
	const tradeSide = Number(requireArg(args.tradeside, "tradeside"))
	const marginType = Number(requireArg(args.margintype, "margintype"))
	const exerciseFee = {
		rate: BigInt(requireArg(args.exercisefeerate, "exercisefeerate")),
		cap: BigInt(requireArg(args.exercisefeecap, "exercisefeecap")),
	}
	const solverFee = { openFee: BigInt(args.solverfeeopen), closeFee: BigInt(args.solverfeeclose) }
	const deadline = BigInt(requireArg(args.deadline, "deadline"))
	const feeToken = requireArg(args.feetoken, "feetoken")
	const affiliate = requireArg(args.affiliate, "affiliate")
	const userData = requireArg(args.userdata, "userdata")
	const partyBsWhiteList = args.whitelist ? args.whitelist.split(",").map(addr => addr.trim()) : []

	const { ethers } = await hre.network.getOrCreate()
	const [admin] = await ethers.getSigners()
	const partyAOpenFacet = (await ethers.getContractAt("PartyAOpenFacet", String(loadAddresses().symmioAddress))).connect(admin)

	const tx = await partyAOpenFacet[
		"sendOpenIntent(address[],uint256,uint256,uint256,uint256,uint256,uint256,uint8,uint8,(uint256,uint256),(uint256,uint256),uint256,address,address,bytes)"
	](
		partyBsWhiteList,
		symbolId,
		price,
		quantity,
		strikePrice,
		expiration,
		mm,
		tradeSide,
		marginType,
		exerciseFee,
		solverFee,
		deadline,
		feeToken,
		affiliate,
		userData,
	)
	console.log("Transaction sent:", tx.hash)
	await tx.wait()
	console.log("Transaction confirmed.")
}
