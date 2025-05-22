import { ethers, keccak256, toUtf8Bytes } from "ethers"
import {
	SignedCloseIntentStruct,
	SignedFillIntentByIdStruct,
	SignedFillIntentStruct,
	SignedOpenIntentStruct,
	SignedSimpleActionIntentStruct,
} from "../../types/contracts/interfaces/ISymmio"

// Prefixes
const PREFIX = {
	Open: keccak256(toUtf8Bytes("SymmioOpenIntent_v1")),
	Close: keccak256(toUtf8Bytes("SymmioCloseIntent_v1")),
	FillOpen: keccak256(toUtf8Bytes("SymmioFillOpenIntent_v1")),
	FillOpenById: keccak256(toUtf8Bytes("SymmioFillOpenIntentById_v1")),
	FillClose: keccak256(toUtf8Bytes("SymmioFillCloseIntent_v1")),
	FillCloseById: keccak256(toUtf8Bytes("SymmioFillCloseIntentById_v1")),
	CancelOpen: keccak256(toUtf8Bytes("SymmioCancelOpenIntent_v1")),
	AcceptCancelOpen: keccak256(toUtf8Bytes("SymmioAcceptCancelOpenIntent_v1")),
	CancelClose: keccak256(toUtf8Bytes("SymmioCancelCloseIntent_v1")),
	AcceptCancelClose: keccak256(toUtf8Bytes("SymmioAcceptCancelCloseIntent_v1")),
	Lock: keccak256(toUtf8Bytes("SymmioLockIntent_v1")),
	Unlock: keccak256(toUtf8Bytes("SymmioUnlockIntent_v1")),
}

const abiCoder = new ethers.AbiCoder()

export function hashSignedOpenIntent(req: SignedOpenIntentStruct, chainId: number, diamondAddress: string): string {
	return keccak256(
		abiCoder.encode(
			["uint256", "address", "bytes32", "address", "address", "uint256", "bytes", "uint8", "uint256", "address", "address", "uint256"],
			[
				chainId,
				diamondAddress,
				PREFIX.Open,
				req.partyA,
				req.partyB,
				req.price,
				abiCoder.encode(
					["uint256", "uint256", "uint256", "uint256", "uint256", "uint256", "uint256"],
					[req.symbolId, req.quantity, req.strikePrice, req.expirationTimestamp, req.mm, req.exerciseFee.rate, req.exerciseFee.cap],
				),
				req.marginType,
				req.deadline,
				req.feeToken,
				req.affiliate,
				req.salt,
			],
		),
	)
}

export function hashSignedCloseIntent(req: SignedCloseIntentStruct, chainId: number, diamondAddress: string): string {
	return keccak256(
		abiCoder.encode(
			["uint256", "address", "bytes32", "address", "uint256", "uint256", "uint256", "uint256", "uint256"],
			[chainId, diamondAddress, PREFIX.Close, req.partyA, req.tradeId, req.price, req.quantity, req.deadline, req.salt],
		),
	)
}

export function hashSignedFillOpenIntent(req: SignedFillIntentStruct, chainId: number, diamondAddress: string): string {
	return keccak256(
		abiCoder.encode(
			["uint256", "address", "bytes32", "address", "bytes32", "uint256", "uint256", "uint256", "uint256"],
			[chainId, diamondAddress, PREFIX.FillOpen, req.partyB, req.intentHash, req.price, req.quantity, req.deadline, req.salt],
		),
	)
}

export function hashSignedFillOpenIntentById(req: SignedFillIntentByIdStruct, chainId: number, diamondAddress: string): string {
	return keccak256(
		abiCoder.encode(
			["uint256", "address", "bytes32", "address", "uint256", "uint256", "uint256", "uint256", "uint256"],
			[chainId, diamondAddress, PREFIX.FillOpenById, req.partyB, req.intentId, req.price, req.quantity, req.deadline, req.salt],
		),
	)
}

export function hashSignedFillCloseIntent(req: SignedFillIntentStruct, chainId: number, diamondAddress: string): string {
	return keccak256(
		abiCoder.encode(
			["uint256", "address", "bytes32", "address", "bytes32", "uint256", "uint256", "uint256", "uint256"],
			[chainId, diamondAddress, PREFIX.FillClose, req.partyB, req.intentHash, req.price, req.quantity, req.deadline, req.salt],
		),
	)
}

export function hashSignedFillCloseIntentById(req: SignedFillIntentByIdStruct, chainId: number, diamondAddress: string): string {
	return keccak256(
		abiCoder.encode(
			["uint256", "address", "bytes32", "address", "uint256", "uint256", "uint256", "uint256", "uint256"],
			[chainId, diamondAddress, PREFIX.FillCloseById, req.partyB, req.intentId, req.price, req.quantity, req.deadline, req.salt],
		),
	)
}

export function hashSignedCancelOpenIntent(req: SignedSimpleActionIntentStruct, chainId: number, diamondAddress: string): string {
	return keccak256(
		new ethers.AbiCoder().encode(
			["uint256", "address", "bytes32", "address", "uint256", "uint256", "uint256"],
			[chainId, diamondAddress, PREFIX.CancelOpen, req.signer, req.intentId, req.deadline, req.salt],
		),
	)
}

export function hashSignedAcceptCancelOpenIntent(req: SignedSimpleActionIntentStruct, chainId: number, diamondAddress: string): string {
	return keccak256(
		new ethers.AbiCoder().encode(
			["uint256", "address", "bytes32", "address", "uint256", "uint256", "uint256"],
			[chainId, diamondAddress, PREFIX.AcceptCancelOpen, req.signer, req.intentId, req.deadline, req.salt],
		),
	)
}

export function hashSignedSimpleActionIntent(
	req: SignedSimpleActionIntentStruct,
	prefix: keyof typeof PREFIX,
	chainId: number,
	diamondAddress: string,
): string {
	return keccak256(
		abiCoder.encode(
			["uint256", "address", "bytes32", "address", "uint256", "uint256", "uint256"],
			[chainId, diamondAddress, PREFIX[prefix], req.signer, req.intentId, req.deadline, req.salt],
		),
	)
}
