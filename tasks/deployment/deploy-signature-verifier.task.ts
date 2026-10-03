import type { HardhatRuntimeEnvironment } from "hardhat/types/hre"
import { deploySignatureVerifier } from "./deploy-lib.js"

export default async function (_: Record<string, unknown>, hre: HardhatRuntimeEnvironment) {
	const { ethers } = await hre.network.getOrCreate()
	return deploySignatureVerifier(ethers)
}
