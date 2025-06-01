import { Builder } from "builder-pattern"
import { keccak256, toUtf8Bytes, ZeroAddress } from "ethers"
import { SignedFillIntentByIdStruct } from "../../../types/contracts/interfaces/ISymmio"
import { e } from "../../../utils/e"

const defaultSignedFillIntent: SignedFillIntentByIdStruct = {
	partyB: ZeroAddress,
	deadline: 0,
	intentId: 1,
	price: 1,
	quantity: e(1),
	salt: keccak256(toUtf8Bytes("")),
}

export const SignedFillIntentByIdBuilder = () => Builder(defaultSignedFillIntent)
