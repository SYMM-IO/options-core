import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers"
import { expect, use } from "chai"
import { initializeTestFixture } from "../initialize-test.fixture"
import { PartyA } from "../models/partyA.model"
import { RunContext } from "../run-context"
import { IntentStatus, TradeSide, TradeStatus } from "../option-enums"
import { OpenIntent, openIntentRequestBuilder } from "../models/builders/send-open-intent.builder"
import { PartyB } from "../models/partyB.model"
import { ethers, network } from "hardhat"
import { e } from "../../utils/e"
import { AbiCoder, encodeBytes32String, InterfaceAbi, ZeroAddress, AddressLike, toUtf8Bytes } from "ethers"
import { bigint, int } from "hardhat/internal/core/params/argumentTypes"
import { config } from "dotenv"
import { OpenIntentStruct, OpenIntentStructOutput, SymbolStruct, TradeStruct } from "../../types/contracts/interfaces/ISymmio"

import { MarginType } from "../option-enums"
import { getLatestBlockTime } from "../../utils/time"
import { InstantLayer, MultiAccount } from "../../types"

import * as diamond from "../../artifacts/contracts/Diamond.sol/Diamond.json"
// import * as partyAOpenIntent from "../artifacts/contracts/facets/PartyAOpen/PartyAOpenFacet.sol/PartyAOpenFacet.json"
// import * as partyBOpenIntent from "../artifacts/contracts/facets/PartyBOpen/PartyBOpenFacet.sol/PartyBOpenFacet.json"
import { trace } from "console"
import { hexZeroPad, zeroPad } from "@ethersproject/bytes"
import { Context } from "mocha"

