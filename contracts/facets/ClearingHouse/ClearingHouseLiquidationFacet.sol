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

contract ClearingHouseLiquidationFacet is Pausable, Accessibility, IClearingHouseEvents {
	using LibParty for address;
	function flagIsolatedPartyBLiquidation(
		address partyB,
		address collateral
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.flagIsolatedPartyBLiquidation(partyB, collateral);
		emit FlagIsolatedPartyBLiquidation(msg.sender, partyB, collateral);
	}

	function unflagIsolatedPartyBLiquidation(
		address partyB,
		address collateral
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.unflagIsolatedPartyBLiquidation(partyB, collateral);
		emit UnflagIsolatedPartyBLiquidation(msg.sender, partyB, collateral);
	}

	function liquidateIsolatedPartyB(
		address partyB,
		address collateral,
		int256 upnl,
		uint256 collateralPrice
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.liquidateIsolatedPartyB(partyB, collateral, upnl, collateralPrice);
		emit LiquidateIsolatedPartyB(msg.sender, partyB, collateral, partyB.balanceOf(collateral).isolatedBalance, upnl, collateralPrice);
	}

	function flagCrossPartyBLiquidation(
		address partyB,
		address partyA,
		address collateral
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.flagCrossPartyBLiquidation(partyB, partyA, collateral);
		emit FlagCrossPartyBLiquidation(msg.sender, partyB, partyA, collateral);
	}

	function unflagCrossPartyBLiquidation(
		address partyB,
		address partyA,
		address collateral
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.unflagCrossPartyBLiquidation(partyB, partyA, collateral);
		emit UnflagCrossPartyBLiquidation(msg.sender, partyB, partyA, collateral);
	}

	function liquidateCrossPartyB(
		address partyB,
		address partyA,
		address collateral,
		int256 upnl,
		uint256 collateralPrice
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.liquidateCrossPartyB(partyB, partyA, collateral, upnl, collateralPrice);
		emit LiquidateCrossPartyB(msg.sender, partyB, partyA, collateral, upnl, collateralPrice);
	}

	function flagPartyALiquidation(
		address partyA,
		address partyB,
		address collateral
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.flagPartyALiquidation(partyA, partyB, collateral);
		emit FlagPartyALiquidation(msg.sender, partyA, partyB, collateral);
	}

	function unflagPartyALiquidation(
		address partyA,
		address partyB,
		address collateral
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.unflagPartyALiquidation(partyA, partyB, collateral);
		emit UnflagPartyALiquidation(msg.sender, partyA, partyB, collateral);
	}

	function liquidateCrossPartyA(
		uint256 liquidationId,
		address partyA,
		address partyB,
		address collateral,
		int256 upnl,
		uint256 collateralPrice
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.validateLiquidationMetadata(liquidationId, partyA, partyB, collateral);
		LibClearingHouse.liquidateCrossPartyA(liquidationId, upnl, collateralPrice);
		emit LiquidateCrossPartyA(msg.sender, liquidationId, partyA, partyB, collateral, upnl, collateralPrice);
	}

	function flagCrossPartyBLiquidation(
		address partyB,
		uint256 partyBBucketId,
		address partyA,
		uint256 partyABucketId,
		address collateral
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.flagCrossPartyBLiquidation(partyB, partyBBucketId, partyA, partyABucketId, collateral);
		emit FlagCrossPartyBLiquidation(msg.sender, partyB, partyA, collateral);
	}

	function unflagCrossPartyBLiquidation(
		address partyB,
		uint256 partyBBucketId,
		address partyA,
		uint256 partyABucketId,
		address collateral
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.unflagCrossPartyBLiquidation(partyB, partyBBucketId, partyA, partyABucketId, collateral);
		emit UnflagCrossPartyBLiquidation(msg.sender, partyB, partyA, collateral);
	}

	function liquidateCrossPartyB(
		address partyB,
		uint256 partyBBucketId,
		address partyA,
		uint256 partyABucketId,
		address collateral,
		int256 upnl,
		uint256 collateralPrice
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.liquidateCrossPartyB(partyB, partyBBucketId, partyA, partyABucketId, collateral, upnl, collateralPrice);
		emit LiquidateCrossPartyB(msg.sender, partyB, partyA, collateral, upnl, collateralPrice);
	}

	function flagPartyALiquidation(
		address partyA,
		uint256 partyABucketId,
		address partyB,
		uint256 partyBBucketId,
		address collateral
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.flagPartyALiquidation(partyA, partyABucketId, partyB, partyBBucketId, collateral);
		emit FlagPartyALiquidation(msg.sender, partyA, partyB, collateral);
	}

	function unflagPartyALiquidation(
		address partyA,
		uint256 partyABucketId,
		address partyB,
		uint256 partyBBucketId,
		address collateral
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.unflagPartyALiquidation(partyA, partyABucketId, partyB, partyBBucketId, collateral);
		emit UnflagPartyALiquidation(msg.sender, partyA, partyB, collateral);
	}

	function cancelOpenIntents(uint256[] calldata intentIds) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.cancelOpenIntents(intentIds);
		emit CancelOpenIntentsForLiquidation(msg.sender, intentIds);
	}

	function cancelCloseIntents(uint256[] calldata intentIds) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.cancelCloseIntents(intentIds);
		emit CancelCloseIntentsForLiquidation(msg.sender, intentIds);
	}
}
