// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { SettlementPriceSig } from "../../types/SettlementTypes.sol";
import { Accessibility } from "../../utils/Accessibility.sol";
import { Pausable } from "../../utils/Pausable.sol";
import { ITradeSettlementFacet } from "./ITradeSettlementFacet.sol";
import { TradeSettlementFacetImpl } from "./TradeSettlementFacetImpl.sol";

/**
 * @title TradeSettlementFacet
 * @notice Manages the settlement of trades
 * @dev Implements the ITradeSettlementFacet interface with access control and pausability
 *      This facet handles the final processes of trade lifecycle including PnL calculation
 */
contract TradeSettlementFacet is Accessibility, Pausable, ITradeSettlementFacet {
	/**
	 * @notice Executes a trade that has reached its expiration timestamp
	 * @dev Can be called by either PartyB or authorized third parties
	 * @param tradeId The unique identifier of the trade being expired
	 * @param settlementPriceSig Cryptographically signed data from Muon oracle containing
	 *                          the verified settlement price of the symbol at expiration time
	 */
	function executeTrade(
		uint256 tradeId,
		SettlementPriceSig memory settlementPriceSig
	) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
		bool isExpired = TradeSettlementFacetImpl.executeTrade(tradeId, settlementPriceSig);
		emit ExecuteTrade(msg.sender, tradeId, settlementPriceSig.settlementPrice, settlementPriceSig.collateralPrice, isExpired);
	}
}
