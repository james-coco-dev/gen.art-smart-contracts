// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../interfaces/IERC721MintableAndBurnable.sol";

contract GenArtStaking is Ownable, ReentrancyGuard {
	using SafeMath for uint256;
	using SafeERC20 for IERC20;

	struct PoolInfo {
		uint256 dropStartBlock;
		uint256 dropEndBlock;
		uint256 DARefundsETH;
		uint256 mintFundsETH;
		uint256 DARefundPoolETHBalanceInDrop;
		uint256 memPoolETHBalanceInDrop;
		uint256 genPoolETHBalanceInDrop;
		uint256 totalGenAmountStaked;
		uint256 totalStandardMemTokenAmountStaked;
		uint256 totalGoldMemTokenAmountStaked;
  }

  struct UserInfo {
		address userAddress;
    uint256[] memIds;
		bool isGoldMem;
    uint256 genAmount;
    uint256 blockNumber;
		uint256 rewardsClaimed;
  }

	address public memToken;
	address public genToken;
	address public stkToken;

  mapping (uint256 => mapping (address => UserInfo)) public stakedUsers;	// stkTokenId => user => UserInfo

	mapping (uint256 => PoolInfo) public pools;	// dropId => PoolInfo
	uint256 private _currentDropId;

	mapping (uint256 => mapping (address => uint256)) public ethSpends;	// minted amount of user in drop, just temporary variable which should be moved later. dropId => user => ethSpends

	uint16 DARefundsPoolDistributionRate = 20;
	uint16 genPoolDistributionRate = 60;
	uint16 memPoolDistributionRate = 20;

  constructor(address _memToken, address _genToken, address _stkToken) {
		memToken = _memToken;
		genToken = _genToken;
		stkToken = _stkToken;
  }

  function stake(uint256[] memory _memIds, bool _isGold, uint256 _genAmount) external {
		PoolInfo storage pool = pools[_currentDropId];
		IERC20(genToken).safeTransferFrom(_msgSender(), address(this), _genAmount);
		for (uint i = 0; i < _memIds.length; i++) {
			IERC721(memToken).safeTransferFrom(_msgSender(), address(this), _memIds[i]);
		}
		pool.totalGenAmountStaked = pool.totalGenAmountStaked.add(_genAmount);
		if (_isGold) {
			pool.totalGoldMemTokenAmountStaked = pool.totalGoldMemTokenAmountStaked.add(_memIds.length);
		} else {
			pool.totalStandardMemTokenAmountStaked = pool.totalStandardMemTokenAmountStaked.add(_memIds.length);
		}
		(uint256 tokenId) = IERC721MintableAndBurnable(stkToken).mint(_msgSender());
    UserInfo storage user = stakedUsers[tokenId][_msgSender()];
		user.userAddress = _msgSender();
		user.memIds = _memIds;
		user.isGoldMem = _isGold;
    user.genAmount = user.genAmount.add(_genAmount);
		user.blockNumber = block.number;
  }

	function unstake(uint256 _stkTokenId) external {
		require(IERC721(stkToken).ownerOf(_stkTokenId) == _msgSender(), 'GenArtStaking: !unstake');
		UserInfo memory user = stakedUsers[_stkTokenId][_msgSender()];
		for (uint i = 0; i < user.memIds.length; i++) {
			IERC721(memToken).approve(_msgSender(), user.memIds[i]);
			IERC721(memToken).safeTransferFrom(address(this), _msgSender(), user.memIds[i]);
		}
		IERC20(genToken).safeTransfer(_msgSender(), user.genAmount);
		IERC721MintableAndBurnable(stkToken).burn(_stkTokenId);
		delete stakedUsers[_stkTokenId][_msgSender()];
	}

	function claim(uint256 _stkTokenId) external {
		UserInfo memory user = stakedUsers[_stkTokenId][_msgSender()];
		require(user.genAmount > 0);
		uint256 rewards = pendingReward(_msgSender(), _stkTokenId);
		if (rewards > address(this).balance) {
			rewards = address(this).balance;
		}
		if (rewards > 0) {
			payable(_msgSender()).transfer(rewards);
		}
		user.rewardsClaimed = user.rewardsClaimed.add(rewards);
	}

	function distributeRewards(uint256 _dropId, uint256 _dropStartBlock, uint256 _dropEndBlock, uint256 _DARefundsETH, uint256 _mintFundsETH) external {
		PoolInfo storage pool = pools[_dropId];
		_currentDropId = _dropId;
		uint256 DARefundPoolBal = _DARefundsETH.add(_mintFundsETH.mul(DARefundsPoolDistributionRate).div(100));
		uint256 genPoolBal = _mintFundsETH.mul(genPoolDistributionRate).div(100);
		uint256 memPoolBal = _mintFundsETH.mul(memPoolDistributionRate).div(100);
		pool.dropStartBlock = _dropStartBlock;
		pool.dropEndBlock = _dropEndBlock;
		pool.DARefundsETH = _DARefundsETH;
		pool.mintFundsETH = _mintFundsETH;
		pool.genPoolETHBalanceInDrop = genPoolBal;
		pool.DARefundPoolETHBalanceInDrop = DARefundPoolBal;
		pool.memPoolETHBalanceInDrop = memPoolBal;
	}

	function pendingReward(address _user, uint256 _stkTokenId) public view returns (uint256) {
		PoolInfo memory pool = pools[_currentDropId];
		UserInfo memory user = stakedUsers[_stkTokenId][_user];

		uint256 genPoolRewards = pool.genPoolETHBalanceInDrop.div(pool.totalGenAmountStaked).mul(user.genAmount);
		uint256 memPoolRewards;
		if (user.isGoldMem) {
			memPoolRewards = pool.memPoolETHBalanceInDrop.div(pool.totalGoldMemTokenAmountStaked.mul(5).add(pool.totalStandardMemTokenAmountStaked)).mul(user.memIds.length * 5);
		} else {
			memPoolRewards = pool.memPoolETHBalanceInDrop.div(pool.totalGoldMemTokenAmountStaked.mul(5).add(pool.totalStandardMemTokenAmountStaked)).mul(user.memIds.length);
		}
		uint256 DAUserSpent = ethSpends[_currentDropId][_user];
		uint256 totalRewards = genPoolRewards.add(memPoolRewards).add(DAUserSpent);
		return totalRewards;
	}

	function updateMemToken(address _memToken) external onlyOwner {
		require(_memToken != address(0));
		memToken = _memToken;
	}

	function updateGenToken(address _genToken) external onlyOwner {
		require(_genToken != address(0));
		genToken = _genToken;
	}

	function updateStkToken(address _stkToken) external onlyOwner {
		require(_stkToken != address(0));
		stkToken = _stkToken;
	}

	function updateRewardsDistributionRate(uint16 _DARefundsPoolDistributionRate, uint16 _genPoolDistributionRate, uint16 _memPoolDistributionRate) external onlyOwner {
		uint16 total = _DARefundsPoolDistributionRate + _genPoolDistributionRate + _memPoolDistributionRate;
		require(total > 0 && total <= 100, 'GenArtStaking: invalid rates');
		DARefundsPoolDistributionRate = _DARefundsPoolDistributionRate;
		genPoolDistributionRate = _genPoolDistributionRate;
		memPoolDistributionRate = _memPoolDistributionRate;
	}

  function _concatenateArrays(uint256[] storage _src, uint256[] memory _dest) internal {
    uint i = 0;
    while (i++ < _dest.length) {
      _src.push(_dest[i]);
    }
  }

  // receiving funds
  fallback() external payable {}
	receive() external payable {}
}
