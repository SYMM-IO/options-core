// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.19;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface ITradeNFTForMock {
	function mintNFTForTrade(address partyA, uint256 tradeId) external;

	function transferTradeNFT(address from, address to, uint256 tradeId) external;
}

/// @notice Stands in for Symmio in TradeNFT tests. Records every callback with the NFT owner at call time,
///         which pins whether the callback runs before or after ownership moves.
contract MockTradeNFTSymmio {
	struct TransferCall {
		address from;
		address to;
		uint256 tradeId;
		address ownerAtCall;
	}

	TransferCall[] public calls;
	ITradeNFTForMock public nft;

	function setNFT(address nft_) external {
		nft = ITradeNFTForMock(nft_);
	}

	function transferTradeFromNFT(address from, address to, uint256 tradeId) external {
		calls.push(TransferCall(from, to, tradeId, IERC721(address(nft)).ownerOf(tradeId)));
	}

	function callCount() external view returns (uint256) {
		return calls.length;
	}

	function mint(address to, uint256 tradeId) external {
		nft.mintNFTForTrade(to, tradeId);
	}

	function moveTrade(address from, address to, uint256 tradeId) external {
		nft.transferTradeNFT(from, to, tradeId);
	}
}
