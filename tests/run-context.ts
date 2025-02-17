import { ethers } from "hardhat"

import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers"
import { AccountFacet, ControlFacet, DiamondCutFacet, DiamondLoupeFacet, FakeStablecoin, ForceActionsFacet, PartyAFacet, ViewFacet } from "../types"

export class RunContext {
	accountFacet!: AccountFacet
	diamondCutFacet!: DiamondCutFacet
	diamondLoupeFacet!: DiamondLoupeFacet
	partyAFacet!: PartyAFacet
	viewFacet!: ViewFacet
	controlFacet!: ControlFacet
	forceActionsFacet!: ForceActionsFacet
	signers!: {
		admin: SignerWithAddress
		user: SignerWithAddress
		user2: SignerWithAddress
		liquidator: SignerWithAddress
		feeCollector: SignerWithAddress
		others: SignerWithAddress[]
	}
	diamond!: string
	collateral!: FakeStablecoin
}

export async function createRunContext(
	diamond: string,
	collateral: string,
): Promise<RunContext> {
	let context = new RunContext()

	const signers: SignerWithAddress[] = await ethers.getSigners()
	context.signers = {
		admin: signers[0],
		user: signers[1],
		user2: signers[2],
		liquidator: signers[3],
		feeCollector: signers[4],
		others: [signers[5], signers[6]],
	}

	context.diamond = diamond
	context.collateral = await ethers.getContractAt("FakeStablecoin", collateral)
	context.accountFacet = await ethers.getContractAt("AccountFacet", diamond)
	context.diamondCutFacet = await ethers.getContractAt("DiamondCutFacet", diamond)
	context.diamondLoupeFacet = await ethers.getContractAt("DiamondLoupeFacet", diamond)
	context.partyAFacet = await ethers.getContractAt("PartyAFacet", diamond)
	context.viewFacet = await ethers.getContractAt("ViewFacet", diamond)
	context.controlFacet = await ethers.getContractAt("ControlFacet", diamond)
	context.forceActionsFacet = await ethers.getContractAt("ForceActionsFacet", diamond)

	return context
}
