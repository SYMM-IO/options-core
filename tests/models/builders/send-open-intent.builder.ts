import { Builder } from "builder-pattern"
import { AddressLike, BigNumberish, BytesLike, encodeBytes32String, ZeroAddress } from "ethers"
import { e } from "../../../utils/e"
import { ExerciseFeeStruct, FeeStruct } from "../../../types/contracts/interfaces/ISymmio"
import { FeeStructureStruct } from "../../../types/contracts/facets/View/IViewFacet"
import { MarginType, TradeSide } from "../../option-enums"

export interface OpenIntent {
	partyBsWhiteList: AddressLike[]
	symbolId: BigNumberish
	price: BigNumberish
	quantity: BigNumberish
	strikePrice: BigNumberish
	expirationTimestamp: BigNumberish
	mm: BigNumberish
	tradeSide: BigNumberish
	marginType: BigNumberish
	exerciseFee: ExerciseFeeStruct
	solverFee: FeeStruct
	deadline: BigNumberish
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
	mm: e(1),
	tradeSide: TradeSide.BUY,
	marginType: MarginType.ISOLATED,
	exerciseFee: {
		cap: e(1),
		rate: 0,
	},
	solverFee: {
		openFee: 1,
		closeFee: 1,
	},
	deadline: 0,
	feeToken: ZeroAddress,
	affiliate: ZeroAddress,
	userData: encodeBytes32String("0"),
}

export const openIntentRequestBuilder = () => Builder(openIntentRequest)
