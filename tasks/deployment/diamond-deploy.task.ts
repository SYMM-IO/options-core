import type { HardhatRuntimeEnvironment } from "hardhat/types/hre"
import { deployDiamond } from "./deploy-lib.js"

export default async function ({ skipLog }: { skipLog: boolean }, hre: HardhatRuntimeEnvironment) {
	const { ethers } = await hre.network.getOrCreate()
	return deployDiamond(ethers, !skipLog)
}
