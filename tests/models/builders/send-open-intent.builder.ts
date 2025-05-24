import { Builder } from "builder-pattern"
import { AddressLike, BigNumberish, BytesLike, encodeBytes32String, ZeroAddress } from "ethers"
import { ExerciseFeeStruct } from "../../../types/contracts/facets/InstantActionsOpen/IInstantActionsOpenFacet"
import { e } from "../../../utils/e"

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
	partyBsWhiteList: [ZeroAddress],
	symbolId: 1,
	price: 1,
	quantity: e(1),
	strikePrice: 1,
	expirationTimestamp: 0,
	exerciseFee: {
		cap: e(1),
		rate: 0,
	},
	deadline: 0,
	marginType: 0,
	mm: 0,
	tradeSide: 0,
	feeToken: "",
	affiliate: ZeroAddress,
	userData: encodeBytes32String("0"),
}

export const openIntentRequestBuilder = () => Builder(openIntentRequest)
