// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.19;

import { LibDiamond } from "../../libraries/LibDiamond.sol";

import { AppStorage } from "../../storages/AppStorage.sol";

import { IDiamondCut } from "./IDiamondCut.sol";

/******************************************************************************\
* Author: Nick Mudge <nick@perfectabstractions.com> (https://twitter.com/mudgen)
* EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
/******************************************************************************/

contract DiamondCutFacet is IDiamondCut {
	/// @notice Add/replace/remove any number of functions and optionally execute a function with delegatecall
	/// @param _diamondCut Contains the facet addresses and function selectors
	/// @param _init The address of the contract or facet to execute _calldata
	/// @param _calldata A function call, including function selector and arguments _calldata is executed with delegatecall on _init
	function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) external override {
		// version bump on diamondCut call
		AppStorage.Layout storage appLayout = AppStorage.layout();
		appLayout.version++;

		LibDiamond.enforceIsContractOwner();
		LibDiamond.diamondCut(_diamondCut, _init, _calldata);
	}
}
