import { TestModeEnum } from "../common/test-mode.enum"
import { name, version } from "../package.json"
import { shouldBehaveLikeAccountFacet } from "./account-facet.behavior"
import { shouldBehaveLikePartyACloseFacet } from "./partyA-close-facet.behavior"
import { shouldBehaveLikePartyAOpenFacet } from "./partyA-open-facet.behavior copy"
import { shouldBehaveLikePartyBFacet } from "./partyB-facet.behavior"

describe(`${name}-v${version}`, () => {
	if (process.env.TEST_MODE === TestModeEnum.UNIT_TEST) {
		// describe("Facets_Accounts", async function () {
		// 	shouldBehaveLikeAccountFacet()
		// })

		// describe("Facets_PartyAOpenFacet", async function () {
		// 	shouldBehaveLikePartyAOpenFacet()
		// })
		
		describe("Facets_PartyACloseFacet", async function () {
			shouldBehaveLikePartyACloseFacet()
		})

		// describe("Facets_PartyB", async function () {
		// 	shouldBehaveLikePartyBFacet()
		// })
	} else {
		throw new Error(`Invalid TEST_MODE property. Should be one of: ${Object.keys(TestModeEnum).join(", ")}`)
	}
})
