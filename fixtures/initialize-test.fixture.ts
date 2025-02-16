import { ethers, run } from "hardhat"
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers"
import { Diamond, FakeStablecoin } from "../types"

export class RunContext {
	signers!: {
		admin?: SignerWithAddress
		user?: SignerWithAddress
		user2?: SignerWithAddress
	}
	diamond!: Diamond
	stableCoin!: FakeStablecoin
}

export async function initializeTestFixture(): Promise<RunContext> {
	
	let context = new RunContext()
	const signers: SignerWithAddress[] = await ethers.getSigners()
	context.signers = {
		admin: signers[0],
		user: signers[1],
		user2: signers[2],
	}

	// TODO ::: deploy and call initialize methods here


	context.diamond = await run("deploy:diamond")
	context.stableCoin = await run("deploy:stablecoin")

	// TODO ::: set collateral, etc.

	return context
}
