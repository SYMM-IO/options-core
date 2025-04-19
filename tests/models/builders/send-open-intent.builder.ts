import { Builder } from "builder-pattern"
import { AddressLike, BigNumberish, BytesLike, encodeBytes32String } from "ethers"
import { ExerciseFeeStruct } from "../../../types/contracts/facets/InstantActionsOpen/IInstantActionsOpenFacet"

export interface OpenIntent {
	partyBsWhiteList: AddressLike[]
	symbolId: BigNumberish
	price: BigNumberish
	quantity: BigNumberish
	strikePrice: BigNumberish
	expirationTimestamp: BigNumberish
	mm: BigNumberish
	deadline: BigNumberish
	tradeSide: BigNumberish
	marginType: BigNumberish
	exerciseFee: ExerciseFeeStruct
	feeToken: AddressLike
	affiliate: AddressLike
	userData: BytesLike
}

const openIntentRequest: OpenIntent = {
	partyBsWhiteList: [""],
	symbolId: 0,
	price: 0,
	quantity: 0,
	strikePrice: 0,
	expirationTimestamp: 0,
	exerciseFee: {
		cap: 0,
		rate: 0,
	},
	deadline: 0,
	marginType: 0,
	mm: 0,
	tradeSide: 0,
	feeToken: "",
	affiliate: "",
	userData: encodeBytes32String("x"),
}

export const openIntentRequestBuilder = () => Builder(openIntentRequest)
