import type { HardhatRuntimeEnvironment } from "hardhat/types/hre"
import { requireArg } from "../utils/args.js"
import { deployStablecoin } from "./deploy-lib.js"

export default async function ({ name, symbol }: { name: string; symbol: string }, hre: HardhatRuntimeEnvironment) {
	const { ethers } = await hre.network.getOrCreate()
	return deployStablecoin(ethers, requireArg(name, "name"), requireArg(symbol, "symbol"))
}
