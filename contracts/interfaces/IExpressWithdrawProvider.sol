// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

interface IExpressWithdrawProvider {
	function validateWithdraw(
		address user,
		address collateral,
		uint256 amount,
		address to,
		bytes memory userData
	) external view returns (bool, string memory reason);
}
