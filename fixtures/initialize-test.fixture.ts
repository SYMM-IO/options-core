import { ethers, run } from "hardhat"
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers"
import { Diamond } from "../src/types"

export class RunContext {
	signers!: {
		admin?: SignerWithAddress
		user?: SignerWithAddress
		user2?: SignerWithAddress
	}
	diamond!: Diamond
}

export async function initializeTestFixture(): Promise<RunContext> {
	// TODO :::
	
	let context = new RunContext()
	const signers: SignerWithAddress[] = await ethers.getSigners()
	context.signers = {
		admin: signers[0],
		user: signers[1],
		user2: signers[2],
	}

	context.diamond = await run("deploy:diamond")

	return context
}
