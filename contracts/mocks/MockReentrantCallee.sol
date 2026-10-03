// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.19;

interface IReentryTarget {
	function _call(bytes[] calldata _callDatas) external;
}

/// @notice Multicast target that optionally re-enters the caller's `_call` with an empty batch.
///         An empty batch succeeds on its own, so a revert can only come from the reentrancy guard.
contract MockReentrantCallee {
	bool public reenter;
	uint256 public hits;

	function setReenter(bool reenter_) external {
		reenter = reenter_;
	}

	function ping() external {
		hits++;
		if (reenter) IReentryTarget(msg.sender)._call(new bytes[](0));
	}
}
