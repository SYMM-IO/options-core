import { Builder } from "builder-pattern"
import { keccak256, toUtf8Bytes, ZeroAddress } from "ethers"
import { SignedFillIntentStruct } from "../../../types/contracts/interfaces/ISymmio"
import { e } from "../../../utils/e"

const defaultSignedFillIntent: SignedFillIntentStruct = {
	partyB: ZeroAddress,
	intentHash: keccak256(toUtf8Bytes("")),
	price: 1,
	quantity: e(1),
	deadline: 0,
	salt: 0,
}

export const signedFillIntentBuilder = () => Builder(defaultSignedFillIntent)
