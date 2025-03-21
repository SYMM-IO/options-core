// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibAccessibility } from "../libraries/LibAccessibility.sol";
import { AccountStorage, Withdraw } from "../storages/AccountStorage.sol";
import { AppStorage } from "../storages/AppStorage.sol";
import { Trade, IntentStorage, OpenIntent } from "../storages/IntentStorage.sol";

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

	modifier onlyPartyBOfTrade(uint256 tradeId) {
		Trade storage trade = IntentStorage.layout().trades[tradeId];
		require(trade.partyB == msg.sender, "Accessibility: Should be partyB of Trade");
		_;
	}

	modifier notSuspended(address user) {
		require(!AccountStorage.layout().suspendedAddresses[user], "Accessibility: Sender is Suspended");
		_;
	}

	modifier notSuspendedWithdrawal(uint256 withdrawId) {
		Withdraw storage withdrawObject = AccountStorage.layout().withdrawals[withdrawId];
		require(!AccountStorage.layout().suspendedAddresses[withdrawObject.user], "Accessibility: User is Suspended");
		require(!AccountStorage.layout().suspendedAddresses[withdrawObject.to], "Accessibility: Receiver is Suspended");
		require(!AccountStorage.layout().suspendedWithdrawal[withdrawId], "Accessibility: Withdrawal is Suspended");
		_;
	}

	modifier inactiveInstantMode(address sender) {
		require(!AccountStorage.layout().instantActionsMode[sender], "Accessibility: Instant action mode is activated");
		_;
	}
}
