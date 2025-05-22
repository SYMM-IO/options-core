import { ethers } from "hardhat"

export async function getCurrentLatestBlockTime(): Promise<number> {
	return ethers.provider.getBlock("latest").then(block => block?.timestamp ?? 0)
}
