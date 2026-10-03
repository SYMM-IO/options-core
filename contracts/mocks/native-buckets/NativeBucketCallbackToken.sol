// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Test token that calls an arbitrary contract during deposit transferFrom.
contract NativeBucketCallbackToken is ERC20 {
	address public callbackTarget;
	bytes public callbackData;
	bool public callbackSucceeded;
	bytes public callbackResult;
	bool private callingBack;

	constructor() ERC20("Native bucket callback token", "CALLBACK") {}

	function mint(address recipient, uint256 amount) external {
		_mint(recipient, amount);
	}

	function configureCallback(address target, bytes calldata data) external {
		callbackTarget = target;
		callbackData = data;
		callbackSucceeded = false;
	}

	function execute(address target, bytes calldata data) external {
		(bool success, bytes memory result) = target.call(data);
		if (!success) {
			assembly {
				revert(add(result, 32), mload(result))
			}
		}
	}

	function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
		bool success = super.transferFrom(from, to, amount);
		if (callbackTarget != address(0) && !callingBack) {
			callingBack = true;
			(callbackSucceeded, callbackResult) = callbackTarget.call(callbackData);
			callingBack = false;
		}
		return success;
	}
}

/// @dev Test wallet reproducing a token callback through the original bucket owner.
contract NativeBucketCallbackWallet {
	address public reentryTarget;
	bytes public reentryData;
	bool public reentrySucceeded;
	bytes public reentryResult;

	function configureReentry(address target, bytes calldata data) external {
		reentryTarget = target;
		reentryData = data;
		reentrySucceeded = false;
	}

	function onTokenCallback() external {
		(reentrySucceeded, reentryResult) = reentryTarget.call(reentryData);
	}

	function execute(address target, bytes calldata data) external returns (bytes memory result) {
		bool success;
		(success, result) = target.call(data);
		if (!success) {
			assembly {
				revert(add(result, 32), mload(result))
			}
		}
	}
}

contract NativeBucketSixDecimalToken is ERC20 {
	constructor() ERC20("Six decimal bucket collateral", "SIX") {}
	function decimals() public pure override returns (uint8) {
		return 6;
	}
	function mint(address recipient, uint256 amount) external {
		_mint(recipient, amount);
	}
}
