// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IERC721MintableAndBurnable is IERC721 {
  function mint(address _to) external returns (uint256 tokenIdMinted);
  function burn(uint256 _tokenId) external;
}
