// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

interface IMultiAccount {
	struct Account {
		address accountAddress;
		string name;
	}
	event SetAccountImplementation(bytes oldAddress, bytes newAddress);
	event SetSymmioAddress(address oldAddress, address newAddress);
	event DeployContract(address sender, address contractAddress);
	event AddAccount(address user, address account, string name);
	event EditAccountName(address user, address account, string newName);
	event DepositForAccount(address collateral, address user, address account, uint256 amount);
	event AllocateForAccount(address user, address account, uint256 amount);
	event CompleteWithdrawFromAccount(uint256 id, address account);
	event Call(address user, address account, bytes _callData, bool _success, bytes _resultData);
	event DelegateAccess(address account, address target, bytes4 selector, bool state);
	event DelegateAccesses(address account, address target, bytes4[] selector, bool state);
	event ProposeToRevokeAccesses(address account, address target, bytes4[] selector);
	event SetDelegateAccessRevokeCooldown(uint256 oldCooldown, uint256 newCooldown);

	function owners(address user) external view returns (address);
	function _call(address account, bytes[] memory _callDatas) external;
	function verifySignatureOfAccount(address account, bytes32 hash, bytes calldata signature) external view returns (bytes4);
}
