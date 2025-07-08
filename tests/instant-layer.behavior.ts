import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers"
import { expect, use } from "chai"
import { initializeTestFixture } from "./initialize-test.fixture"
import { PartyA } from "./models/partyA.model"
import { RunContext } from "./run-context"
import { IntentStatus, TradeSide } from "./option-enums"
import { openIntentRequestBuilder } from "./models/builders/send-open-intent.builder"
import { PartyB } from "./models/partyB.model"
import { ethers, network } from "hardhat"
import { e } from "../utils/e"
import { AbiCoder, encodeBytes32String, InterfaceAbi, ZeroAddress, AddressLike } from "ethers"
import { bigint, int } from "hardhat/internal/core/params/argumentTypes"
import { config } from "dotenv"
import { OpenIntentStruct, OpenIntentStructOutput, SymbolStruct } from "../types/contracts/interfaces/ISymmio"

import { MarginType } from "./option-enums"
import { getLatestBlockTime } from "../utils/time"
import { InstantLayer } from "../types"

import * as diamond from "../artifacts/contracts/Diamond.sol/Diamond.json"
import * as partyAOpenIntent from "../artifacts/contracts/facets/PartyAOpen/PartyAOpenFacet.sol/PartyAOpenFacet.json"
import * as partyBOpenIntent from "../artifacts/contracts/facets/PartyBOpen/PartyBOpenFacet.sol/PartyBOpenFacet.json"
import { trace } from "console"
import { zeroPad } from "@ethersproject/bytes"

