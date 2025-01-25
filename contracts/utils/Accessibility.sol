// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../storages/AppStorage.sol";
import "../storages/SymbolStorage.sol";
import "../storages/AccountStorage.sol";
import "../storages/IntentStorage.sol";
import "../libraries/LibAccessibility.sol";

abstract contract Accessibility {
	modifier onlyPartyB() {
		require(AppStorage.layout().partyBConfigs[msg.sender].isActive, "Accessibility: Should be partyB");
		_;
	}

	modifier notPartyB() {
		require(!AppStorage.layout().partyBConfigs[msg.sender].isActive, "Accessibility: Shouldn't be partyB");
		_;
	}

	modifier userNotPartyB(address user) {
		require(!AppStorage.layout().partyBConfigs[user].isActive, "Accessibility: Shouldn't be partyB");
		_;
	}

	modifier onlyRole(bytes32 role) {
		require(LibAccessibility.hasRole(msg.sender, role), "Accessibility: Must has role");
		_;
	}

	modifier onlyPartyAOfTrade(uint256 tradeId) {
		Trade storage trade = IntentStorage.layout().trades[tradeId];
		require(trade.partyA == msg.sender, "Accessibility: Should be partyA of Trade");
		_;
	}

	modifier onlyNFTContract() {
        IntentStorage.Layout storage intentLayout = IntentStorage.layout();
        require(msg.sender == intentLayout.tradeNftAddress, "PartyAFacet: caller not TradeNFT");
        _;
    }

	modifier onlyPartyBOfOpenIntent(uint256 intentId) {
		OpenIntent storage intent = IntentStorage.layout().openIntents[intentId];
		require(intent.partyB == msg.sender, "Accessibility: Should be partyB of Intent");
		_;
	}

	modifier onlyPartyBOfTrade(uint256 tradeId) {
		Trade storage trade = IntentStorage.layout().trades[tradeId];
		require(trade.partyB == msg.sender, "Accessibility: Should be partyB of Trade");
		_;
	}

	modifier onlyPartyBOfCloseIntent(uint256 intentId) {
		Trade storage trade = IntentStorage.layout().trades[IntentStorage.layout().closeIntents[intentId].tradeId];

		require(trade.partyB == msg.sender, "Accessibility: Should be partyA of Intent");
		_;
	}

	modifier notSuspended(address user) {
		require(!AccountStorage.layout().suspendedAddresses[user], "Accessibility: Sender is Suspended");
		_;
	}

	modifier notSuspendedWithdrawal(uint256 withdrawId) {
		Withdraw storage withdrawObject = AccountStorage.layout().withdraws[withdrawId];
		require(!AccountStorage.layout().suspendedAddresses[withdrawObject.user], "Accessibility: User is Suspended");
		require(!AccountStorage.layout().suspendedAddresses[withdrawObject.to], "Accessibility: Reciever is Suspended");
		_;
	}
}
