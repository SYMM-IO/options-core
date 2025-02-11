// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../utils/Pausable.sol";
import "../../utils/Accessibility.sol";
import "./IClearingHouseFacet.sol";
import "./ClearingHouseFacetImpl.sol";
import "../../storages/AccountStorage.sol";

contract ClearingHouseFacet is Pausable, Accessibility, IClearingHouseFacet {
	/**
	 * @notice Flags Party B to be liquidated.
	 * @param partyB The address of Party B to be liquidated.
	 * @param collateral The address of collateral
	 */
	function flagLiquidation(address partyB, address collateral) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		ClearingHouseFacetImpl.flagLiquidation(partyB, collateral);
		emit FlagLiquidation(msg.sender, partyB, collateral);
	}

	/**
	 * @notice Unflags Party B for liquidation.
	 * @param partyB The address of Party B to be liquidated.
	 * @param collateral The address of collateral
	 */
	function unflagLiquidation(address partyB, address collateral) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		ClearingHouseFacetImpl.unflagLiquidation(partyB, collateral);
		emit UnflagLiquidation(msg.sender, partyB, collateral);
	}

	/**
	 * @notice Liquidates Party B based on the provided signature.
	 * @param partyB The address of Party B to be liquidated.
	 * @param collateral The address of collatarl.
	 * @param upnl The upnl of partyB at the moment of liquidation
	 * @param collateralPrice The price of collateral
	 */
	function liquidate(
		address partyB,
		address collateral,
		int256 upnl,
		uint256 collateralPrice
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		ClearingHouseFacetImpl.liquidate(partyB, collateral, upnl, collateralPrice);
		emit Liquidate(msg.sender, partyB, collateral, AccountStorage.layout().balances[partyB][collateral].available, upnl, collateralPrice);
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

	function unfreezePartyAs(address partyB, address collateral) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {}

	function closeTrades(
		uint256[] memory tradeIds,
		uint256[] memory prices
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		ClearingHouseFacetImpl.closeTrades(tradeIds, prices);
	}

	function distributeCollateral(address[] memory partyAs) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {}
}
