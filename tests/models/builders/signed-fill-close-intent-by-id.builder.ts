import { Builder } from "builder-pattern"
import { keccak256, toUtf8Bytes, ZeroAddress } from "ethers"
import { SignedFillIntentByIdStruct } from "../../../types/contracts/interfaces/ISymmio"

const defaultSignedFillIntent: SignedFillIntentByIdStruct = {
	partyB: ZeroAddress,
	deadline: 0,
	intentId: 1,
	price: "0",
	quantity: "0",
	salt: keccak256(toUtf8Bytes("")),
}

export const SignedFillIntentByIdBuilder = () => Builder(defaultSignedFillIntent)
