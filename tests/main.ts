import { TestModeEnum } from "../common/test-mode.enum.js"
import pkg from "../package.json" with { type: "json" }
import { shouldBehaveLikeAccountFacet } from "./account-facet.behavior.js"
import { shouldBehaveLikeForceActionFacet } from "./force-action.behavior.js"
import { shouldBehaveLikeLibCloseIntent } from "./lib-closeIntent.behavior.js"
import { shouldBehaveLikePartyACloseFacet } from "./partyA-close-facet.behavior.js"
import { shouldBehaveLikePartyAOpenFacet } from "./partyA-open-facet.behavior.js"
import { shouldBehaveLikePartyBCloseFacet } from "./partyB-close-facet.behavior.js"
import { shouldBehaveLikePartyBOpenFacet } from "./partyB-open-facet.behavior.js"
import { shouldBehaveLikeSettlementFacet } from "./trade-settlement.js"
import { shouldBehaveLikeBridgeFacet } from "./bridge-facet.behavior.js"
import { shouldBehaveLikeInstantLayer } from "./helpers/instant-layer.behavior.js"
import { shouldBehaveLikeMultiAccount } from "./helpers/multi-account.behavior.js"
import { shouldBehaveLikeSymmioPartyB } from "./helpers/symmio-partyb.behavior.js"
import { shouldBehaveLikeClearingHouseFacet } from "./clearing-house.js"
import { shouldBehaveLikeControlFacet } from "./control-facet.behavior.js"
import { shouldBehaveLikeTradeNFT } from "./helpers/trade-nft.behavior.js"
import { shouldGuardSymmioPartyBAgainstReentrancy } from "./helpers/symmio-partyb-reentrancy.behavior.js"
import { shouldBehaveLikeSignatureVerifier } from "./helpers/signature-verifier.behavior.js"
import { shouldShareOneChainWithTasks } from "./helpers/connection.behavior.js"

const { name, version } = pkg

describe(`${name}-v${version}`, () => {
	if (process.env.TEST_MODE === TestModeEnum.UNIT_TEST) {
		describe("Hardhat connection", async function () {
			shouldShareOneChainWithTasks()
		})

		describe("Facets_Accounts", async function () {
			shouldBehaveLikeAccountFacet()
		})

		describe("Facets_ControlFacet", async function () {
			shouldBehaveLikeControlFacet()
		})

		describe("Facets_PartyAOpenFacet", async function () {
			shouldBehaveLikePartyAOpenFacet()
		})

		describe("Facets_PartyBOpenFacet", async function () {
			shouldBehaveLikePartyBOpenFacet()
		})

		describe("Facets_PartyACloseFacet", async function () {
			shouldBehaveLikePartyACloseFacet()
		})

		describe("Libraries_LibCloseIntent", async function () {
			shouldBehaveLikeLibCloseIntent()
		})

		describe("Facets_PartyBCloseFacet", async function () {
			shouldBehaveLikePartyBCloseFacet()
		})

		describe("Facets_Settlement", async function () {
			shouldBehaveLikeSettlementFacet()
		})

		describe("Facets_ForceActions", async function () {
			shouldBehaveLikeForceActionFacet()
		})

		describe("Facet_BridgeFacet", async function () {
			shouldBehaveLikeBridgeFacet()
		})

		describe("Instant Layer", async function () {
			shouldBehaveLikeInstantLayer()
		})

		describe("Multi Account", async function () {
			shouldBehaveLikeMultiAccount()
		})

		describe("Symmio PartyB", async function () {
			shouldBehaveLikeSymmioPartyB()
		})

		describe("Symmio Clearing House", async function () {
			shouldBehaveLikeClearingHouseFacet()
		})

		describe("Trade NFT", async function () {
			shouldBehaveLikeTradeNFT()
		})

		describe("Symmio PartyB reentrancy", async function () {
			shouldGuardSymmioPartyBAgainstReentrancy()
		})

		describe("Signature Verifier", async function () {
			shouldBehaveLikeSignatureVerifier()
		})
	} else {
		throw new Error(`Invalid TEST_MODE property. Should be one of: ${Object.keys(TestModeEnum).join(", ")}`)
	}
})
