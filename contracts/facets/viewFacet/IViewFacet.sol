// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity  >= 0.8.18;

interface IViewFacet{

    // Account
    function balanceOf(address user, address collateral) external view returns (uint256);

	function lockedBalancesOf(address user, address collateral) external view returns(uint256);

    function partyAStats(
		address partyA,
		address collateral
	)
		external
		view
		returns (bool, uint256, uint256, uint256[] memory, uint256[] memory, uint256[] memory);

	function getWithdraw(uint256 id) external view returns(Withdraw memory);

	function isSuspended(address user) external view returns(bool);
	
	// Intents
}