// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibAccessibility } from "../../libraries/core/LibAccessibility.sol";
import { LibParty } from "../../libraries/models/LibParty.sol";

import { Pausable } from "../../utils/Pausable.sol";
import { Accessibility } from "../../utils/Accessibility.sol";

import { IClearingHouseFacet } from "./IClearingHouseFacet.sol";
import { LibClearingHouse } from "../../libraries/core/LibClearingHouse.sol";

import { MarginType } from "../../types/BaseTypes.sol";

contract ClearingHouseFacet is Pausable, Accessibility, IClearingHouseFacet {
	using LibParty for address;

	/**
	 * @notice Flags Party B to be liquidated.
	 * @param partyB The address of Party B to be liquidated.
	 * @param collateral The address of collateral
	 */
	function flagIsolatedPartyBLiquidation(
		address partyB,
		address collateral
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.flagIsolatedPartyBLiquidation(partyB, collateral);
		emit FlagIsolatedPartyBLiquidation(msg.sender, partyB, collateral);
	}

	/**
	 * @notice Unflags Party B for liquidation.
	 * @param partyB The address of Party B to be liquidated.
	 * @param collateral The address of collateral
	 */
	function unflagIsolatedPartyBLiquidation(
		address partyB,
		address collateral
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.unflagIsolatedPartyBLiquidation(partyB, collateral);
		emit UnflagIsolatedPartyBLiquidation(msg.sender, partyB, collateral);
	}

	/**
	 * @notice Liquidates Party B based on the provided signature.
	 * @param partyB The address of Party B to be liquidated.
	 * @param collateral The address of collateral.
	 * @param upnl The upnl of partyB at the moment of liquidation
	 * @param collateralPrice The price of collateral
	 */
	function liquidateIsolatedPartyB(
		address partyB,
		address collateral,
		int256 upnl,
		uint256 collateralPrice
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.liquidateIsolatedPartyB(partyB, collateral, upnl, collateralPrice);
		emit LiquidateIsolatedPartyB(msg.sender, partyB, collateral, partyB.balanceOf(collateral).isolatedBalance, upnl, collateralPrice);
	}

	function confiscatePartyA(
		uint256 liquidationId,
		uint256 amount
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.confiscatePartyA(liquidationId, amount);
		emit ConfiscatePartyA(msg.sender, liquidationId, amount);
	}

	function confiscatePartyBWithdrawal(uint256 withdrawId) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.confiscatePartyBWithdrawal(withdrawId);
		emit ConfiscatePartyBWithdrawal(msg.sender, withdrawId);
	}

	function distributeCollateral(
		address partyB,
		address collateral,
		MarginType marginType,
		address[] calldata partyAs,
		uint256[] calldata amounts
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.distributeCollateral(partyB, collateral, marginType, partyAs, amounts);
		emit DistributeCollateral(msg.sender, partyB, collateral, partyAs, amounts);
		// if (isLiquidationFinished) {
		// 	emit FullyLiquidated(partyB, liquidationId);
		// }
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
		LibClearingHouse.liquidateCrossPartyA(liquidationId, upnl, collateralPrice);
		emit LiquidateCrossPartyA(msg.sender, liquidationId, partyA, partyB, collateral, upnl, collateralPrice);
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

	function cancelOpenIntents(uint256[] calldata intentIds) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.cancelOpenIntents(intentIds);
		emit CancelOpenIntentsForLiquidation(msg.sender, intentIds);
	}

	function cancelCloseIntents(uint256[] calldata intentIds) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		LibClearingHouse.cancelCloseIntents(intentIds);
		emit CancelCloseIntentsForLiquidation(msg.sender, intentIds);
	}
}
