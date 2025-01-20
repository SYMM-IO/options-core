// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../utils/Pausable.sol";
import "../../utils/Accessibility.sol";
import "./ILiquidationFacet.sol";
import "./LiquidationFacetImpl.sol";
import "../../storages/AccountStorage.sol";

contract LiquidationFacet is Pausable, Accessibility, ILiquidationFacet {
	function flagLiquidation(address partyB, address collateral) external whenNotLiquidationPaused onlyRole(LibAccessibility.LIQUIDATOR_ROLE) {
		LiquidationFacetImpl.flagLiquidation(partyB, collateral);
		emit FlagLiquidation(msg.sender, partyB, collateral);
	}

	function unflagLiquidation(address partyB, address collateral) external whenNotLiquidationPaused onlyRole(LibAccessibility.LIQUIDATOR_ROLE) {
		LiquidationFacetImpl.unflagLiquidation(partyB, collateral);
		emit UnflagLiquidation(msg.sender, partyB, collateral);
	}
	/**
	 * @notice Liquidates Party B based on the provided signature.
	 * @param partyB The address of Party B to be liquidated.
	 * @param collateral The address of collateral
	 * @param liquidationSig The Muon signature.
	 */
	function liquidate(
		address partyB,
		address collateral,
		LiquidationSig memory liquidationSig
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.LIQUIDATOR_ROLE) {
		LiquidationFacetImpl.liquidate(partyB, collateral, liquidationSig);
		emit Liquidate(
			msg.sender,
			partyB,
			collateral,
			AccountStorage.layout().balances[partyB][collateral],
			liquidationSig.upnl,
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
		address collateral,
		LiquidationSig memory liquidationSig
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.LIQUIDATOR_ROLE) {
		LiquidationFacetImpl.setSymbolsPrice(partyB, collateral, liquidationSig);
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
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.LIQUIDATOR_ROLE) {
		(uint256[] memory liquidatedAmounts, int256[] memory pnls, bytes memory liquidationId) = LiquidationFacetImpl.liquidateTrades(
			partyB,
			collateral,
			tradeIds
		);
		emit LiquidateTrades(msg.sender, partyB, tradeIds, liquidatedAmounts, pnls, liquidationId);
	}
}
