// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./TradeSettlementFacetImpl.sol";
import "./ITradeSettlementFacet.sol";
import "../../utils/Accessibility.sol";
import "../../utils/Pausable.sol";
import "../PartyBClose/PartyBCloseFacetImpl.sol";

contract TradeSettlementFacet is Accessibility, Pausable, ITradeSettlementFacet {
	/**
	 * @notice Expires a trade.
	 * @param tradeId The ID of the trade.
	 * @param settlementPriceSig The muon sig about price of the symbol at the time of expiration
	 */
	function expireTrade(
		uint256 tradeId,
		SettlementPriceSig memory settlementPriceSig
	) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
		TradeSettlementFacetImpl.expireTrade(tradeId, settlementPriceSig);
		emit ExpireTrade(msg.sender, tradeId, settlementPriceSig.settlementPrice);
	}

	/**
	 * @notice Exercises a trade.
	 * @param tradeId The ID of the trade.
	 * @param settlementPriceSig The muon sig about price of the symbol at the time of expiration
	 */
	function exerciseTrade(
		uint256 tradeId,
		SettlementPriceSig memory settlementPriceSig
	) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
		TradeSettlementFacetImpl.exerciseTrade(tradeId, settlementPriceSig);
		emit ExerciseTrade(msg.sender, tradeId, settlementPriceSig.settlementPrice);
	}
}
