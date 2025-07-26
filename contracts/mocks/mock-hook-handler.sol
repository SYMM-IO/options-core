// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.19;

contract MockHookHandler {
	function onTransfer(address collateral, address sender, address receiver, uint256 amount) external {}
}
