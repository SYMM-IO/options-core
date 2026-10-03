import { ethers, networkHelpers } from "../connection.js"
import { expect, use } from "chai"
import { initializeTestFixture } from "../initialize-test.fixture.js"
import { PartyA } from "../models/partyA.model.js"
import { RunContext } from "../run-context.js"
import { IntentStatus, TradeSide, TradeStatus } from "../option-enums.js"
import { OpenIntent, openIntentRequestBuilder } from "../models/builders/send-open-intent.builder.js"
import { PartyB } from "../models/partyB.model.js"
import { e } from "../../utils/e.js"
import { AbiCoder, encodeBytes32String, InterfaceAbi, ZeroAddress, AddressLike, toUtf8Bytes, EthersError, zeroPadValue } from "ethers"
import { OpenIntentStruct, OpenIntentStructOutput, SymbolStruct, TradeStruct } from "../../types/interfaces/ISymmio.js"

import { MarginType } from "../option-enums.js"
import { getLatestBlockTime } from "../utils/time.js"
import { InstantLayer, MultiAccount } from "../../types/index.js"

import diamond from "../../artifacts/contracts/Diamond.sol/Diamond.json" with { type: "json" }

export function shouldBehaveLikeInstantLayer(): void {
	let context: RunContext, partyA1: PartyA, partyA2: PartyA, partyB1: PartyB, partyB2: PartyB
	let openIntentCallData: string, lockIntentCallData: string, fillIntentCallData: string
	let saltOpen1: string, saltOpen2: string, saltLock: string, saltFill: string

	let ops: InstantLayer.OperationStruct[]
	let signedOps: InstantLayer.SignedOperationStruct[]
	let ABI: InterfaceAbi

	let request: OpenIntent

	beforeEach(async function () {
		context = await networkHelpers.loadFixture(initializeTestFixture)
		partyA1 = new PartyA(context, context.signers.partyA1)
		partyA2 = new PartyA(context, context.signers.partyA2)
		partyB1 = new PartyB(context, context.signers.partyB1)
		partyB2 = new PartyB(context, context.signers.partyB2)

		await partyA1.setBalances(context.collateral, e(100000), e(5000))
		await partyA1.setBalances(context.collateralNL, e(100000), e(5000)) // as Fee token
		await partyA2.setBalances(context.collateral, e(100000), e(5000))
		const { instantLayer, collateralNL, partyAOpenFacet, partyBOpenFacet } = context

		await context.controlFacet.setUnbindingCooldown(120)

		saltOpen1 = ethers.keccak256(ethers.toUtf8Bytes("saltOpen1"))
		saltOpen2 = ethers.keccak256(ethers.toUtf8Bytes("saltOpen2"))
		saltLock = ethers.keccak256(ethers.toUtf8Bytes("saltLock"))
		saltFill = ethers.keccak256(ethers.toUtf8Bytes("saltFill"))

		const latestBlock = await getLatestBlockTime()
		const deadline = latestBlock + 300

		request = openIntentRequestBuilder()
			.partyBsWhiteList([])
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
		fillIntentCallData = partyBOpenFacet.interface.encodeFunctionData("fillOpenIntent", [1, request.quantity, request.price])

		ops = [
			{
				sourceIndices: [],
				insertionPoints: [],
			},
			{
				sourceIndices: [],
				insertionPoints: [],
			},
			{
				sourceIndices: [0],
				insertionPoints: [0],
			},
			{
				sourceIndices: [0],
				insertionPoints: [0],
			},
		]
	})

	describe("Registering PartyB", async function () {
		it("Should be failed when Sender not Setter Role ", async () => {
			await expect(context.instantLayer.connect(partyA1.getSigner).registerPartyB(partyB1.getSigner)).to.revert(ethers)
		})

		it("Should Add PartyB to Whitelisted Bs", async () => {
			await expect(context.instantLayer.registerPartyB(partyB1.getSigner)).not.to.revert(ethers)

			expect(await context.instantLayer.registeredPartyBs(partyB1.getSigner)).to.be.equal(true)
			expect(await context.instantLayer.registeredPartyBs(partyB2.getSigner)).to.be.equal(false)
		})

		it("Should be granted the right role", async () => {
			await expect(context.instantLayer.registerPartyB(partyB1.getSigner)).not.to.revert(ethers)
			const OPERATOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes("OPERATOR_ROLE"))

			expect(await context.instantLayer.hasRole(OPERATOR_ROLE, partyB1.getSigner)).to.be.equal(true)
		})
	})

	describe("Unregistering PartyB", async function () {
		it("Should be failed when Sender not Setter Role ", async () => {
			await expect(context.instantLayer.connect(partyA1.getSigner).unregisterPartyB(partyB1.getSigner)).to.revert(ethers)
		})

		it("Should remove PartyB from Whitelisted Bs", async () => {
			await expect(context.instantLayer.unregisterPartyB(partyB1.getSigner)).not.to.revert(ethers)

			expect(await context.instantLayer.registeredPartyBs(partyB1.getSigner)).to.be.equal(false)
		})

		it("Should remove the right role", async () => {
			await expect(context.instantLayer.unregisterPartyB(partyB1.getSigner)).not.to.revert(ethers)
			const OPERATOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes("OPERATOR_ROLE"))

			expect(await context.instantLayer.hasRole(OPERATOR_ROLE, partyB1.getSigner)).to.be.equal(false)
		})
	})

	describe("Registering PartyB Batch", async function () {
		it("Should be failed when Sender not Setter Role ", async () => {
			await expect(context.instantLayer.connect(partyA1.getSigner).registerPartyBBatch([partyB1.getSigner, partyB2.getSigner])).to.revert(ethers)
		})

		it("Should Add PartyB to Whitelisted Bs", async () => {
			await expect(context.instantLayer.registerPartyBBatch([partyB1.getSigner, partyB2.getSigner])).not.to.revert(ethers)

			expect(await context.instantLayer.registeredPartyBs(partyB1.getSigner)).to.be.equal(true)
			expect(await context.instantLayer.registeredPartyBs(partyB2.getSigner)).to.be.equal(true)
		})

		it("Should be granted the right role", async () => {
			await expect(context.instantLayer.registerPartyBBatch([partyB1.getSigner, partyB2.getSigner])).not.to.revert(ethers)
			const OPERATOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes("OPERATOR_ROLE"))

			expect(await context.instantLayer.hasRole(OPERATOR_ROLE, partyB1.getSigner)).to.be.equal(true)
			expect(await context.instantLayer.hasRole(OPERATOR_ROLE, partyB2.getSigner)).to.be.equal(true)
		})
	})

	describe("Registering MultiAccount Batch", async function () {
		it("Should be failed when Sender not Setter Role ", async () => {
			await expect(context.instantLayer.connect(partyA1.getSigner).registerMultiAccountBatch([partyB1.getSigner])).to.revert(ethers)
		})

		it("Should Add the multiAccount addresses batch to Whitelisted mapping", async () => {
			await expect(context.instantLayer.registerMultiAccountBatch([partyB1.getSigner, partyB2.getSigner])).not.to.revert(ethers)

			expect(await context.instantLayer.registeredMultiAccounts(partyB1.getSigner)).to.be.equal(true)
			expect(await context.instantLayer.registeredMultiAccounts(partyB2.getSigner)).to.be.equal(true)
		})
	})

	describe("Registering MultiAccount", async function () {
		it("Should be failed when Sender not Setter Role ", async () => {
			await expect(context.instantLayer.connect(partyA1.getSigner).registerMultiAccount(partyB1.getSigner)).to.revert(ethers)
		})

		it("Should Add the multiAccount address to Whitelisted mapping", async () => {
			await expect(context.instantLayer.registerMultiAccount(partyB1.getSigner)).not.to.revert(ethers)

			expect(await context.instantLayer.registeredMultiAccounts(partyB1.getSigner)).to.be.equal(true)
		})
	})

	describe("Unregistering MultiAccount", async function () {
		it("Should be failed when Sender not Setter Role ", async () => {
			await expect(context.instantLayer.connect(partyA1.getSigner).unregisterMultiAccount(partyB1.getSigner)).to.revert(ethers)
		})

		it("Should Remove the multiAccount address from Whitelisted mapping", async () => {
			await expect(context.instantLayer.unregisterMultiAccount(partyB1.getSigner)).not.to.revert(ethers)

			expect(await context.instantLayer.registeredMultiAccounts(partyB1.getSigner)).to.be.equal(false)
		})
	})

	describe("Adding Template", async function () {
		it("Should be failed when Sender not have Setter Role ", async () => {
			await expect(context.instantLayer.connect(partyA1.getSigner).addTemplate("test", ops)).to.revert(ethers)
			//TODO adapt to recent changes
		})

		it("Should Set the template Active Mode to true", async () => {
			await expect(context.instantLayer.addTemplate("test", ops)).not.to.revert(ethers)
			let template = await context.instantLayer.getTemplate(0)
			expect(template.active).to.be.equal(true)
		})

		it("Should Set the template Name as expected", async () => {
			let name = "myTemp"
			await expect(context.instantLayer.addTemplate(name, ops)).not.to.revert(ethers)
			let template = await context.instantLayer.getTemplate(0)
			expect(template.name).to.be.equal(name)
		})

		it("Should Set the template Operations as expected", async () => {
			let name = "myTemp"
			await expect(context.instantLayer.addTemplate(name, ops)).not.to.revert(ethers)
			const tempID = (await context.instantLayer.getLastTemplateID()) - 1n
			let template: InstantLayer.TemplateStruct = await context.instantLayer.getTemplate(tempID)

			expect(template.operations.length).to.be.equal(ops.length) // equals 2
			expect(template.name).to.equal(name)
			expect(template.active).to.equal(true)

			for (let i = 0; i < template.operations.length; i++) {
				expect(template.operations[i].sourceIndices).to.deep.equal(ops[i].sourceIndices)
				expect(template.operations[i].insertionPoints).to.deep.equal(ops[i].insertionPoints)
			}
		})
	})

	describe("Is Valid Signature?", async function () {
		beforeEach(async function () {})

		it("should Pass Signature verification with valid signer", async function () {
			const latestBlock = await getLatestBlockTime()
			const deadline = latestBlock + 300

			const saltHex = "0xabc123"
			const salt = zeroPadValue(saltHex, 32)
			const saltStr: string = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"

			if (!/^0x[0-9a-fA-F]{64}$/.test(salt) || !/^0x[0-9a-fA-F]{64}$/.test(saltStr)) {
				throw new Error("Invalid bytes32 format")
			}

			const opOpenA: InstantLayer.SignedOperationStruct = {
				accountSource: ZeroAddress,
				signer: partyA1.address,
				callData: "0x1234",
				nonce: 0,
				salt: salt,
				deadline: 0,
				signature: "0x",
			}

			const hash = await context.instantLayer.getOperationHash(opOpenA)
			opOpenA.signature = await partyA1.sign(ethers.getBytes(hash))

			expect(await context.instantLayer.isValidSignature(opOpenA.signer, hash, opOpenA.signature)).to.be.equal(true)
		})
	})

	describe("execute Batch", async function () {
		let opOpenA1: InstantLayer.SignedOperationStruct, opOpenA2: InstantLayer.SignedOperationStruct
		let opLockB1: InstantLayer.SignedOperationStruct, opFillB1: InstantLayer.SignedOperationStruct
		let accounts: MultiAccount.AccountStruct[]
		beforeEach(async function () {
			const latestBlock = await getLatestBlockTime()
			const deadline = latestBlock + 300

			await expect(context.multiAccount.connect(partyA1.getSigner).addAccount("testAccount")).not.to.revert(ethers) // here the party A Role is an EOA to create an Party A address
			accounts = await context.multiAccount.getAccounts(partyA1.address, 0, 100)

			// await expect(context.collateral.connect(partyA1.getSigner).approve(context.common.diamondAddress, ethers.MaxUint256)).not.to.revert(ethers)
			await context.symmioPartyB.grantRole(ethers.keccak256(toUtf8Bytes("TRUSTED_ROLE")), partyA1.address)
			await expect(context.symmioPartyB.connect(partyA1.getSigner)._approve(context.collateral, e(30))).not.to.revert(ethers) // for symmoio contract

			await expect(context.collateral.connect(partyA1.getSigner).mint(accounts[0].account, e(30))).not.to.revert(ethers)
			await expect(context.collateralNL.connect(partyA1.getSigner).mint(accounts[0].account, e(30))).not.to.revert(ethers)
			await context.accountFacet.connect(partyA1.getSigner).depositFor(await context.collateral.getAddress(), accounts[0].account, e(20))
			await context.accountFacet.connect(partyA1.getSigner).depositFor(await context.collateralNL.getAddress(), accounts[0].account, e(20))

			opOpenA1 = {
				accountSource: await context.multiAccount.getAddress(),
				signer: accounts[0].account,
				callData: openIntentCallData,
				nonce: 0,
				salt: saltOpen1,
				deadline: deadline,
				signature: new Uint8Array([0x1, 0x2]),
			}

			opOpenA2 = {
				accountSource: await context.multiAccount.getAddress(),
				signer: accounts[0].account,
				callData: openIntentCallData,
				nonce: 0,
				salt: saltOpen2,
				deadline: deadline,
				signature: new Uint8Array([0x1, 0x2]),
			}

			opLockB1 = {
				accountSource: ethers.ZeroAddress,
				signer: await context.symmioPartyB.getAddress(),
				callData: lockIntentCallData,
				nonce: 0,
				salt: saltLock,
				deadline: deadline,
				signature: new Uint8Array([0x1, 0x2]),
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

		it("Should be failed when Sender not have Operator Role ", async () => {
			await expect(context.instantLayer.connect(partyA1.getSigner).executeBatch([])).to.revert(ethers) // with "AccessControl" Error
		})

		it("Should be failed when input Ops have zero length ", async () => {
			await expect(context.instantLayer.executeBatch([])).to.be.revertedWithCustomError(context.instantLayer, "EmptyBatch")
		})

		it("Should be failed when input Ops have passed the Deadline ", async () => {
			const deadline = await getLatestBlockTime()
			await ethers.provider.send("evm_setNextBlockTimestamp", [deadline + 24])
			await ethers.provider.send("evm_mine")

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

			await context.controlFacet.grantRole(context.instantLayer, ethers.keccak256(toUtf8Bytes("INSTANT_LAYER_ROLE")))
			await expect(context.instantLayer.executeBatch([opOpenALocal])).to.be.revertedWithCustomError(context.instantLayer, "DeadlineExpired")
		})

		it("Should be able to set CallFromInstantLayer state with the right role", async () => {
			await expect(context.controlFacet.connect(partyA1.getSigner).setCallFromInstantLayer(true)).to.revert(ethers)

			await expect(context.controlFacet.setCallFromInstantLayer(true)).not.to.revert(ethers)
			expect(await context.viewFacet.isCallFromInstantLayer()).to.be.equal(true)

			await expect(context.controlFacet.setCallFromInstantLayer(false)).not.to.revert(ethers)
			expect(await context.viewFacet.isCallFromInstantLayer()).to.be.equal(false)
		})

		it("should Set the SYMMIO to Accept Instant Layer Actions", async function () {
			await context.controlFacet.setCallFromInstantLayer(true)
			expect(await context.viewFacet.isCallFromInstantLayer()).to.be.equal(true)
		})

		it("should Register Symmio PartyB when sending as PartyB", async function () {
			const deadline = (await getLatestBlockTime()) + 24
			let saltStr: string = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
			const opOpenALocal: InstantLayer.SignedOperationStruct = {
				accountSource: ZeroAddress,
				signer: partyA1.address,
				callData: "0x", // no matter
				nonce: 100, // no matter
				salt: saltStr, // no matter
				deadline: deadline,
				signature: "0x",
			}

			await context.controlFacet.grantRole(context.instantLayer, ethers.keccak256(toUtf8Bytes("INSTANT_LAYER_ROLE")))
			await expect(context.instantLayer.executeBatch([opOpenALocal])).to.be.revertedWithCustomError(context.instantLayer, "UnregisteredPartyB")
		})

		it("should reject PartyA operations from an unregistered MultiAccount before consuming the signature", async function () {
			await context.controlFacet.grantRole(context.instantLayer, ethers.keccak256(toUtf8Bytes("INSTANT_LAYER_ROLE")))

			await expect(context.instantLayer.executeBatch([opOpenA1]))
				.to.be.revertedWithCustomError(context.instantLayer, "UnregisteredMultiAccount")
				.withArgs(await context.multiAccount.getAddress())

			expect(await context.instantLayer.usedOperationHashes(await context.instantLayer.getOperationHash(opOpenA1))).to.equal(false)
			expect(await context.viewFacet.getLastOpenIntentId()).to.equal(0)
			expect(await context.viewFacet.isCallFromInstantLayer()).to.equal(false)
		})

		it("should reject a replayed salt operation without creating another intent", async function () {
			await context.instantLayer.registerMultiAccount(context.multiAccount)
			await context.controlFacet.grantRole(context.instantLayer, ethers.keccak256(toUtf8Bytes("INSTANT_LAYER_ROLE")))

			const opHash = await context.instantLayer.getOperationHash(opOpenA1)
			opOpenA1.signature = await partyA1.sign(ethers.getBytes(opHash))

			await expect(context.instantLayer.executeBatch([opOpenA1]))
				.to.emit(context.instantLayer, "BatchExecuted")
				.withArgs(context.signers.admin.address, 1)
			expect(await context.instantLayer.usedOperationHashes(opHash)).to.equal(true)
			expect(await context.viewFacet.getLastOpenIntentId()).to.equal(1)
			expect(await context.viewFacet.isCallFromInstantLayer()).to.equal(false)

			await expect(context.instantLayer.executeBatch([opOpenA1]))
				.to.be.revertedWithCustomError(context.instantLayer, "OperationAlreadyExecuted")
				.withArgs(opHash)
			expect(await context.viewFacet.getLastOpenIntentId()).to.equal(1)
			expect(await context.viewFacet.isCallFromInstantLayer()).to.equal(false)
		})

		it("should reject PartyB operations after the PartyB contract signer is rotated", async function () {
			await context.instantLayer.registerPartyB(context.symmioPartyB)
			await context.symmioPartyB.setSigner(partyB1.getSigner)
			await context.controlFacet.grantRole(context.instantLayer, ethers.keccak256(toUtf8Bytes("INSTANT_LAYER_ROLE")))

			const opHash = await context.instantLayer.getOperationHash(opLockB1)
			opLockB1.signature = await partyB1.sign(ethers.getBytes(opHash))
			await context.symmioPartyB.setSigner(partyB2.getSigner)

			await expect(context.instantLayer.executeBatch([opLockB1]))
				.to.be.revertedWithCustomError(context.instantLayer, "InvalidSignature")
				.withArgs(await context.symmioPartyB.getAddress())
			expect(await context.instantLayer.usedOperationHashes(opHash)).to.equal(false)
			expect(await context.viewFacet.isCallFromInstantLayer()).to.equal(false)
		})

		it("should allow Sending Intents in a single batch", async function () {
			const { instantLayer, collateralNL, partyAOpenFacet, partyBOpenFacet } = context
			const multiAccount = context.multiAccount

			// Granting Roles
			await context.instantLayer.registerPartyB(await context.symmioPartyB.getAddress()) // Admin with SETTER Role
			await context.instantLayer.registerMultiAccount(context.multiAccount) // Admin with SETTER Role

			await context.symmioPartyB.setSigner(partyB1.getSigner) // Admin with SETTER Role

			//Sign using getOperationHash
			const opOpenAHash1 = await instantLayer.getOperationHash(opOpenA1)
			const opOpenAHash2 = await instantLayer.getOperationHash(opOpenA2)
			const opLockBHash = await instantLayer.getOperationHash(opLockB1)
			const opFillBHash = await instantLayer.getOperationHash(opFillB1)

			opOpenA1.signature = await partyA1.sign(ethers.getBytes(opOpenAHash1))
			opOpenA2.signature = await partyA1.sign(ethers.getBytes(opOpenAHash2))
			opLockB1.signature = await partyB1.sign(ethers.getBytes(opLockBHash))
			opFillB1.signature = await partyB1.sign(ethers.getBytes(opFillBHash))
			console.log("OpenIntent Interface:", openIntentCallData)
			console.log("LockIntent Interface:", lockIntentCallData)
			console.log("FillIntent Interface:", fillIntentCallData)
			console.log("PartyA address:", partyA1.address)
			console.log("PartyA Account address:", accounts[0].account)
			console.log("PartyB1 address:", partyB1.address)
			console.log("Symmio PartyB address:", await context.symmioPartyB.getAddress())
			console.log("MultiAccount address:", await multiAccount.getAddress())
			console.log("Signature and length PartyA Open:", opOpenA1.signature.length, opOpenA1.signature)
			console.log("Signature and length PartyB Lock:", opLockB1.signature.length, opLockB1.signature)
			console.log("Signature and length PartyB Fill:", opFillB1.signature.length, opFillB1.signature)

			try {
				let recoveredAddress = ethers.verifyMessage(ethers.getBytes(opOpenAHash1), opOpenA1.signature)
				console.log("Party A Verifyed:", recoveredAddress === partyA1.address)
				console.log("signer vs Recovered", opOpenA1.signer, " vs ", recoveredAddress)
				recoveredAddress = ethers.verifyMessage(ethers.getBytes(opLockBHash), opLockB1.signature)
				console.log("Party B Verifyed:", recoveredAddress === opLockB1.signer)
				console.log("signer vs Recovered", opLockB1.signer, " vs ", recoveredAddress)
				recoveredAddress = ethers.verifyMessage(ethers.getBytes(opFillBHash), opFillB1.signature)
				console.log("Party B Fill Verifyed:", recoveredAddress === opFillB1.signer)
				console.log("signer vs Recovered", opFillB1.signer, " vs ", recoveredAddress)
			} catch (error) {
				console.error("Verification failed:", error)
				return false
			}

			await context.controlFacet.grantRole(context.instantLayer, ethers.keccak256(toUtf8Bytes("INSTANT_LAYER_ROLE")))

			const signedOps: InstantLayer.SignedOperationStruct[] = [opOpenA1, opOpenA2]
			await expect(instantLayer.executeBatch(signedOps)).not.to.revert(ethers)

			let intent: OpenIntentStruct = await context.viewFacet.getOpenIntent(1)
			expect(intent.price).to.be.equal(request.price).to.be.equal(5)
			expect(intent.tradeAgreements.quantity).to.be.equal(request.quantity).to.equal(e(1))
		})

		it("should allow Sending Intent, Locking and Filling in a single batch Seperately", async function () {
			const { instantLayer, collateralNL, partyAOpenFacet, partyBOpenFacet } = context
			const multiAccount = context.multiAccount

			// Granting Roles
			await context.instantLayer.registerPartyB(await context.symmioPartyB.getAddress())
			await context.instantLayer.registerMultiAccount(context.multiAccount)

			await context.symmioPartyB.setSigner(partyB1.getSigner)
			await context.symmioPartyB.setMulticastWhitelist(context.common.diamondAddress, true)

			//Sign using getOperationHash
			const opOpenAHash1 = await instantLayer.getOperationHash(opOpenA1)
			const opLockBHash = await instantLayer.getOperationHash(opLockB1)
			const opFillBHash = await instantLayer.getOperationHash(opFillB1)

			opOpenA1.signature = await partyA1.sign(ethers.getBytes(opOpenAHash1))
			opLockB1.signature = await partyB1.sign(ethers.getBytes(opLockBHash))
			opFillB1.signature = await partyB1.sign(ethers.getBytes(opFillBHash))

			await context.controlFacet.grantRole(context.instantLayer, ethers.keccak256(toUtf8Bytes("INSTANT_LAYER_ROLE")))

			const signedOps: InstantLayer.SignedOperationStruct[] = [opOpenA1]
			await expect(instantLayer.executeBatch(signedOps)).not.to.revert(ethers) // Admin with OPERATOR Role
			const lastID = await context.viewFacet.getLastOpenIntentId()
			expect(lastID).to.equal(1)
			let intent: OpenIntentStruct = await context.viewFacet.getOpenIntent(lastID)
			expect(intent.price).to.be.equal(request.price)
			expect(intent.tradeAgreements.quantity).to.be.equal(request.quantity)

			// await expect(multiAccount.connect(accounts))

			await context.controlFacet.setPartyBConfig(context.symmioPartyB.getAddress(), {
				// Admin with PARTY_B_MANAGER_ROLE
				isActive: true,
				lossCoverage: 0,
				oracleId: 1,
			})

			await context.controlFacet.setPartyBSupportedSymbolTypes(context.symmioPartyB.getAddress(), [0], [true])

			const signedOpsLock: InstantLayer.SignedOperationStruct[] = [opLockB1]
			await expect(instantLayer.executeBatch(signedOpsLock)).not.to.revert(ethers)

			intent = await context.viewFacet.getOpenIntent(lastID)
			console.log("Intent Status", lastID, intent.status == IntentStatus.LOCKED ? "Locked" : intent.status)

			const signedOpsFill: InstantLayer.SignedOperationStruct[] = [opFillB1]
			await expect(instantLayer.executeBatch(signedOpsFill)).not.to.revert(ethers)

			intent = await context.viewFacet.getOpenIntent(lastID)
			console.log("Intent Status", lastID, intent.status == IntentStatus.FILLED ? "Filled" : intent.status)
			expect(intent.status).to.be.equal(IntentStatus.FILLED)

			const lastTradeId = await context.viewFacet.getLastTradeId()
			let trade: TradeStruct = await context.viewFacet.getTrade(lastTradeId)
			expect(trade.openIntentId).to.be.equal(intent.id)
		})

		it("should allow Sending Intent, Locking and Filling in a single batch Altogether", async function () {
			const { instantLayer, collateralNL, partyAOpenFacet, partyBOpenFacet } = context
			const multiAccount = context.multiAccount

			// Granting Roles
			await context.instantLayer.registerPartyB(await context.symmioPartyB.getAddress())
			await context.instantLayer.registerMultiAccount(context.multiAccount)

			await context.symmioPartyB.setSigner(partyB1.getSigner)
			await context.symmioPartyB.setMulticastWhitelist(context.common.diamondAddress, true)

			//Sign using getOperationHash
			const opOpenAHash1 = await instantLayer.getOperationHash(opOpenA1)
			const opLockBHash = await instantLayer.getOperationHash(opLockB1)
			const opFillBHash = await instantLayer.getOperationHash(opFillB1)

			opOpenA1.signature = await partyA1.sign(ethers.getBytes(opOpenAHash1))
			opLockB1.signature = await partyB1.sign(ethers.getBytes(opLockBHash))
			opFillB1.signature = await partyB1.sign(ethers.getBytes(opFillBHash))

			await context.controlFacet.grantRole(context.instantLayer, ethers.keccak256(toUtf8Bytes("INSTANT_LAYER_ROLE")))
			await context.controlFacet.setPartyBConfig(context.symmioPartyB.getAddress(), {
				// Admin with PARTY_B_MANAGER_ROLE
				isActive: true,
				lossCoverage: 0,
				oracleId: 1,
			})
			await context.controlFacet.setPartyBSupportedSymbolTypes(context.symmioPartyB.getAddress(), [0], [true])

			//Execution
			const signedOps: InstantLayer.SignedOperationStruct[] = [opOpenA1, opLockB1, opFillB1]
			await expect(instantLayer.executeBatch(signedOps)).not.to.revert(ethers) // Admin with OPERATOR Role

			//Verificaiton
			const lastID = await context.viewFacet.getLastOpenIntentId()
			expect(lastID).to.equal(1)
			let intent: OpenIntentStruct = await context.viewFacet.getOpenIntent(lastID)
			expect(intent.price).to.be.equal(request.price)
			expect(intent.tradeAgreements.quantity).to.be.equal(request.quantity)
			intent = await context.viewFacet.getOpenIntent(lastID)
			console.log("Intent Status", lastID, intent.status == IntentStatus.LOCKED ? "Locked" : intent.status)
			intent = await context.viewFacet.getOpenIntent(lastID)
			console.log("Intent Status", lastID, intent.status == IntentStatus.FILLED ? "Filled" : intent.status)
			expect(intent.status).to.be.equal(IntentStatus.FILLED)
			const lastTradeId = await context.viewFacet.getLastTradeId()
			let trade: TradeStruct = await context.viewFacet.getTrade(lastTradeId)
			expect(trade.openIntentId).to.be.equal(intent.id)
		})

		it("should Fail Signature verification with Invalid Nonce", async function () {
			const latestBlock = await getLatestBlockTime()
			const deadline = latestBlock + 300

			// Granting Roles
			await context.instantLayer.registerMultiAccount(context.multiAccount)

			let saltStr: string = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
			if (!/^0x[0-9a-fA-F]{64}$/.test(saltStr)) {
				throw new Error("Invalid bytes32 format")
			}

			const opOpenALocal: InstantLayer.SignedOperationStruct = {
				accountSource: await context.multiAccount.getAddress(),
				signer: accounts[0].account,
				callData: openIntentCallData,
				nonce: 2,
				salt: saltStr,
				deadline: deadline,
				signature: "0x",
			}

			const hash = await context.instantLayer.getOperationHash(opOpenALocal)
			opOpenALocal.signature = await partyA1.sign(ethers.getBytes(hash))

			await context.controlFacet.grantRole(context.instantLayer, ethers.keccak256(toUtf8Bytes("INSTANT_LAYER_ROLE")))

			await expect(context.instantLayer.executeBatch([opOpenALocal])).to.be.revertedWithCustomError(context.instantLayer, "InvalidNonce")
		})

		it("should Update Nonce on Signature verification with Valid nonce", async function () {
			const latestBlock = await getLatestBlockTime()
			const deadline = latestBlock + 300

			// Granting Roles
			await context.instantLayer.registerMultiAccount(context.multiAccount)

			await expect(context.multiAccount.connect(partyA1.getSigner).addAccount("testAccount")).not.to.revert(ethers) // here the party A Role is an EOA to create an Party A address
			accounts = await context.multiAccount.getAccounts(partyA1.address, 0, 100)

			const saltHex = "0xabc123"
			const salt = zeroPadValue(saltHex, 32)
			if (!/^0x[0-9a-fA-F]{64}$/.test(salt)) {
				throw new Error("Invalid bytes32 format")
			}

			const nonce = 1
			const opOpenALocal: InstantLayer.SignedOperationStruct = {
				accountSource: await context.multiAccount.getAddress(),
				signer: accounts[0].account,
				callData: openIntentCallData,
				nonce: nonce,
				salt: salt,
				deadline: deadline,
				signature: "0x",
			}

			const oldNonce = await context.instantLayer.nonces(opOpenALocal.signer)
			const hash = await context.instantLayer.getOperationHash(opOpenALocal)
			opOpenALocal.signature = await partyA1.sign(ethers.getBytes(hash))
			await context.controlFacet.grantRole(context.instantLayer, ethers.keccak256(toUtf8Bytes("INSTANT_LAYER_ROLE")))
			await expect(context.instantLayer.executeBatch([opOpenALocal])).not.to.revert(ethers)

			let newNonce = await context.instantLayer.nonces(opOpenALocal.signer)
			console.log("New Nonce:", newNonce)

			expect(newNonce).to.be.equal(nonce)
			expect(newNonce).to.be.equal(oldNonce + 1n)
		})

		// it("Should be failed when ", async () => {
		// 	// await context.instantLayer.registerPartyB(partyB1.getSigner)
		// 	// for(let i =0; i< signedOps.length; i++){
		// 	// 	let hash = await context.instantLayer.getOperationHash(signedOps[i])
		// 	// 	console.log("Hash Of Operation " + i +":",hash)
		// 	// }
		// 	// await expect(context.instantLayer.executeBatch(signedOps)).not.to.revert(ethers)
		// 	//TODO
		// })
	})

	describe("execute Template", async function () {
		let opOpenA1: InstantLayer.SignedOperationStruct, opOpenA2: InstantLayer.SignedOperationStruct
		let opLockB1: InstantLayer.SignedOperationStruct, opFillB1: InstantLayer.SignedOperationStruct
		let accounts: MultiAccount.AccountStruct[]

		beforeEach(async function () {
			const latestBlock = await getLatestBlockTime()
			const deadline = latestBlock + 300

			await expect(context.multiAccount.connect(partyA1.getSigner).addAccount("testAccount")).not.to.revert(ethers) // here the party A Role is an EOA to create an Party A address
			accounts = await context.multiAccount.getAccounts(partyA1.address, 0, 100)

			// await expect(context.collateral.connect(partyA1.getSigner).approve(context.common.diamondAddress, ethers.MaxUint256)).not.to.revert(ethers)
			await context.symmioPartyB.grantRole(ethers.keccak256(toUtf8Bytes("TRUSTED_ROLE")), partyA1.address)
			await expect(context.symmioPartyB.connect(partyA1.getSigner)._approve(context.collateral, e(30))).not.to.revert(ethers) // for symmoio contract

			await expect(context.collateral.connect(partyA1.getSigner).mint(accounts[0].account, e(30))).not.to.revert(ethers)
			await expect(context.collateralNL.connect(partyA1.getSigner).mint(accounts[0].account, e(30))).not.to.revert(ethers)
			await context.accountFacet.connect(partyA1.getSigner).depositFor(await context.collateral.getAddress(), accounts[0].account, e(20))
			await context.accountFacet.connect(partyA1.getSigner).depositFor(await context.collateralNL.getAddress(), accounts[0].account, e(20))

			opOpenA1 = {
				accountSource: await context.multiAccount.getAddress(),
				signer: accounts[0].account,
				callData: openIntentCallData,
				nonce: 0,
				salt: saltOpen1,
				deadline: deadline,
				signature: new Uint8Array([0x1, 0x2]),
			}

			opOpenA2 = {
				accountSource: await context.multiAccount.getAddress(),
				signer: accounts[0].account,
				callData: openIntentCallData,
				nonce: 0,
				salt: saltOpen2,
				deadline: deadline,
				signature: new Uint8Array([0x1, 0x2]),
			}

			opLockB1 = {
				accountSource: ethers.ZeroAddress,
				signer: await context.symmioPartyB.getAddress(),
				callData: lockIntentCallData,
				nonce: 0,
				salt: saltLock,
				deadline: deadline,
				signature: new Uint8Array([0x1, 0x2]),
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

			await context.instantLayer.addTemplate("MyTemp", ops)
		})

		it("Should be failed when Sender not have Operator Role ", async () => {
			await expect(context.instantLayer.connect(partyA1.getSigner).executeTemplate(1, [])).to.revert(ethers) // with "AccessControl" Error
		})

		it("Should be failed when Template does not exist", async () => {
			await expect(context.instantLayer.executeTemplate(99, [])).to.be.revertedWithCustomError(context.instantLayer, "InvalidTemplate").withArgs(99)
		})

		it("Should be failed when Template Inactive ", async () => {
			const tempID = (await context.instantLayer.getLastTemplateID()) - 1n
			await context.instantLayer.setTemplateActive(tempID, false)
			await expect(context.instantLayer.executeTemplate(tempID, [])).to.be.revertedWithCustomError(context.instantLayer, "TemplateNotActive")
		})

		it("Should be failed when Template Operation Input length Mismatch ", async () => {
			const opsLocal: InstantLayer.OperationStruct[] = [
				{
					sourceIndices: [],
					insertionPoints: [1],
				},
			]

			await context.instantLayer.addTemplate("MyTemp", opsLocal)

			const tempID = (await context.instantLayer.getLastTemplateID()) - 1n
			await expect(context.instantLayer.executeTemplate(tempID, [])).to.be.revertedWithCustomError(context.instantLayer, "ArrayLengthMismatch")
		})

		it("Should be failed when input Ops have passed the Deadline ", async () => {
			const deadline = await getLatestBlockTime()
			await ethers.provider.send("evm_setNextBlockTimestamp", [deadline + 24])
			await ethers.provider.send("evm_mine")

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

			let opsLocal: InstantLayer.OperationStruct[]
			opsLocal = [
				{
					sourceIndices: [],
					insertionPoints: [],
				},
			]

			await context.instantLayer.addTemplate("MyLocal", opsLocal)

			const tempID = (await context.instantLayer.getLastTemplateID()) - 1n
			await context.controlFacet.grantRole(context.instantLayer, ethers.keccak256(toUtf8Bytes("INSTANT_LAYER_ROLE")))
			await expect(context.instantLayer.executeTemplate(tempID, [opOpenALocal])).to.be.revertedWithCustomError(
				context.instantLayer,
				"DeadlineExpired",
			)
		})

		it("should Register Symmio PartyB when sending as PartyB", async function () {
			const deadline = (await getLatestBlockTime()) + 24
			let saltStr: string = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
			const opOpenALocal: InstantLayer.SignedOperationStruct = {
				accountSource: ZeroAddress,
				signer: partyA1.address,
				callData: "0x", // no matter
				nonce: 100, // no matter
				salt: saltStr, // no matter
				deadline: deadline,
				signature: "0x",
			}

			const tempID = (await context.instantLayer.getLastTemplateID()) - 1n
			await context.controlFacet.grantRole(context.instantLayer, ethers.keccak256(toUtf8Bytes("INSTANT_LAYER_ROLE")))
			await expect(context.instantLayer.executeTemplate(tempID, [opOpenALocal, opOpenA1, opLockB1, opFillB1])).to.be.revertedWithCustomError(
				context.instantLayer,
				"UnregisteredPartyB",
			)
		})

		it("should allow Sending Intents with a single Operation", async function () {
			const { instantLayer, collateralNL, partyAOpenFacet, partyBOpenFacet, symmioPartyB } = context
			const multiAccount = context.multiAccount

			// Granting Roles
			await context.instantLayer.registerPartyB(symmioPartyB) // Admin with SETTER Role, grants OPERATOR_ROLE to the us
			await context.instantLayer.registerMultiAccount(multiAccount) // Admin with SETTER Role, grants OPERATOR_ROLE to the user
			
			await context.symmioPartyB.setSigner(partyB1.getSigner) // Admin with SETTER Role
			
			await context.controlFacet.grantRole(context.instantLayer, ethers.keccak256(toUtf8Bytes("INSTANT_LAYER_ROLE"))) // to call Control faucet

			await context.controlFacet.setPartyBConfig(context.symmioPartyB.getAddress(), {
				// Admin with PARTY_B_MANAGER_ROLE
				isActive: true,
				lossCoverage: 0,
				oracleId: 1,
			})
			await context.controlFacet.setPartyBSupportedSymbolTypes(context.symmioPartyB.getAddress(), [0], [true])


			//Sign using getOperationHash
			const opOpenAHash1 = await instantLayer.getOperationHash(opOpenA1)
			const opOpenAHash2 = await instantLayer.getOperationHash(opOpenA2)
			const opLockBHash = await instantLayer.getOperationHash(opLockB1)
			const opFillBHash = await instantLayer.getOperationHash(opFillB1)

			opOpenA1.signature = await partyA1.sign(ethers.getBytes(opOpenAHash1))
			opOpenA2.signature = await partyA1.sign(ethers.getBytes(opOpenAHash2))
			opLockB1.signature = await partyB1.sign(ethers.getBytes(opLockBHash))
			opFillB1.signature = await partyB1.sign(ethers.getBytes(opFillBHash))
			console.log("OpenIntent Interface:", openIntentCallData)
			console.log("LockIntent Interface:", lockIntentCallData)
			console.log("FillIntent Interface:", fillIntentCallData)
			console.log("PartyA address:", partyA1.address)
			console.log("PartyA Account address:", accounts[0].account)
			console.log("PartyB1 address:", partyB1.address)
			console.log("Symmio PartyB address:", await context.symmioPartyB.getAddress())
			console.log("MultiAccount address:", await multiAccount.getAddress())
			console.log("Signature and length PartyA Open:", opOpenA1.signature.length, opOpenA1.signature)
			console.log("Signature and length PartyB Lock:", opLockB1.signature.length, opLockB1.signature)
			console.log("Signature and length PartyB Fill:", opFillB1.signature.length, opFillB1.signature)

			try {
				let recoveredAddress = ethers.verifyMessage(ethers.getBytes(opOpenAHash1), opOpenA1.signature)
				console.log("Party A Verifyed:", recoveredAddress === partyA1.address)
				console.log("signer vs Recovered", opOpenA1.signer, " vs ", recoveredAddress)
				recoveredAddress = ethers.verifyMessage(ethers.getBytes(opLockBHash), opLockB1.signature)
				console.log("Party B Verifyed:", recoveredAddress === opLockB1.signer)
				console.log("signer vs Recovered", opLockB1.signer, " vs ", recoveredAddress)
				recoveredAddress = ethers.verifyMessage(ethers.getBytes(opFillBHash), opFillB1.signature)
				console.log("Party B Fill Verifyed:", recoveredAddress === opFillB1.signer)
				console.log("signer vs Recovered", opFillB1.signer, " vs ", recoveredAddress)
			} catch (error) {
				console.error("Verification failed:", error)
				return false
			}


			const tempID = (await context.instantLayer.getLastTemplateID()) - 1n
			const signedOps: InstantLayer.SignedOperationStruct[] = [opOpenA1, opOpenA2, opLockB1, opFillB1]

			await expect(instantLayer.executeTemplate(tempID, signedOps)).not.to.be.revertedWithCustomError(context.instantLayer, "InvalidTemplate")
			// try {
			// 	await instantLayer.executeTemplate(tempID, signedOps)
			// } catch (error: unknown) {
			// 	console.log("Error Fetched:", error)
			// }

			let intent: OpenIntentStruct = await context.viewFacet.getOpenIntent(1)
			console.log("Intent Status:", intent.status == IntentStatus.FILLED?"Filled":intent.status)
			expect(intent.price).to.be.equal(request.price)
			expect(intent.tradeAgreements.quantity).to.be.equal(request.quantity)
		})

		it("should allow Sending Intent, Locking and Filling in a single batch Altogether", async function () {
			const { instantLayer, collateralNL, partyAOpenFacet, partyBOpenFacet, symmioPartyB } = context
			const multiAccount = context.multiAccount

			// Granting Roles
			await context.instantLayer.registerPartyB(symmioPartyB)
			await context.instantLayer.registerMultiAccount(multiAccount)

			await context.symmioPartyB.setSigner(partyB1.getSigner)
			// await context.symmioPartyB.setMulticastWhitelist(context.common.diamondAddress, true)

			await context.controlFacet.grantRole(context.instantLayer, ethers.keccak256(toUtf8Bytes("INSTANT_LAYER_ROLE")))
			await context.controlFacet.setPartyBConfig(context.symmioPartyB.getAddress(), {
				// Admin with PARTY_B_MANAGER_ROLE
				isActive: true,
				lossCoverage: 0,
				oracleId: 1,
			})
			await context.controlFacet.setPartyBSupportedSymbolTypes(context.symmioPartyB.getAddress(), [0], [true])

			//Sign using getOperationHash
			const opOpenAHash1 = await instantLayer.getOperationHash(opOpenA1)
			const opOpenAHash2 = await instantLayer.getOperationHash(opOpenA2)
			const opLockBHash = await instantLayer.getOperationHash(opLockB1)
			const opFillBHash = await instantLayer.getOperationHash(opFillB1)

			opOpenA1.signature = await partyA1.sign(ethers.getBytes(opOpenAHash1))
			opOpenA2.signature = await partyA1.sign(ethers.getBytes(opOpenAHash2))
			opLockB1.signature = await partyB1.sign(ethers.getBytes(opLockBHash))
			opFillB1.signature = await partyB1.sign(ethers.getBytes(opFillBHash))

			const tempID = (await context.instantLayer.getLastTemplateID()) - 1n

			//Execution
			const signedOps: InstantLayer.SignedOperationStruct[] = [opOpenA1, opOpenA2, opLockB1, opFillB1]
			await expect(instantLayer.executeTemplate(tempID, signedOps)).not.to.revert(ethers)
			// try {
			// 	await instantLayer.executeTemplate(tempID, signedOps) // Admin with OPERATOR Role
			// } catch (error: unknown) {
			// 	console.log("Error Fetched:", error)
			// }

			//Verification
			const lastID = await context.viewFacet.getLastOpenIntentId()
			expect(lastID).to.equal(2)
			let intent: OpenIntentStruct = await context.viewFacet.getOpenIntent(1)
			expect(intent.price).to.be.equal(request.price)
			expect(intent.tradeAgreements.quantity).to.be.equal(request.quantity)
			console.log("Intent Status", 1, intent.status == IntentStatus.FILLED ? "Filled" : intent.status)
			expect(intent.status).to.be.equal(IntentStatus.FILLED)
			const lastTradeId = await context.viewFacet.getLastTradeId()
			let trade: TradeStruct = await context.viewFacet.getTrade(lastTradeId)
			expect(trade.openIntentId).to.be.equal(intent.id)
		})

		it("should Fail Signature verification with Invalid Nonce", async function () {
			const latestBlock = await getLatestBlockTime()
			const deadline = latestBlock + 300

			// Granting Roles
			await context.instantLayer.registerMultiAccount(context.multiAccount)

			let saltStr: string = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
			if (!/^0x[0-9a-fA-F]{64}$/.test(saltStr)) {
				throw new Error("Invalid bytes32 format")
			}

			const opOpenALocal: InstantLayer.SignedOperationStruct = {
				accountSource: await context.multiAccount.getAddress(),
				signer: accounts[0].account,
				callData: openIntentCallData,
				nonce: 2,
				salt: saltStr,
				deadline: deadline,
				signature: "0x",
			}

			const hash = await context.instantLayer.getOperationHash(opOpenALocal)
			opOpenALocal.signature = await partyA1.sign(ethers.getBytes(hash))

			await context.controlFacet.grantRole(context.instantLayer, ethers.keccak256(toUtf8Bytes("INSTANT_LAYER_ROLE")))

			await expect(context.instantLayer.executeBatch([opOpenALocal])).to.be.revertedWithCustomError(context.instantLayer, "InvalidNonce")
		})

		it("should Update Nonce on Signature verification with Valid nonce", async function () {
			const latestBlock = await getLatestBlockTime()
			const deadline = latestBlock + 300

			// Granting Roles
			await context.instantLayer.registerMultiAccount(context.multiAccount)

			await expect(context.multiAccount.connect(partyA1.getSigner).addAccount("testAccount")).not.to.revert(ethers) // here the party A Role is an EOA to create an Party A address
			accounts = await context.multiAccount.getAccounts(partyA1.address, 0, 100)

			const saltHex = "0xabc123"
			const salt = zeroPadValue(saltHex, 32)
			if (!/^0x[0-9a-fA-F]{64}$/.test(salt)) {
				throw new Error("Invalid bytes32 format")
			}

			const nonce = 1
			const opOpenALocal: InstantLayer.SignedOperationStruct = {
				accountSource: await context.multiAccount.getAddress(),
				signer: accounts[0].account,
				callData: openIntentCallData,
				nonce: nonce,
				salt: salt,
				deadline: deadline,
				signature: "0x",
			}

			const oldNonce = await context.instantLayer.nonces(opOpenALocal.signer)
			const hash = await context.instantLayer.getOperationHash(opOpenALocal)
			opOpenALocal.signature = await partyA1.sign(ethers.getBytes(hash))
			await context.controlFacet.grantRole(context.instantLayer, ethers.keccak256(toUtf8Bytes("INSTANT_LAYER_ROLE")))
			await expect(context.instantLayer.executeBatch([opOpenALocal])).not.to.revert(ethers)

			let newNonce = await context.instantLayer.nonces(opOpenALocal.signer)
			console.log("New Nonce:", newNonce)

			expect(newNonce).to.be.equal(nonce)
			expect(newNonce).to.be.equal(oldNonce + 1n)
		})

		// it("Should be failed when ", async () => {
		// 	// await context.instantLayer.registerPartyB(partyB1.getSigner)
		// 	// for(let i =0; i< signedOps.length; i++){
		// 	// 	let hash = await context.instantLayer.getOperationHash(signedOps[i])
		// 	// 	console.log("Hash Of Operation " + i +":",hash)
		// 	// }
		// 	// await expect(context.instantLayer.executeBatch(signedOps)).not.to.revert(ethers)
		// 	//TODO
		// })
	})
}
