// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IExternalTransferTarget } from "../../interfaces/IExternalTransferTarget.sol";
import { IExpressWithdrawProvider } from "../../interfaces/IExpressWithdrawProvider.sol";

contract NativeBucketHooks is IExternalTransferTarget, IExpressWithdrawProvider {
	address public sender;
	address public receiver;
	address public collateral;
	uint256 public amount;
	bool public rejectWithdraw;

	function onTransfer(address token, address from, address to, uint256 value) external {
		collateral = token;
		sender = from;
		receiver = to;
		amount = value;
	}

	function setRejectWithdraw(bool rejected) external {
		rejectWithdraw = rejected;
	}

	function validateWithdraw(address, address, uint256, address, bytes memory) external view returns (bool, string memory) {
		return (!rejectWithdraw, "test rejection");
	}
}
