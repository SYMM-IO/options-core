// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity ^0.8.19;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { ERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { Counters } from "@openzeppelin/contracts/utils/Counters.sol";

interface ISymmio {
	function transferTradeFromNFT(address from, address to, uint256 tradeId) external;
}

contract TradeNFT is ERC721Enumerable, Ownable {
	using Counters for Counters.Counter;

	Counters.Counter private _tokenIdCounter;
	ISymmio public symmio;
	bool private transferInitiatedInSymmio;

	event PositionNFTMinted(address indexed owner, uint256 indexed tokenId);
	event PositionNFTTransferred(uint256 indexed tokenId, address from, address to);

	constructor(address symmio_) ERC721("Trade Ownership NFT", "TRNFT") {
		require(symmio_ != address(0), "TradeNFT: partyAFacet is zero");
		symmio = ISymmio(symmio_);
		_tokenIdCounter.increment();
	}

	/**
	 * @notice Mint an NFT representing a tradeId.
	 *         We first verify the trade is valid by calling PartyAFacet.checkTradeExists(tradeId).
	 */
	function mintNFTForTrade(address to) external returns (uint256 tokenId) {
		require(msg.sender == address(symmio), "TradeNFT: Only Symmio contract can mint NFT");
		tokenId = _tokenIdCounter.current();
		_tokenIdCounter.increment();

		_mint(to, tokenId);

		emit PositionNFTMinted(to, tokenId);
		return tokenId;
	}

	/**
	 * @notice The diamond/facet calls this function to forcibly transfer an NFT from -> to,
	 *         for the scenario where PartyA initiated a trade transfer in the diamond.
	 */
	function transferNFTInitiatedInSymmio(address from, address to, uint256 tokenId) external {
		require(msg.sender == address(symmio), "TradeNFT: only facet can call");

		transferInitiatedInSymmio = true;
		_transfer(from, to, tokenId);
		transferInitiatedInSymmio = false;
	}

	/**
	 * @notice If a user calls `transferFrom` or `safeTransferFrom` directly on the NFT,
	 *         we use `_beforeTokenTransfer` to call the diamond for trade ownership update
	 */
	function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal override {
		super._beforeTokenTransfer(from, to, tokenId, batchSize);

		if (from != address(0) && to != address(0) && !transferInitiatedInSymmio) {
			symmio.transferTradeFromNFT(from, to, tokenId);
			emit PositionNFTTransferred(tokenId, from, to);
		}
	}

	function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Enumerable) returns (bool) {
		return interfaceId == type(IERC721).interfaceId || interfaceId == type(ERC721Enumerable).interfaceId || super.supportsInterface(interfaceId);
	}
}
