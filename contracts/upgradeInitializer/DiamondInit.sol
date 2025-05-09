// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

/******************************************************************************\
* Author: Nick Mudge <nick@perfectabstractions.com> (https://twitter.com/mudgen)
* EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
*
* Implementation of a diamond.
/******************************************************************************/

import { LibDiamond } from "../libraries/LibDiamond.sol";

import { IDiamondCut } from "../facets/DiamondCut/IDiamondCut.sol";
import { IDiamondLoupe } from "../facets/DiamondLoup/IDiamondLoupe.sol";

import { IERC165 } from "../interfaces/IERC165.sol";

contract DiamondInit {
	function init() external {
		LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
		ds.supportedInterfaces[type(IERC165).interfaceId] = true;
		ds.supportedInterfaces[type(IDiamondCut).interfaceId] = true;
		ds.supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;
	}
}