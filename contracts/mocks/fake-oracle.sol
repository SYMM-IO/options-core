// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.19;

contract FakeOracle {
	function getPrice(address token, address symbolCollateral) external pure returns (uint256) {
		return 1e18;
	}
}
