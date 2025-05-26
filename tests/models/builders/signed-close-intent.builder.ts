import { Builder } from "builder-pattern"
import { keccak256, toUtf8Bytes, ZeroAddress } from "ethers"
import { SignedCloseIntentStruct, SignedFillIntentByIdStruct } from "../../../types/contracts/interfaces/ISymmio"

const defaultSignedCloseIntent: SignedCloseIntentStruct = {
	partyA: ZeroAddress,
	tradeId: "0",
	deadline: 0,
	price: "0",
	quantity: "0",
	salt: keccak256(toUtf8Bytes("")),
}

export const SignedCloseIntentBuilder = () => Builder(defaultSignedCloseIntent)
