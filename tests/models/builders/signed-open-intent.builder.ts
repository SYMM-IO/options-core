import { Builder } from "builder-pattern"
import { encodeBytes32String, ZeroAddress } from "ethers"
import { SignedOpenIntentStruct } from "../../../types/contracts/interfaces/ISymmio"
import { e } from "../../../utils/e"

const defaultSignedOpenIntent: SignedOpenIntentStruct = {
	partyA: ZeroAddress,
	partyB: ZeroAddress,
	symbolId: 1,
	price: 1,
	quantity: e(1),
	strikePrice: 0,
	expirationTimestamp: 0,
	mm: 0,
	tradeSide: 0,
	marginType: 0,
	exerciseFee: {
		cap: e(1),
		rate: 0,
	},
	deadline: 0,
	affiliate: ZeroAddress,
	feeToken: ZeroAddress,
	userData: "0x",
	salt: 0,
}

export const signedOpenIntentBuilder = () => Builder(defaultSignedOpenIntent)
