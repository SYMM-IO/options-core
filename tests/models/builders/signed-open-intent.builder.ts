import { Builder } from "builder-pattern"
import { encodeBytes32String, ZeroAddress } from "ethers"
import { SignedOpenIntentStruct } from "../../../types/contracts/interfaces/ISymmio"

const defaultSignedOpenIntent: SignedOpenIntentStruct = {
	partyA: ZeroAddress,
	partyB: ZeroAddress,
	symbolId: 0,
	price: 0,
	quantity: 0,
	strikePrice: 0,
	expirationTimestamp: 0,
	mm: 0,
	tradeSide: 0,
	marginType: 0,
	exerciseFee: {
		cap: 0,
		rate: 0,
	},
	deadline: 0,
	affiliate: ZeroAddress,
	feeToken: ZeroAddress,
	userData: "0x",
	salt: 0,
}

export const signedOpenIntentBuilder = () => Builder(defaultSignedOpenIntent)
