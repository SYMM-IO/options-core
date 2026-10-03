import { BigNumberish } from "ethers"
import { ethers } from "hardhat"

export async function getLatestBlockTime(): Promise<number> {
	return ethers.provider.getBlock("latest").then(block => block?.timestamp ?? 0)
}

export async function moveTime(futureInSec: number) {
	const newBlock = (await getLatestBlockTime()) + futureInSec
	await ethers.provider.send("evm_setNextBlockTimestamp", [newBlock])
}
