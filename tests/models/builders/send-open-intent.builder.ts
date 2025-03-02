import { Builder } from "builder-pattern"
import { AddressLike, BigNumberish } from "ethers"

export interface OpenIntent {
	partyBsWhiteList: AddressLike[]
	symbolId: BigNumberish
	price: BigNumberish
	quantity: BigNumberish
	strikePrice: BigNumberish
	expirationTimestamp: BigNumberish
	exerciseFee: { rate: BigNumberish; cap: BigNumberish }
	deadline: BigNumberish
	affiliate: AddressLike
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
	affiliate: "",
}

export const openIntentRequestBuilder = () => Builder(openIntentRequest)
