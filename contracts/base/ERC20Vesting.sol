// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenVesting is Ownable(address(0)) {
    IERC20 public token;
    address public beneficiary;
    uint256 public totalAmount;
    uint256 public vestingStart;
    uint256 public vestingDuration;
    uint256 public vestingCliff;

    constructor(
        IERC20 _token,
        address _beneficiary,
        uint256 _totalAmount,
        uint256 _vestingStart,
        uint256 _vestingDuration,
        uint256 _vestingCliff
    ) {
        require(_vestingDuration > 0, "Vesting duration must be greater than 0");
        require(_vestingCliff <= _vestingDuration, "Cliff period must be less than or equal to vesting duration");

        token = _token;
        beneficiary = _beneficiary;
        totalAmount = _totalAmount;
        vestingStart = _vestingStart;
        vestingDuration = _vestingDuration;
        vestingCliff = _vestingCliff;
    }

    function release() external onlyOwner {
        require(block.timestamp >= vestingStart, "Vesting has not started yet");

        uint256 vestedAmount = calculateVestedAmount();
        require(vestedAmount > 0, "No tokens are currently vested");

        token.transfer(beneficiary, vestedAmount);
    }

    function calculateVestedAmount() public view returns (uint256) {
        if (block.timestamp < vestingCliff) {
            return 0;
        } else if (block.timestamp >= vestingStart + vestingDuration) {
            return totalAmount;
        } else {
            uint256 elapsed = block.timestamp - vestingCliff;
            uint256 vestingPeriod = vestingStart + vestingDuration - vestingCliff;
            return (totalAmount * elapsed) / vestingPeriod;
        }
    }

    function revoke() external onlyOwner {
        // In case of any issues, owner can revoke the vesting and transfer the remaining tokens back to the owner
        token.transfer(owner(), token.balanceOf(address(this)));
    }
}
