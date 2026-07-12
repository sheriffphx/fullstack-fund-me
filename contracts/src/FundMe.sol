//SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import {PriceConverter} from "./PriceConverter.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";

contract FundMe {
    using PriceConverter for uint256;

    // Total deposited ETH in USD
    uint256 totalDeposit;
    //  Minimum amount to fund in USD
    uint256 public constant MINIMUM_USD = 1e18;
    address public OWNER;
    AggregatorV3Interface public priceFeed;
    // funders list
    address[] public funders;
    // Cumulative funder donation
    mapping(address => uint256) public amountFunded;

    error FundMe_NotOwner();

    event Funded(address indexed funder, uint256 amount);
    event Withdrawn(address indexed owner, uint256 amount);

    constructor(AggregatorV3Interface _priceFeed) {
        OWNER = msg.sender;
        priceFeed = _priceFeed;
    }

    function fund() public payable {
        uint256 usdValue = msg.value.getConversionRate(priceFeed);

        require(usdValue >= MINIMUM_USD, "Need more ETH");
        totalDeposit += msg.value;
        amountFunded[msg.sender] += msg.value;
        funders.push(msg.sender);

        emit Funded(msg.sender, msg.value);
    }

    function withdraw() external onlyOwner {
        totalDeposit = 0;

        uint256 balance = address(this).balance;
        //Empty the amount funded for each address
        for (uint256 i = 0; i < funders.length; ++i) {
            address funder = funders[i];
            amountFunded[funder] = 0;
        }
        //Empty the stored funders list
        funders = new address[](0);

        (bool success,) = payable(OWNER).call{value: balance}("");
        require(success, "Withdraw Failed");

        emit Withdrawn(OWNER, balance);
    }

    modifier onlyOwner() {
        if (msg.sender != OWNER) revert FundMe_NotOwner();
        _;
    }

    function getEthPrice() public view returns (uint256) {
        return PriceConverter.getPrice(priceFeed);
    }

    receive() external payable {
        fund();
    }

    fallback() external payable {
        fund();
    }

    /**
     * Getter functions
     */
    function getTotalDeposit() public view returns (uint256) {
        return totalDeposit;
    }

    function getFunder(uint256 index) public view returns (address) {
        return funders[index];
    }

    function getAmountFunded(address funder) public view returns (uint256) {
        return amountFunded[funder];
    }

    function getOwner() public view returns (address) {
        return OWNER;
    }

    function getPriceFeed() public view returns (AggregatorV3Interface) {
        return priceFeed;
    }

    function getMinimumUsd() public pure returns (uint256) {
        return MINIMUM_USD;
    }

    function getFundersLength() public view returns (uint256) {
        return funders.length;
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function getVersion() public view returns (uint256) {
        return priceFeed.version();
    }

    function getConversionRate(uint256 ethAmount) public view returns (uint256) {
        return ethAmount.getConversionRate(priceFeed);
    }
}
