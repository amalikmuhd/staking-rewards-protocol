// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @title RewardNFT
/// @notice Simple ERC721 reward badge. Only the StakingRewards contract (set as
///         the immutable `minter`) is allowed to mint.
contract RewardNFT is ERC721 {
    /// @notice The only address permitted to mint — the StakingRewards contract.
    address public immutable minter;
    /// @notice ID assigned to the next minted token.
    uint256 public nextTokenId;

    error NotMinter();

    constructor(address _minter) ERC721("Reward NFT", "rNFT") {
        minter = _minter;
    }

    /// @notice Mint a new reward NFT to `to`. Callable only by the minter.
    function mint(address to) external returns (uint256 tokenId) {
        if (msg.sender != minter) revert NotMinter();
        tokenId = nextTokenId++;
        _safeMint(to, tokenId);
    }
}
