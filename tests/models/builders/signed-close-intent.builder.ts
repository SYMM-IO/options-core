import { Builder } from "builder-pattern"
import { keccak256, toUtf8Bytes, ZeroAddress } from "ethers"
import { SignedCloseIntentStruct, SignedFillIntentByIdStruct } from "../../../types/contracts/interfaces/ISymmio"
import { e } from "../../../utils/e"

const defaultSignedCloseIntent: SignedCloseIntentStruct = {
	partyA: ZeroAddress,
	tradeId: 1,
	deadline: 0,
	price: 1,
	quantity: e(1),
	salt: keccak256(toUtf8Bytes("")),
}

export const SignedCloseIntentBuilder = () => Builder(defaultSignedCloseIntent)
