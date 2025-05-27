// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

interface IPriceOracle {
	function getPrice(address token, address collateral) external view returns (uint256);
}
