import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers"
import { expect, use } from "chai"
import { initializeTestFixture } from "../initialize-test.fixture"
import { PartyA } from "../models/partyA.model"
import { RunContext } from "../run-context"
import { IntentStatus, TradeSide } from "../option-enums"
import { openIntentRequestBuilder } from "../models/builders/send-open-intent.builder"
import { PartyB } from "../models/partyB.model"
import { ethers, network } from "hardhat"
import { e } from "../../utils/e"
import { AbiCoder, encodeBytes32String, InterfaceAbi, ZeroAddress, AddressLike, toUtf8Bytes } from "ethers"
import { bigint, int } from "hardhat/internal/core/params/argumentTypes"
import { config } from "dotenv"
import { OpenIntentStruct, OpenIntentStructOutput, SymbolStruct } from "../../types/contracts/interfaces/ISymmio"

import { MarginType } from "../option-enums"
import { getLatestBlockTime } from "../../utils/time"
import { InstantLayer, MultiAccount } from "../../types"

import * as diamond from "../../artifacts/contracts/Diamond.sol/Diamond.json"
// import * as partyAOpenIntent from "../artifacts/contracts/facets/PartyAOpen/PartyAOpenFacet.sol/PartyAOpenFacet.json"
// import * as partyBOpenIntent from "../artifacts/contracts/facets/PartyBOpen/PartyBOpenFacet.sol/PartyBOpenFacet.json"
import { trace } from "console"
import { hexZeroPad, zeroPad } from "@ethersproject/bytes"

export function shouldBehaveLikeMultiAccount(): void {
	let context: RunContext, partyA1: PartyA, partyA2: PartyA, partyB1: PartyB, partyB2: PartyB
	let openIntentCallData: string, lockIntentCallData: string, fillIntentCallData: string
	let saltOpen: string, saltLock: string, saltFill: string
	let accounts: MultiAccount.AccountStruct[]

	let ops: InstantLayer.OperationStruct[]
	let signedOps: InstantLayer.SignedOperationStruct[]
	let ABI: InterfaceAbi

	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)
		partyA1 = new PartyA(context, context.signers.partyA1)
		partyA2 = new PartyA(context, context.signers.partyA2)
		partyB1 = new PartyB(context, context.signers.partyB1)
		partyB2 = new PartyB(context, context.signers.partyB2)

		await partyA1.setBalances(context.collateral, e(100000), e(100000))
		await partyA1.setBalances(context.collateralNL, e(100000), e(100000)) // as Fee token
		await partyA2.setBalances(context.collateral, e(100000), e(100000))
		const { instantLayer, collateralNL, partyAOpenFacet, partyBOpenFacet } = context

		await context.controlFacet.setPartyBConfig(context.signers.partyB1, {
			isActive: true,
			lossCoverage: 0,
			oracleId: 1,
		})

		await context.controlFacet.setUnbindingCooldown(120)

		saltOpen = ethers.keccak256(ethers.toUtf8Bytes("saltOpen"))
		saltLock = ethers.keccak256(ethers.toUtf8Bytes("saltLock"))
		saltFill = ethers.keccak256(ethers.toUtf8Bytes("saltFill"))

		const latestBlock = await getLatestBlockTime()
		const deadline = latestBlock + 300

		const request = openIntentRequestBuilder()
			.partyBsWhiteList([partyB1.address])
			.affiliate(context.signers.affiliate1.address)
			.feeToken(await collateralNL.getAddress())
			.symbolId(1)
			.deadline(deadline)
			.expirationTimestamp(deadline)
			.exerciseFee({ cap: e(1), rate: "0" })
			.marginType(MarginType.ISOLATED)
			.tradeSide(TradeSide.BUY)
			.strikePrice(e(1))
			.build()


		openIntentCallData = partyAOpenFacet.interface.encodeFunctionData("sendOpenIntent", [
			request.partyBsWhiteList,
			request.symbolId,
			request.price,
			request.quantity,
			request.strikePrice,
			request.expirationTimestamp,
			request.mm,
			request.tradeSide,
			request.marginType,
			request.exerciseFee,
			request.deadline,
			request.feeToken,
			request.affiliate,
			request.userData,
		])
		lockIntentCallData = partyBOpenFacet.interface.encodeFunctionData("lockOpenIntent", [1])
		fillIntentCallData = partyBOpenFacet.interface.encodeFunctionData("fillOpenIntent", [1, e(100), 7])

		await expect(context.multiAccount.connect(partyA1.getSigner).addAccount("testAccount")).not.to.reverted
		accounts = await context.multiAccount.getAccounts(partyA1.address, 0, 100)
	})

	describe("Add Account Function", async function () {
		it("should Add Account for msg sender", async () => {
			await expect(context.multiAccount.connect(partyA2.getSigner).addAccount("testAccount2")).not.to.reverted
			let accountsLocal: MultiAccount.AccountStruct[] = await context.multiAccount.getAccounts(partyA2.address, 0, 100)

			expect(accountsLocal.length).to.be.equal(1)
			expect(accountsLocal[0].name).to.equal("testAccount2")
		})
	})

	describe("_call Function", async function () {
		let accounts: MultiAccount.AccountStruct[]
		beforeEach(async function () {
			await expect(context.multiAccount.connect(partyA1.getSigner).addAccount("testAccount")).not.to.reverted
			accounts = await context.multiAccount.getAccounts(partyA1.address, 0, 100)
		})

		it("should fail when not Expected msg sender", async () => {			
			await expect(context.multiAccount._call(accounts[0].account,["0x"])).to.revertedWithCustomError(context.multiAccount,"UnauthorizedAccess")
		})
	})
}
