// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibTradeOperations } from "../../libraries/core/LibTradeOperations.sol";

import { Pausable } from "../../utils/Pausable.sol";
import { Accessibility } from "../../utils/Accessibility.sol";
import { ReentrancyGuard } from "../../utils/ReentrancyGuard.sol";

import { ITradeFacet } from "./ITradeFacet.sol";
import { SettlementPriceSig } from "../../types/TradeTypes.sol";

/**
 * @title TradeFacet
 * @notice Manages trade transactions through trade operations
 * @dev Implements the ITradeFacet interface with access control and pausability mechanisms
 */
contract TradeFacet is Accessibility, Pausable, ITradeFacet, ReentrancyGuard {
	/**
	 * @notice Transfers ownership of a trade to another address
	 * @dev Only the current PartyA owner of the trade can initiate this transfer
	 *      If the trade has an associated NFT, the NFT will also be transferred
	 * @param receiver The address that will become the new owner of the trade
	 * @param tradeId The unique identifier of the trade to be transferred
	 */
	function transferTrade(
		address receiver,
		uint256 tradeId
	) external nonReentrant whenPartyNotPaused(msg.sender) onlyPartyAOfTrade(tradeId) whenNotSuspended(msg.sender) whenNotSuspended(receiver) {
		LibTradeOperations.transferTrade(receiver, tradeId);
		emit TransferTradeByPartyA(msg.sender, receiver, tradeId);
	}

	/**
	 * @notice Updates trade ownership when an associated NFT is transferred
	 * @dev This function is designed to be called only by the NFT contract itself
	 *      It synchronizes the trade ownership with the NFT ownership after transfers
	 * @param sender The previous owner of the trade/NFT
	 * @param receiver The new owner who will receive ownership of the trade
	 * @param tradeId The unique identifier of the trade whose ownership is being updated
	 */
	function transferTradeFromNFT(
		address sender,
		address receiver,
		uint256 tradeId
	) external whenPartyNotPaused(sender) whenNotSuspended(sender) whenNotSuspended(receiver) {
		LibTradeOperations.transferTradeFromNFT(sender, receiver, tradeId);
		emit TransferTradeByPartyA(sender, receiver, tradeId);
	}

	/**
	 * @notice Executes trades of an specific symbol that have reached their expiration timestamp
	 * @dev Can be called by either PartyB or authorized third parties
	 * @param tradeIds Array of unique identifiers of the trades to be executed
	 * @param settlementPriceSig Cryptographically signed data from Muon oracle containing
	 *                          the verified settlement price of the symbol at expiration time
	 */
	function executeTrades(uint256[] calldata tradeIds, SettlementPriceSig calldata settlementPriceSig) external whenNotThirdPartyActionsPaused {
		(bool[] memory exercised, bool[] memory expired) = LibTradeOperations.executeTrades(tradeIds, settlementPriceSig);
		emit ExecuteTrades(msg.sender, tradeIds, exercised, expired, settlementPriceSig.settlementPrice, settlementPriceSig.collateralPrice);
	}

	/**
	 * @notice Mints an NFT for a trade
	 * @dev Only PartyA can call this function
	 * @param tradeId The unique identifier of the trade to mint an NFT for
	 */
	function mintNFTForTrade(uint256 tradeId) external nonReentrant onlyPartyAOfTrade(tradeId) {
		LibTradeOperations.mintNFTForTrade(tradeId);
	}
}
