import { Builder } from "builder-pattern"
import { ZeroAddress } from "ethers"
import { SignedSimpleActionIntentStruct } from "../../../types/contracts/interfaces/ISymmio"

const defaultSignedOpenIntent: SignedSimpleActionIntentStruct = {
	signer: ZeroAddress,
	intentId: 1,
	deadline: 0,
	salt: 0,
}

export const signedSimpleActionIntentBuilder = () => Builder(defaultSignedOpenIntent)