export function shouldBehaveLikeSymmioPartyB(): void {
	let context: RunContext, partyA1: PartyA, partyA2: PartyA, partyB1: PartyB, partyB2: PartyB
	let openIntentCallData: string, lockIntentCallData: string, fillIntentCallData: string
	let saltOpen1: string, saltOpen2: string, saltLock: string, saltFill: string

	let ops: InstantLayer.OperationStruct[]
	let signedOps: InstantLayer.SignedOperationStruct[]
	let ABI: InterfaceAbi

	let request: OpenIntent

	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)
		partyA1 = new PartyA(context, context.signers.partyA1)
		partyA2 = new PartyA(context, context.signers.partyA2)
		partyB1 = new PartyB(context, context.signers.partyB1)
		partyB2 = new PartyB(context, context.signers.partyB2)

		await partyA1.setBalances(context.collateral, e(100000), e(5000))
		await partyA1.setBalances(context.collateralNL, e(100000), e(5000)) // as Fee token
		await partyA2.setBalances(context.collateral, e(100000), e(5000))
		const { instantLayer, collateralNL, partyAOpenFacet, partyBOpenFacet } = context

		await context.controlFacet.setPartyBConfig(context.signers.partyB1, {
			isActive: true,
			lossCoverage: 0,
			oracleId: 1,
		})

		await context.controlFacet.setUnbindingCooldown(120)

		saltOpen1 = ethers.keccak256(ethers.toUtf8Bytes("saltOpen1"))
		saltOpen2 = ethers.keccak256(ethers.toUtf8Bytes("saltOpen2"))
		saltLock = ethers.keccak256(ethers.toUtf8Bytes("saltLock"))
		saltFill = ethers.keccak256(ethers.toUtf8Bytes("saltFill"))

		const latestBlock = await getLatestBlockTime()
		const deadline = latestBlock + 300

		request = openIntentRequestBuilder()
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
			.price(5)
			.quantity(e(1))
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
			request.solverFee,
			request.deadline,
			request.feeToken,
			request.affiliate,
			request.userData,
		])
		lockIntentCallData = partyBOpenFacet.interface.encodeFunctionData("lockOpenIntent", [1])
		fillIntentCallData = partyBOpenFacet.interface.encodeFunctionData("fillOpenIntent", [1, e(100), 7])
	})

	describe("Who is Signer?", async function () {
		beforeEach(async function () {})

		it("should set signer", async function () {
			await expect(context.symmioPartyB.setSigner(partyA1.getSigner)).not.reverted
		})
	})

	describe("Is Valid Signature?", async function () {
		beforeEach(async function () {})

		it("should Pass Signature verification with valid signer", async function () {
			const latestBlock = await getLatestBlockTime()
			const deadline = latestBlock + 300

			const saltHex = "0xabc123"
			const salt = hexZeroPad(saltHex, 32)
			let saltStr: string = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"

			if (!/^0x[0-9a-fA-F]{64}$/.test(salt) || !/^0x[0-9a-fA-F]{64}$/.test(saltStr)) {
				throw new Error("Invalid bytes32 format")
			}

			const opOpenALocal: InstantLayer.SignedOperationStruct = {
				accountSource: ZeroAddress,
				signer: await context.symmioPartyB.getAddress(),
				callData: "0x1234",
				nonce: 0,
				salt: saltStr,
				deadline: 0,
				signature: "0x",
			}

			const hash = await context.instantLayer.getOperationHash(opOpenALocal)
			opOpenALocal.signature = await partyB1.sign(ethers.getBytes(hash))

			await context.symmioPartyB.setSigner(partyB1.getSigner)
			expect(await context.symmioPartyB.isValidSignature(ethers.hashMessage(ethers.getBytes(hash)), opOpenALocal.signature)).to.be.equal("0x1626ba7e")
		})
	})

	describe("execute _Call Function", async function () {
		let opOpenA1: InstantLayer.SignedOperationStruct, opOpenA2: InstantLayer.SignedOperationStruct
		let opLockB1: InstantLayer.SignedOperationStruct, opFillB1: InstantLayer.SignedOperationStruct
		let accounts: MultiAccount.AccountStruct[]
		beforeEach(async function () {
			const latestBlock = await getLatestBlockTime()
			const deadline = latestBlock + 300

			await context.symmioPartyB.setSigner(partyB1.getSigner)

			opLockB1 = {
				accountSource: ethers.ZeroAddress,
				signer: await context.symmioPartyB.getAddress(),
				callData: lockIntentCallData,
				nonce: 0,
				salt: saltLock,
				deadline: deadline,
				signature: "0x",
			}

			opFillB1 = {
				accountSource: ethers.ZeroAddress,
				signer: await context.symmioPartyB.getAddress(),
				callData: fillIntentCallData,
				nonce: 0,
				salt: saltFill,
				deadline: deadline,
				signature: new Uint8Array([0x1, 0x2]),
			}
		})

		it("should fail when Symmio address not set", async function () {
			await context.symmioPartyB.setSymmioAddress(ZeroAddress)
			await expect(context.symmioPartyB._call([lockIntentCallData])).to.be.revertedWithCustomError(context.symmioPartyB, "InvalidAddress")
		})

		it("should fail when Call Data not set", async function () {
			await expect(context.symmioPartyB._call(["0x"])).to.be.revertedWithCustomError(context.symmioPartyB, "InvalidCallData")
		})

		it("Should be failed when input Ops have passed the Deadline ", async () => {
			const deadline = await getLatestBlockTime()
			await network.provider.send("evm_setNextBlockTimestamp", [deadline + 24])
			await network.provider.send("evm_mine")

			let saltStr: string = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
			const opOpenALocal: InstantLayer.SignedOperationStruct = {
				accountSource: ZeroAddress,
				signer: ZeroAddress,
				callData: "0x", // no matter
				nonce: 100, // no matter
				salt: saltStr, // no matter
				deadline: deadline,
				signature: "0x",
			}

			const abiCoder = ethers.AbiCoder.defaultAbiCoder()

			const encodedStruct = abiCoder.encode(
				[
					// Tuple type for SignedOperationStruct
					`tuple(
					address accountSource,
					address signer,
					bytes callData,
					uint256 nonce,
					bytes32 salt,
					uint256 deadline,
					bytes signature
					)`,
				],
				[opOpenALocal],
			)

			// const TRUSTED_ROLE = ethers.keccak256(ethers.toUtf8Bytes("TRUSTED_ROLE"))
			// const MANAGER_ROLE = ethers.keccak256(ethers.toUtf8Bytes("MANAGER_ROLE"))
			// await context.controlFacet.grantRole(await context.symmioPartyB.getAddress(), TRUSTED_ROLE)
			// await context.controlFacet.grantRole(await context.symmioPartyB.getAddress(), MANAGER_ROLE)
			// expect(await context.viewFacet.hasRole(context.signers.admin, TRUSTED_ROLE)).to.equal(true)
			// expect(await context.viewFacet.hasRole(context.signers.admin, MANAGER_ROLE)).to.equal(true)

			// await expect(context.symmioPartyB._call([lockIntentCallData])).to.be.revertedWithCustomError(context.symmioPartyB, "InvalidAddress")
			//TODO permission error
		})

		// it("should allow Sending Intents in a single batch", async function () {
		// 	const { instantLayer, collateralNL, partyAOpenFacet, partyBOpenFacet } = context
		// 	const multiAccount = context.multiAccount

		// 	//Sign using getOperationHash
		// 	const opOpenAHash1 = await instantLayer.getOperationHash(opOpenA1)
		// 	const opOpenAHash2 = await instantLayer.getOperationHash(opOpenA2)
		// 	const opLockBHash = await instantLayer.getOperationHash(opLockB1)
		// 	const opFillBHash = await instantLayer.getOperationHash(opFillB1)

		// 	opOpenA1.signature = await partyA1.sign(ethers.getBytes(opOpenAHash1))
		// 	opOpenA2.signature = await partyA1.sign(ethers.getBytes(opOpenAHash2))
		// 	opLockB1.signature = await partyB1.sign(ethers.getBytes(opLockBHash))
		// 	opFillB1.signature = await partyB1.sign(ethers.getBytes(opFillBHash))
		// 	console.log("OpenIntent Interface:", openIntentCallData)
		// 	console.log("LockIntent Interface:", lockIntentCallData)
		// 	console.log("FillIntent Interface:", fillIntentCallData)
		// 	console.log("PartyA address:", partyA1.address)
		// 	console.log("PartyA Account address:", accounts[0].account)
		// 	console.log("PartyB1 address:", partyB1.address)
		// 	console.log("Symmio PartyB address:", await context.symmioPartyB.getAddress())
		// 	console.log("MultiAccount address:", await multiAccount.getAddress())
		// 	console.log("Signature and length PartyA Open:", opOpenA1.signature.length, opOpenA1.signature)
		// 	console.log("Signature and length PartyB Lock:", opLockB1.signature.length, opLockB1.signature)
		// 	console.log("Signature and length PartyB Fill:", opFillB1.signature.length, opFillB1.signature)

		// 	try {
		// 		let recoveredAddress = ethers.verifyMessage(ethers.getBytes(opOpenAHash1), opOpenA1.signature)
		// 		console.log("Party A Verifyed:", recoveredAddress === partyA1.address)
		// 		console.log("signer vs Recovered", opOpenA1.signer, " vs ", recoveredAddress)
		// 		recoveredAddress = ethers.verifyMessage(ethers.getBytes(opLockBHash), opLockB1.signature)
		// 		console.log("Party B Verifyed:", recoveredAddress === opLockB1.signer)
		// 		console.log("signer vs Recovered", opLockB1.signer, " vs ", recoveredAddress)
		// 		recoveredAddress = ethers.verifyMessage(ethers.getBytes(opFillBHash), opFillB1.signature)
		// 		console.log("Party B Fill Verifyed:", recoveredAddress === opFillB1.signer)
		// 		console.log("signer vs Recovered", opFillB1.signer, " vs ", recoveredAddress)
		// 	} catch (error) {
		// 		console.error("Verification failed:", error)
		// 		return false
		// 	}

		// 	await context.controlFacet.grantRole(context.instantLayer, ethers.keccak256(toUtf8Bytes("INSTANT_LAYER_ROLE")))

		// 	// Execute the batch using 1 open Intent signed from the PartyA submitted to PartyB API
		// 	// Accompanying with a lock and fill signed from PartyB and Finally submitted to Instant Layer
		// 	const signedOps: InstantLayer.SignedOperationStruct[] = [opOpenA1, opOpenA2]
		// 	await expect(instantLayer.executeBatch(signedOps)).not.to.be.reverted
		// 	let intent: OpenIntentStruct = await context.viewFacet.getOpenIntent(1)
		// 	expect(intent.price).to.be.equal(request.price).to.be.equal(5)
		// 	expect(intent.tradeAgreements.quantity).to.be.equal(request.quantity).to.equal(e(1))
		// })

		// it("should allow Sending Intent, Locking and Filling in a single batch", async function () {
		// 	const { instantLayer, collateralNL, partyAOpenFacet, partyBOpenFacet } = context
		// 	const multiAccount = context.multiAccount

		// 	//Sign using getOperationHash
		// 	const opOpenAHash1 = await instantLayer.getOperationHash(opOpenA1)
		// 	const opLockBHash = await instantLayer.getOperationHash(opLockB1)
		// 	const opFillBHash = await instantLayer.getOperationHash(opFillB1)

		// 	opOpenA1.signature = await partyA1.sign(ethers.getBytes(opOpenAHash1))
		// 	opLockB1.signature = await partyB1.sign(ethers.getBytes(opLockBHash))
		// 	opFillB1.signature = await partyB1.sign(ethers.getBytes(opFillBHash))

		// 	await context.controlFacet.grantRole(context.instantLayer, ethers.keccak256(toUtf8Bytes("INSTANT_LAYER_ROLE")))

		// 	// Execute the batch using 1 open Intent signed from the PartyA submitted to PartyB API
		// 	// Accompanying with a lock and fill signed from PartyB and Finally submitted to Instant Layer
		// 	const signedOps: InstantLayer.SignedOperationStruct[] = [opOpenA1, opLockB1]
		// 	await expect(instantLayer.executeBatch(signedOps)).to.be.revertedWithCustomError(context.instantLayer, "InvalidNonce")

		// 	// let intent: OpenIntentStruct = await context.viewFacet.getOpenIntent(1)
		// 	// let trade: TradeStruct = await context.viewFacet.getTrade(1)
		// 	// expect(intent.price).to.be.equal(request.price).to.be.equal(5)
		// 	// expect(intent.tradeAgreements.quantity).to.be.equal(request.quantity).to.equal(e(1))
		// 	// expect(intent.status).to.be.equal(IntentStatus.FILLED)
		// 	// expect(trade.openIntentId).to.be.equal(intent.id)
		// 	// expect(trade.status).to.be.equal(TradeStatus.OPENED)

		// 	//TODO signature verification to Use EIP-1271
		// })
	})
}
