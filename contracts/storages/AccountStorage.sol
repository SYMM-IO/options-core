// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../libraries/LibScheduledReleaseBalance.sol";

struct Withdraw {
	uint256 id;
	uint256 amount;
	address collateral;
	address user;
	address to;
	uint256 timestamp;
	WithdrawStatus status;
}

enum WithdrawStatus {
	INITIATED,
	CANCELED,
	COMPLETED
}

struct BridgeTransaction {
	uint256 id;
	uint256 amount;
	address collateral;
	address sender;
	address receiver;
	address bridge;
	uint256 timestamp;
	BridgeTransactionStatus status;
}

enum BridgeTransactionStatus {
	RECEIVED,
	SUSPENDED,
	WITHDRAWN
}

library AccountStorage {
	bytes32 internal constant ACCOUNT_STORAGE_SLOT = keccak256("diamond.standard.storage.account");

	struct Layout {
		mapping(address => mapping(address => ScheduledReleaseBalance)) balances; // user => collateral => balance
		mapping(address => mapping(address => uint256)) lockedBalances; // user => collateral => lockedBalance
		mapping(address => uint256) partyBReleaseIntervals;
		uint256 maxConnectedPartyBs;
		/////////////////////////////////////////////////////////
		mapping(address => address) boundPartyB; // partyA => Address of partyB
		mapping(address => uint256) unbindingRequestTime; // partyA => time when unbinding was requested
		uint256 unbindingCooldown;
		/////////////////////////////////////////////////////////
		mapping(address => bool) suspendedAddresses;
		mapping(uint256 => bool) suspendedWithdrawal;
		/////////////////////////////////////////////////////////
		mapping(uint256 => Withdraw) withdrawals;
		mapping(address => uint256[]) userWithdrawals;
		uint256 lastWithdrawId;
		/////////////////////////////////////////////////////////
		mapping(address => bool) instantActionsMode;
		mapping(address => uint256) instantActionsModeDeactivateTime;
		uint256 deactiveInstantActionModeCooldown;
		/////////////////////////////////////////////////////////
		mapping(address => bool) bridges;
		mapping(uint256 => BridgeTransaction) bridgeTransactions;
		mapping(address => uint256[]) bridgeTransactionIds;
		uint256 lastBridgeId;
		address invalidBridgedAmountsPool;
	}

	function layout() internal pure returns (Layout storage l) {
		bytes32 slot = ACCOUNT_STORAGE_SLOT;
		assembly {
			l.slot := slot
		}
	}
}
