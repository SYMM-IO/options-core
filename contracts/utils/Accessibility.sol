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
	// Custom errors
	error NotPartyB(address sender);
	error IsPartyB(address sender);
	error UserIsPartyB(address user);
	error MissingRole(address sender, bytes32 role);
	error NotPartyAOfTrade(address sender, uint256 tradeId, address partyA);
	error NotPartyBOfTrade(address sender, uint256 tradeId, address partyB);
	error UserSuspended(address user);
	error ReceiverSuspended(address receiver);
	error SuspendedWithdrawal(uint256 withdrawId);
	error InstantActionModeActive(address sender);

	modifier onlyPartyB() {
		if (!AppStorage.layout().partyBConfigs[msg.sender].isActive) revert NotPartyB(msg.sender);
		_;
	}

	modifier notPartyB() {
		if (AppStorage.layout().partyBConfigs[msg.sender].isActive) revert IsPartyB(msg.sender);
		_;
	}

	modifier userNotPartyB(address user) {
		if (AppStorage.layout().partyBConfigs[user].isActive) revert UserIsPartyB(user);
		_;
	}

	modifier onlyRole(bytes32 role) {
		if (!LibAccessibility.hasRole(msg.sender, role)) revert MissingRole(msg.sender, role);
		_;
	}

	modifier onlyPartyAOfTrade(uint256 tradeId) {
		Trade storage trade = IntentStorage.layout().trades[tradeId];
		if (trade.partyA != msg.sender) revert NotPartyAOfTrade(msg.sender, tradeId, trade.partyA);
		_;
	}

	modifier onlyPartyBOfTrade(uint256 tradeId) {
		Trade storage trade = IntentStorage.layout().trades[tradeId];
		if (trade.partyB != msg.sender) revert NotPartyBOfTrade(msg.sender, tradeId, trade.partyB);
		_;
	}

	modifier notSuspended(address user) {
		if (AccountStorage.layout().suspendedAddresses[user]) revert UserSuspended(user);
		_;
	}

	modifier notSuspendedWithdrawal(uint256 withdrawId) {
		Withdraw storage withdrawObject = AccountStorage.layout().withdrawals[withdrawId];
		if (AccountStorage.layout().suspendedAddresses[withdrawObject.user]) revert UserSuspended(withdrawObject.user);
		if (AccountStorage.layout().suspendedAddresses[withdrawObject.to]) revert ReceiverSuspended(withdrawObject.to);
		if (AccountStorage.layout().suspendedWithdrawal[withdrawId]) revert SuspendedWithdrawal(withdrawId);
		_;
	}

	modifier inactiveInstantMode(address sender) {
		if (AccountStorage.layout().instantActionsMode[sender]) revert InstantActionModeActive(sender);
		_;
	}
}
