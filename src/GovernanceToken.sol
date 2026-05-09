// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/utils/Nonces.sol";

contract GovernanceToken is ERC20, ERC20Permit, ERC20Votes {
    uint256 public constant TEAM_ALLOCATION = 4000;      
    uint256 public constant TREASURY_ALLOCATION = 3000;   
    uint256 public constant AIRDROP_ALLOCATION = 2000;    
    uint256 public constant LIQUIDITY_ALLOCATION = 1000;  
    uint256 public constant TOTAL_BASIS_POINTS = 10000;   

    address public immutable teamVesting;
    address public immutable treasury;
    address public immutable airdropWallet;
    address public immutable liquidityWallet;

    uint256 public constant TOTAL_SUPPLY = 1_000_000 * 10**18;

    event TokensMintedToTeam(address indexed vestingContract, uint256 amount);
    event TokensMintedToTreasury(address indexed treasury, uint256 amount);
    event TokensMintedToAirdrop(address indexed airdrop, uint256 amount);
    event TokensMintedToLiquidity(address indexed liquidity, uint256 amount);

    constructor(
        address _teamVesting,
        address _treasury,
        address _airdropWallet,
        address _liquidityWallet
    )
        ERC20("Governance Token", "GOV")
        ERC20Permit("Governance Token")
    {
        require(_teamVesting != address(0), "Invalid team vesting address");
        require(_treasury != address(0), "Invalid treasury address");
        require(_airdropWallet != address(0), "Invalid airdrop wallet");
        require(_liquidityWallet != address(0), "Invalid liquidity wallet");

        teamVesting = _teamVesting;
        treasury = _treasury;
        airdropWallet = _airdropWallet;
        liquidityWallet = _liquidityWallet;

        uint256 teamAmount = (TOTAL_SUPPLY * TEAM_ALLOCATION) / TOTAL_BASIS_POINTS;
        uint256 treasuryAmount = (TOTAL_SUPPLY * TREASURY_ALLOCATION) / TOTAL_BASIS_POINTS;
        uint256 airdropAmount = (TOTAL_SUPPLY * AIRDROP_ALLOCATION) / TOTAL_BASIS_POINTS;
        uint256 liquidityAmount = TOTAL_SUPPLY - teamAmount - treasuryAmount - airdropAmount;

        _mint(_teamVesting, teamAmount);
        emit TokensMintedToTeam(_teamVesting, teamAmount);

        _mint(_treasury, treasuryAmount);
        emit TokensMintedToTreasury(_treasury, treasuryAmount);

        _mint(_airdropWallet, airdropAmount);
        emit TokensMintedToAirdrop(_airdropWallet, airdropAmount);

        _mint(_liquidityWallet, liquidityAmount);
        emit TokensMintedToLiquidity(_liquidityWallet, liquidityAmount);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function getVotes(address account) public view virtual override returns (uint256) {
        return super.getVotes(account);
    }

    function delegate(address delegatee) public virtual override {
        super.delegate(delegatee);
    }

    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override {
        super.delegateBySig(delegatee, nonce, expiry, v, r, s);
    }
}