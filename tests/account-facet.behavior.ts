import {loadFixture, time} from "@nomicfoundation/hardhat-network-helpers"
import {ethers} from "hardhat"
import {expect} from "chai"
import { initializeTestFixture, RunContext } from "../fixtures/initialize-test.fixture"

export function shouldBehaveLikeAccountFacet(): void {
	let context: RunContext

	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)
	})

	describe("Deposit", async function () {
		it("Should deposit collateral", async function () {
            //
		})
	})
}