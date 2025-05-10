// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibAccessibility } from "../../libraries/LibAccessibility.sol";

import { AccountStorage } from "../../storages/AccountStorage.sol";

import { Pausable } from "../../utils/Pausable.sol";
import { Accessibility } from "../../utils/Accessibility.sol";

import { IClearingHouseFacet } from "./IClearingHouseFacet.sol";
import { ClearingHouseFacetImpl } from "./ClearingHouseFacetImpl.sol";

contract ClearingHouseFacet is Pausable, Accessibility, IClearingHouseFacet {
	/**
	 * @notice Flags Party B to be liquidated.
	 * @param partyB The address of Party B to be liquidated.
	 * @param collateral The address of collateral
	 */
	function flagIsolatedPartyBLiquidation(
		address partyB,
		address collateral
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		ClearingHouseFacetImpl.flagIsolatedPartyBLiquidation(partyB, collateral);
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
		ClearingHouseFacetImpl.unflagIsolatedPartyBLiquidation(partyB, collateral);
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
		ClearingHouseFacetImpl.liquidateIsolatedPartyB(partyB, collateral, upnl, collateralPrice);
		emit LiquidateIsolatedPartyB(
			msg.sender,
			partyB,
			collateral,
			AccountStorage.layout().balances[partyB][collateral].isolatedBalance,
			upnl,
			collateralPrice
		);
	}

	function confiscatePartyA(
		address partyB,
		address partyA,
		address collateral,
		uint256 amount
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		ClearingHouseFacetImpl.confiscatePartyA(partyB, partyA, collateral, amount);
		emit ConfiscatePartyA(partyB, partyA, collateral, amount);
	}

	function confiscatePartyBWithdrawal(
		address partyB,
		uint256 withdrawId
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		ClearingHouseFacetImpl.confiscatePartyBWithdrawal(partyB, withdrawId);
		emit ConfiscatePartyBWithdrawal(partyB, withdrawId);
	}

	function distributeCollateral(
		address partyB,
		address collateral,
		address[] memory partyAs,
		uint256[] memory amounts
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		ClearingHouseFacetImpl.distributeCollateral(partyB, collateral, partyAs);
		emit DistributeCollateral(msg.sender, partyB, collateral, partyAs, amounts);
		// if (isLiquidationFinished) {
		// 	emit FullyLiquidated(partyB, liquidationId);
		// }
	}

	// function unfreezePartyAs(address partyB, address collateral) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {}

	function flagCrossPartyBLiquidation(
		address partyB,
		address partyA,
		address collateral
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		ClearingHouseFacetImpl.flagCrossPartyBLiquidation(partyB, partyA, collateral);
		emit FlagCrossPartyBLiquidation(msg.sender, partyB, partyA, collateral);
	}

	function unflagCrossPartyBLiquidation(
		address partyB,
		address partyA,
		address collateral
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		ClearingHouseFacetImpl.unflagCrossPartyBLiquidation(partyB, partyA, collateral);
		emit UnflagCrossPartyBLiquidation(msg.sender, partyB, partyA, collateral);
	}

	function liquidateCrossPartyB(
		address partyB,
		address partyA,
		address collateral,
		int256 upnl,
		uint256 collateralPrice
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		ClearingHouseFacetImpl.liquidateCrossPartyB(partyB, partyA, collateral, upnl, collateralPrice);
		emit LiquidateCrossPartyB(msg.sender, partyB, partyA, collateral, upnl, collateralPrice);
	}

	function flagPartyALiquidation(
		address partyA,
		address partyB,
		address collateral
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		ClearingHouseFacetImpl.flagPartyALiquidation(partyA, partyB, collateral);
		emit FlagPartyALiquidation(msg.sender, partyA, partyB, collateral);
	}

	function unflagPartyALiquidation(
		address partyA,
		address partyB,
		address collateral
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		ClearingHouseFacetImpl.unflagPartyALiquidation(partyA, partyB, collateral);
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
		ClearingHouseFacetImpl.liquidateCrossPartyA(liquidationId, upnl, collateralPrice);
		emit LiquidateCrossPartyA(msg.sender, liquidationId, partyA, partyB, collateral, upnl, collateralPrice);
	}

	function closeTrades(
		uint256 liquidationId,
		uint256[] memory tradeIds,
		uint256[] memory prices
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		ClearingHouseFacetImpl.closeTrades(liquidationId, tradeIds, prices);
		emit CloseTradesForLiquidation(msg.sender, tradeIds, prices);
	}

	function allocateFromReserveToCross(
		address party,
		address counterParty,
		address collateral,
		uint256 amount
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		ClearingHouseFacetImpl.allocateFromReserveToCross(party, counterParty, collateral, amount);
	}
}
