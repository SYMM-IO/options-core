import { TestModeEnum } from "../common/test-mode.enum"
import { name, version } from "../package.json"
import { shouldBehaveLikeAccountFacet } from "./account-facet.behavior"
import { shouldBehaveLikeForceActionFacet } from "./force-action.behavior"
import { shouldBehaveLikeLibCloseIntent } from "./lib-closeIntent.behavior"
import { shouldBehaveLikePartyACloseFacet } from "./partyA-close-facet.behavior"
import { shouldBehaveLikePartyAOpenFacet } from "./partyA-open-facet.behavior"
import { shouldBehaveLikePartyBCloseFacet } from "./partyB-close-facet.behavior"
import { shouldBehaveLikePartyBOpenFacet } from "./partyB-open-facet.behavior"
import { shouldBehaveLikeSettlementFacet } from "./trade-settlement"
import { shouldBehaveLikeBridgeFacet } from "./bridge-facet.behavior"
import { shouldBehaveLikeInstantLayer } from "./helpers/instant-layer.behavior"
import { shouldBehaveLikeMultiAccount } from "./helpers/multi-account.behavior"
import { shouldBehaveLikeSymmioPartyB } from "./helpers/symmio-partyb.behavior"
import { shouldBehaveLikeClearingHouseFacet } from "./clearing-house"

describe(`${name}-v${version}`, () => {
	if (process.env.TEST_MODE === TestModeEnum.UNIT_TEST) {
		describe("Facets_Accounts", async function () {
			shouldBehaveLikeAccountFacet()
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

		describe.only("Facets_PartyBCloseFacet", async function () {
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
	} else {
		throw new Error(`Invalid TEST_MODE property. Should be one of: ${Object.keys(TestModeEnum).join(", ")}`)
	}
})
