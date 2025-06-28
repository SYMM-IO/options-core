// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { SettlementPriceSig } from "../../types/SettlementTypes.sol";

import { Pausable } from "../../utils/Pausable.sol";
import { Accessibility } from "../../utils/Accessibility.sol";

import { ITradeSettlementFacet } from "./ITradeSettlementFacet.sol";
import { LibTradeSettlement } from "../../libraries/core/LibTradeSettlement.sol";

/**
 * @title TradeSettlementFacet
 * @notice Manages the settlement of trades
 * @dev Implements the ITradeSettlementFacet interface with access control and pausability
 *      This facet handles the final processes of trade lifecycle including PnL calculation
 */
contract TradeSettlementFacet is Accessibility, Pausable, ITradeSettlementFacet {
	/**
	 * @notice Executes trades of an specific symbol that have reached their expiration timestamp
	 * @dev Can be called by either PartyB or authorized third parties
	 * @param tradeIds Array of unique identifiers of the trades to be executed
	 * @param settlementPriceSig Cryptographically signed data from Muon oracle containing
	 *                          the verified settlement price of the symbol at expiration time
	 */
	function executeTrades(uint256[] memory tradeIds, SettlementPriceSig memory settlementPriceSig) external whenNotThirdPartyActionsPaused {
		(bool[] memory exercised, bool[] memory expired) = LibTradeSettlement.executeTrades(tradeIds, settlementPriceSig);
		emit ExecuteTrades(msg.sender, tradeIds, exercised, expired, settlementPriceSig.settlementPrice, settlementPriceSig.collateralPrice);
	}
}
