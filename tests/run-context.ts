import { ethers } from "hardhat"

import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers"
import { AccountFacet, ControlFacet, DiamondCutFacet, DiamondLoupeFacet, FakeOracle, FakeStablecoin, ForceActionsFacet, PartyAFacet, PartyBFacet, ViewFacet } from "../types"

export class RunContext {
	accountFacet!: AccountFacet
	diamondCutFacet!: DiamondCutFacet
	diamondLoupeFacet!: DiamondLoupeFacet
	partyAFacet!: PartyAFacet
	partyBFacet!: PartyBFacet
	viewFacet!: ViewFacet
	controlFacet!: ControlFacet
	forceActionsFacet!: ForceActionsFacet
	signers!: {
		admin: SignerWithAddress
		user: SignerWithAddress
		user2: SignerWithAddress
		feeCollector: SignerWithAddress
		partyB1: SignerWithAddress
		partyB2: SignerWithAddress
		others: SignerWithAddress[]
	}
	diamond!: string
	collateral!: FakeStablecoin
	oracle!:FakeOracle
}

export async function createRunContext(diamond: string, collateral: string, oracle: string): Promise<RunContext> {
	let context = new RunContext()

	const signers: SignerWithAddress[] = await ethers.getSigners()
	context.signers = {
		admin: signers[0],
		user: signers[1],
		user2: signers[2],
		feeCollector: signers[3],
		partyB1: signers[4],
		partyB2: signers[5],
		others: [signers[6], signers[7]],
	}

	context.diamond = diamond
	context.collateral = await ethers.getContractAt("FakeStablecoin", collateral)
	context.oracle = await ethers.getContractAt("FakeOracle", oracle)
	context.accountFacet = await ethers.getContractAt("AccountFacet", diamond)
	context.diamondCutFacet = await ethers.getContractAt("DiamondCutFacet", diamond)
	context.diamondLoupeFacet = await ethers.getContractAt("DiamondLoupeFacet", diamond)
	context.partyAFacet = await ethers.getContractAt("PartyAFacet", diamond)
	context.partyBFacet = await ethers.getContractAt("PartyBFacet", diamond)
	context.viewFacet = await ethers.getContractAt("ViewFacet", diamond)
	context.controlFacet = await ethers.getContractAt("ControlFacet", diamond)
	context.forceActionsFacet = await ethers.getContractAt("ForceActionsFacet", diamond)

	return context
}
