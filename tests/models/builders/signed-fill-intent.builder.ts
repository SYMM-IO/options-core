import { Builder } from "builder-pattern"
import { keccak256, toUtf8Bytes, ZeroAddress } from "ethers"
import { SignedFillIntentStruct } from "../../../types/contracts/interfaces/ISymmio"

const defaultSignedFillIntent: SignedFillIntentStruct = {
	partyB: ZeroAddress,
	intentHash: keccak256(toUtf8Bytes("intent")),
	price: 0,
	quantity: 0,
	deadline: 0,
	salt: 0,
	marginType: 0,
}

export const signedFillIntentBuilder = () => Builder(defaultSignedFillIntent)
