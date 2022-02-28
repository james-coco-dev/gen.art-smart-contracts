// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../utils/MinterRole.sol";

contract GenArtStaking is ERC721('GenArt Staking Token', 'GenArt:STK'), MinterRole {
  using SafeMath for uint256;

  uint256 private _totalSupply;

  constructor() {

  }

  function mint(address _to) external onlyMinter returns (uint256) {
    uint newTokenId = _totalSupply + 1;
    _safeMint(_to, newTokenId);
    return newTokenId;
  }

  function burn(uint256 _tokenId) external {
    require(_isApprovedOrOwner(msg.sender, _tokenId), "ERC721Burnable: caller is not owner nor approved");
    _burn(_tokenId);
    _totalSupply = _totalSupply.sub(1);
  }
}
