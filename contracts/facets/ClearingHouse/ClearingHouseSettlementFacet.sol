// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license

///////////////////////////////////////////////////////////////////////////
// @author droplet ////////////////////////////////////////////////////////
///////////////////////// Code Flow ///////////////////////////////////////
///////////////////////////////////////////////////////////////////////////
// 1: Flagging the appropriate Party //////////////////////////////////////
// 2: Allocating Reserve if Available/Needed //////////////////////////////
// --NOTE if Allocation Resolves the Solvency Moves to stage 7 ////////////
// 3: Liquidating the appropriate Party ///////////////////////////////////
// 4: Closing the Trades -> CloseIntents -> OpenIntents ///////////////////
// 5: ConfiscateWithdrawal the party
// 5: Confiscate the Party Balance as needed //////////////////////////////
// 6: Distributing the Collateral /////////////////////////////////////////
// 7: Unflag Party ////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////

pragma solidity >=0.8.19;

import { LibAccessibility } from "../../libraries/core/LibAccessibility.sol";
import { LibParty } from "../../libraries/models/LibParty.sol";

import { Pausable } from "../../utils/Pausable.sol";
import { Accessibility } from "../../utils/Accessibility.sol";

import { IClearingHouseEvents } from "./IClearingHouseEvents.sol";
import { LibClearingHouse } from "../../libraries/core/LibClearingHouse.sol";

import { MarginType } from "../../types/BaseTypes.sol";

contract ClearingHouseSettlementFacet is Pausable, Accessibility, IClearingHouseEvents {
	using LibParty for address;
	function confiscate(
		uint256 liquidationId,
		address party,
		address[] calldata counterParties,
		uint256[] calldata amounts,
		MarginType marginType
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.confiscate(liquidationId, party, counterParties, amounts, marginType);
		emit Confiscate(msg.sender, party, counterParties, amounts, liquidationId, marginType);
	}

	function confiscateWithdrawal(uint256 withdrawId) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.confiscateWithdrawal(withdrawId);
		emit ConfiscateWithdrawal(msg.sender, withdrawId);
	}

	function distributeCollateral(
		uint256 liquidationId,
		address partyB,
		address collateral,
		MarginType marginType,
		address[] calldata partyAs,
		uint256[] calldata amounts
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.distributeCollateral(liquidationId, partyB, collateral, marginType, partyAs, amounts);
		emit DistributeCollateral(msg.sender, partyB, collateral, liquidationId, partyAs, amounts);
	}

	function closeTrades(
		uint256 liquidationId,
		uint256[] calldata tradeIds,
		uint256[] calldata prices
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.closeTrades(liquidationId, tradeIds, prices);
		emit CloseTradesForLiquidation(msg.sender, liquidationId, tradeIds, prices);
	}

	function allocateFromReserveToCross(
		address party,
		address counterParty,
		address collateral,
		uint256 amount
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.allocateFromReserveToCross(party, counterParty, collateral, amount);
		emit AllocateFromReserveToCross(msg.sender, party, counterParty, collateral, amount);
	}

	function confiscate(
		uint256 liquidationId,
		address party,
		uint256 partyBucketId,
		address[] calldata counterParties,
		uint256[] calldata counterPartyBucketIds,
		uint256[] calldata amounts,
		MarginType marginType
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.confiscate(liquidationId, party, partyBucketId, counterParties, counterPartyBucketIds, amounts, marginType);
		emit Confiscate(msg.sender, party, counterParties, amounts, liquidationId, marginType);
	}

	function distributeCollateral(
		uint256 liquidationId,
		address partyB,
		uint256 partyBBucketId,
		address collateral,
		MarginType marginType,
		address[] calldata partyAs,
		uint256[] calldata partyABucketIds,
		uint256[] calldata amounts
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.distributeCollateral(liquidationId, partyB, partyBBucketId, collateral, marginType, partyAs, partyABucketIds, amounts);
		emit DistributeCollateral(msg.sender, partyB, collateral, liquidationId, partyAs, amounts);
	}

	function allocateFromReserveToCross(
		address party,
		uint256 partyBucketId,
		address counterParty,
		uint256 counterPartyBucketId,
		address collateral,
		uint256 amount
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.allocateFromReserveToCross(party, partyBucketId, counterParty, counterPartyBucketId, collateral, amount);
		emit AllocateFromReserveToCross(msg.sender, party, counterParty, collateral, amount);
	}
}