export function shouldBehaveLikeInstantLayer(): void {
	let context: RunContext, partyA1: PartyA, partyA2: PartyA, partyB1: PartyB, partyB2: PartyB

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

		const latestBlock = await getLatestBlockTime()
		const request = openIntentRequestBuilder()
			.partyBsWhiteList([partyB1.getSigner])
			.affiliate(context.signers.affiliate1)
			.feeToken(context.collateralNL)
			.symbolId(1)
			.deadline(latestBlock + 120)
			.expirationTimestamp(latestBlock + 120)
			.exerciseFee({ cap: e(1), rate: "0" })
			.marginType(MarginType.ISOLATED)
			.tradeSide(TradeSide.BUY)
			.strikePrice(e(1))
			.build()

		let partyAOpenABI = new ethers.Interface(partyAOpenIntent.abi)
		const openIntentCallData = partyAOpenABI.encodeFunctionData("sendOpenIntent", [
			[partyB1.getSigner.address],
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
			await context.collateralNL.getAddress(),
			await context.signers.affiliate1.getAddress(),
			request.userData,
		])

		let partyBOpenABI = new ethers.Interface(partyBOpenIntent.abi)
		const lockIntentCallData = partyBOpenABI.encodeFunctionData("lockOpenIntent", [0])
		const fillIntentCallData = partyBOpenABI.encodeFunctionData("fillOpenIntent", [0, e(100), 7])

		// ops = [
		// 		{
		// 			callData: openIntentCallData,
		// 			insertionPoints: [],
		// 			sourceIndices: [],
		// 			signer : partyA1.getSigner
		// 		},
		// 		{
		// 			// account : partyB1.getSigner ,
		// 			callData: lockIntentCallData,
		// 			insertionPoints: [4],
		// 			sourceIndices: [0],
		// 			signer : partyB1.getSigner
		// 		},
		// 		{
		// 			// account : partyB1.getSigner ,
		// 			callData: fillIntentCallData,
		// 			insertionPoints: [4],
		// 			sourceIndices: [0],
		// 			signer : partyB1.getSigner
		// 		}
		// ]

		// signedOps = [
		// 		{
		// 			account : partyA1.getSigner ,
		// 			accountSource: partyB1.getSigner,
		// 			signer : partyB1.getSigner,
		// 			callData: openIntentCallData,
		// 			nonce: 0,
		// 			deadline: latestBlock + 120,
		// 			signature: "0x"
		// 		},
		// 		{
		// 			account : partyB1.getSigner ,
		// 			accountSource: partyB1.getSigner,
		// 			signer : partyB1.getSigner,
		// 			callData: lockIntentCallData,
		// 			nonce: 0,
		// 			deadline: latestBlock + 120,
		// 			signature: "0x"

		// 		},
		// 		{
		// 			account : partyB1.getSigner ,
		// 			accountSource: partyB1.getSigner,
		// 			signer : partyB1.getSigner,
		// 			callData: fillIntentCallData,
		// 			nonce: 0,
		// 			deadline: latestBlock + 120,
		// 			signature: "0x"

		// 		}
		// ]
	})

	describe("Registering PartyB", async function () {
		it("Should be failed when Sender not Setter Role ", async () => {
			await expect(context.instantLayer.connect(partyA1.getSigner).registerPartyB(partyB1.getSigner)).to.be.reverted
		})

		it("Should Add PartyB to Whitelisted Bs", async () => {
			await expect(context.instantLayer.registerPartyB(partyB1.getSigner)).not.to.be.reverted

			expect(await context.instantLayer.registeredPartyBs(partyB1.getSigner)).to.be.equal(true)
			expect(await context.instantLayer.registeredPartyBs(partyB2.getSigner)).to.be.equal(false)
		})

		it("Should be granted the right role", async () => {
			await expect(context.instantLayer.registerPartyB(partyB1.getSigner)).not.to.be.reverted
			const OPERATOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes("OPERATOR_ROLE"))

			expect(await context.instantLayer.hasRole(OPERATOR_ROLE, partyB1.getSigner)).to.be.equal(true)
		})
	})

	describe("Unregistering PartyB", async function () {
		it("Should be failed when Sender not Setter Role ", async () => {
			await expect(context.instantLayer.connect(partyA1.getSigner).unregisterPartyB(partyB1.getSigner)).to.be.reverted
		})

		it("Should remove PartyB from Whitelisted Bs", async () => {
			await expect(context.instantLayer.unregisterPartyB(partyB1.getSigner)).not.to.be.reverted

			expect(await context.instantLayer.registeredPartyBs(partyB1.getSigner)).to.be.equal(false)
		})

		it("Should remove the right role", async () => {
			await expect(context.instantLayer.registerPartyB(partyB1.getSigner)).not.to.be.reverted
			const OPERATOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes("OPERATOR_ROLE"))

			expect(await context.instantLayer.hasRole(OPERATOR_ROLE, partyB1.getSigner)).to.be.equal(true)
		})
	})

	describe("Registering PartyB Batch", async function () {
		it("Should be failed when Sender not Setter Role ", async () => {
			await expect(context.instantLayer.connect(partyA1.getSigner).registerPartyBBatch([partyB1.getSigner, partyB2.getSigner])).to.be.reverted
		})

		it("Should Add PartyB to Whitelisted Bs", async () => {
			await expect(context.instantLayer.registerPartyBBatch([partyB1.getSigner, partyB2.getSigner])).not.to.be.reverted

			expect(await context.instantLayer.registeredPartyBs(partyB1.getSigner)).to.be.equal(true)
			expect(await context.instantLayer.registeredPartyBs(partyB2.getSigner)).to.be.equal(true)
		})

		it("Should be granted the right role", async () => {
			await expect(context.instantLayer.registerPartyBBatch([partyB1.getSigner, partyB2.getSigner])).not.to.be.reverted
			const OPERATOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes("OPERATOR_ROLE"))

			// expect(await context.instantLayer.hasRole(OPERATOR_ROLE, partyB1.getSigner)).to.be.equal(true)
			// expect(await context.instantLayer.hasRole(OPERATOR_ROLE, partyB2.getSigner)).to.be.equal(true)
			//TODO
		})
	})

	describe("Registering MultiAccount Batch", async function () {
		it("Should be failed when Sender not Setter Role ", async () => {
			await expect(context.instantLayer.connect(partyA1.getSigner).registerMultiAccountBatch([partyB1.getSigner])).to.be.reverted
		})

		it("Should Add the multiAccount addresses batch to Whitelisted mapping", async () => {
			await expect(context.instantLayer.registerMultiAccountBatch([partyB1.getSigner, partyB2.getSigner])).not.to.be.reverted

			expect(await context.instantLayer.registeredMultiAccounts(partyB1.getSigner)).to.be.equal(true)
			expect(await context.instantLayer.registeredMultiAccounts(partyB2.getSigner)).to.be.equal(true)
		})
	})

	describe("Registering MultiAccount", async function () {
		it("Should be failed when Sender not Setter Role ", async () => {
			await expect(context.instantLayer.connect(partyA1.getSigner).registerMultiAccount(partyB1.getSigner)).to.be.reverted
		})

		it("Should Add the multiAccount address to Whitelisted mapping", async () => {
			await expect(context.instantLayer.registerMultiAccount(partyB1.getSigner)).not.to.be.reverted

			expect(await context.instantLayer.registeredMultiAccounts(partyB1.getSigner)).to.be.equal(true)
		})
	})

	describe("Unregistering MultiAccount", async function () {
		it("Should be failed when Sender not Setter Role ", async () => {
			await expect(context.instantLayer.connect(partyA1.getSigner).unregisterMultiAccount(partyB1.getSigner)).to.be.reverted
		})

		it("Should Remove the multiAccount address from Whitelisted mapping", async () => {
			await expect(context.instantLayer.unregisterMultiAccount(partyB1.getSigner)).not.to.be.reverted

			expect(await context.instantLayer.registeredMultiAccounts(partyB1.getSigner)).to.be.equal(false)
		})
	})

	describe("Adding Template", async function () {
		it("Should be failed when Sender not have Setter Role ", async () => {
			// await expect(context.instantLayer.connect(partyA1.getSigner).addTemplate("test",ops)).to.be.reverted
			//TODO adapt to recent changes
		})

		it("Should Set the template Active Mode to true", async () => {
			// await expect(context.instantLayer.addTemplate("test",ops)).not.to.be.reverted
			// let template = await context.instantLayer.getTemplate(0)
			// expect(template.active).to.be.equal(true)
			//TODO adapt to recent changes
		})

		it("Should Set the template Name as expected", async () => {
			// let name = "myTemp"
			// await expect(context.instantLayer.addTemplate(name,ops)).not.to.be.reverted
			// let template = await context.instantLayer.getTemplate(0)
			// expect(template.name).to.be.equal(name)
			//TODO adapt to recent changes
		})

		it("Should Set the template Operations as expected", async () => {
			// let name = "myTemp"
			// await expect(context.instantLayer.addTemplate(name,ops)).not.to.be.reverted
			// let operations = await context.instantLayer.getTemplateOperations(0)
			// expect(operations.length).to.be.equal(ops.length)
			// for(let i=0;i<ops.length;i++){
			// 	expect(operations[i].account).to.be.equal(ops[i].account)
			// 	expect(operations[i].signer).to.be.equal(ops[i].signer)
			// 	expect(operations[i].callData).to.be.deep.equal(ops[i].callData)
			// 	if(operations[i].insertionPoints.length > 0){
			// 		expect(operations[i].insertionPoints[0]).to.be.equal(ops[i].insertionPoints[0])
			// 	}
			// 	if(operations[i].sourceIndices.length){
			// 		expect(operations[i].sourceIndices[0]).to.be.equal(ops[i].sourceIndices[0])
			// 	}
			// }
			//TODO adopt to recent changes
		})
	})

	describe("execute Batch", async function () {
		beforeEach(async function () {})

		it("Should be failed when Sender not have Operator Role ", async () => {
			await expect(context.instantLayer.connect(partyA1.getSigner).executeBatch([])).to.be.reverted
		})

		it("Should be failed when input Ops have zero length ", async () => {
			// await expect(context.instantLayer.executeBatch([])).to.be.reverted
			//TODO
		})

		it("Should be failed when input Ops have passed the Deadline ", async () => {
			const newBlock = (await getLatestBlockTime()) + 120 + 12
			await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
			await network.provider.send("evm_mine")

			await context.instantLayer.registerPartyB(partyB1.getSigner)
			// await expect(context.instantLayer.executeBatch(signedOps)).to.be.revertedWithCustomError(context.instantLayer,"DeadlineExpired")
			//TODO
		})

		it("Should be able to set CallFromInstantLayer state with the right role", async () => {
			await expect(context.controlFacet.connect(partyA1.getSigner).setCallFromInstantLayer(true)).to.be.reverted

			await expect(context.controlFacet.setCallFromInstantLayer(true)).not.to.be.reverted
			expect(await context.viewFacet.isCallFromInstantLayer()).to.be.equal(true)

			await expect(context.controlFacet.setCallFromInstantLayer(false)).not.to.be.reverted
			expect(await context.viewFacet.isCallFromInstantLayer()).to.be.equal(false)
		})

		it("Should be failed when ", async () => {
			// await context.instantLayer.registerPartyB(partyB1.getSigner)
			// for(let i =0; i< signedOps.length; i++){
			// 	let hash = await context.instantLayer.getOperationHash(signedOps[i])
			// 	console.log("Hash Of Operation " + i +":",hash)
			// }
			// await expect(context.instantLayer.executeBatch(signedOps)).not.to.be.reverted
			//TODO
		})
	})
}
