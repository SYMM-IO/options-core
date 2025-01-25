// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IPartyAFacet {
    function checkTradeExists(uint256 tradeId) external view;
    function setTradeTokenId(uint256 tradeId, uint256 tokenId) external;
    function transferTradeFromNFT(address from, address to, uint256 tradeId) external;
}

contract TradeNFT is ERC721, Ownable {
    address public partyAFacet;
    mapping(uint256 => uint256) private tokenToTradeId;

    uint256 private _nextTokenId;

    bool private inFacetTransfer;

    constructor(address _partyAFacet) ERC721("Trade Ownership NFT", "TRNFT") {
        require(_partyAFacet != address(0), "TradeNFT: partyAFacet is zero");
        partyAFacet = _partyAFacet;
    }

    function setPartyAFacet(address _partyAFacet) external onlyOwner {
        require(_partyAFacet != address(0), "TradeNFT: zero address");
        partyAFacet = _partyAFacet;
    }

    /**
     * @notice Mint an NFT representing a tradeId. 
     *         We first verify the trade is valid by calling PartyAFacet.checkTradeExists(tradeId).
     */
    function mintNFTForTrade(address to, uint256 tradeId) external onlyOwner returns (uint256 tokenId) {
        IPartyAFacet(partyAFacet).checkTradeExists(tradeId);

        tokenId = ++_nextTokenId;
        tokenToTradeId[tokenId] = tradeId;
        _safeMint(to, tokenId);

        IPartyAFacet(partyAFacet).setTradeTokenId(tradeId, tokenId);
    }

    /**
     * @notice The diamond/facet calls this function to forcibly transfer an NFT from -> to, 
     *         for the scenario where PartyA initiated a trade transfer in the diamond.
     */
    function transferNFTFromFacet(address from, address to, uint256 tokenId) external {
        require(msg.sender == partyAFacet, "TradeNFT: only facet can call");
        require(ownerOf(tokenId) == from, "TradeNFT: from is not token owner");
        require(!inFacetTransfer, "TradeNFT: re-entrant call?");

        inFacetTransfer = true;
        _transfer(from, to, tokenId);
        inFacetTransfer = false;
    }

    /**
     * @notice Provide a way for the diamond or users to see which trade is mapped to a tokenId
     */
    function getTradeIdByToken(uint256 tokenId) external view returns (uint256) {
        return tokenToTradeId[tokenId];
    }

    /**
     * @notice If a user calls `transferFrom` or `safeTransferFrom` directly on the NFT, 
     *         we use `_beforeTokenTransfer` to call the diamond for trade ownership update
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        override
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
        if (from == address(0) || to == address(0)) {
            return;
        }

        if (inFacetTransfer) {
            return;
        }

        uint256 tradeId = tokenToTradeId[tokenId];
        IPartyAFacet(partyAFacet).transferTradeFromNFT(from, to, tradeId);
    }
}