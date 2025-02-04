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
		ClearingHouseFacetImpl.unflagLiquidation(partyB, collateral, true);
		emit UnflagLiquidation(msg.sender, partyB, collateral);
	}

	// /**
	//  * @notice Unflags Party B for liquidation.
	//  * @param partyB The address of Party B to be liquidated.
	//  * @param collateral The address of collateral
	//  */
	// function forceUnflagLiquidation(
	// 	address partyB,
	// 	address collateral
	// ) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
	// 	ClearingHouseFacetImpl.unflagLiquidation(partyB, collateral, false);
	// 	emit UnflagLiquidation(msg.sender, partyB, collateral);
	// }

	/**
	 * @notice Liquidates Party B based on the provided signature.
	 * @param partyB The address of Party B to be liquidated.
	 * @param liquidationSig The Muon signature.
	 */
	function liquidate(
		address partyB,
		LiquidationSig memory liquidationSig
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		ClearingHouseFacetImpl.liquidate(partyB, liquidationSig);
		emit Liquidate(
			msg.sender,
			partyB,
			liquidationSig.collateral,
			AccountStorage.layout().balances[partyB][liquidationSig.collateral].available,
			liquidationSig.upnl,
			liquidationSig.collateralPrice,
			liquidationSig.liquidationId
		);
	}

	/**
	 * @notice Sets the prices of symbols at the time of liquidation.
	 * @dev The Muon signature here should be the same as the one that got partyB liquidated.
	 * @param partyB The address of Party B associated with the liquidation.
	 * @param liquidationSig The Muon signature containing symbol IDs and their corresponding prices.
	 */
	function setSymbolsPrice(
		address partyB,
		LiquidationSig memory liquidationSig
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		ClearingHouseFacetImpl.setSymbolsPrice(partyB, liquidationSig);
		emit SetSymbolsPrices(msg.sender, partyB, liquidationSig.symbolIds, liquidationSig.prices, liquidationSig.liquidationId);
	}

	/**
	 * @notice Liquidates trades of Party B.
	 * @param partyB The address of Party B whose trades will be liquidated.
	 * @param tradeIds An array of trade IDs representing the Trades to be liquidated.
	 */
	function liquidateTrades(
		address partyB,
		address collateral,
		uint256[] memory tradeIds
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {
		(uint256[] memory liquidatedAmounts, int256[] memory pnls, bytes memory liquidationId, bool isFullyLiquidated) = ClearingHouseFacetImpl
			.liquidateTrades(partyB, collateral, tradeIds);
		emit LiquidateTrades(msg.sender, partyB, tradeIds, liquidatedAmounts, pnls, liquidationId);
		if (isFullyLiquidated) {
			emit FullyLiquidated(partyB, liquidationId);
		}
	}
}
