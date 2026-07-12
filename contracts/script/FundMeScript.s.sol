//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {AggregatorV3Interface} from "../src/interfaces/AggregatorV3Interface.sol";

contract GetPrice is Script {
    address constant SEPOLIA_ETH_USD_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;

    function run() external view {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(SEPOLIA_ETH_USD_FEED);

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        uint8 decimals = priceFeed.decimals();

        console.log("Round ID:", roundId);
        console.log("ETH/USD Price (raw, 8 decimals):", uint256(answer));
        console.log("Decimals:", decimals);
        console.log("Updated At:", updatedAt);

        // Scaled to 18 decimals like your PriceConverter does
        uint256 scaledPrice = uint256(answer) * 10 ** (18 - decimals);
        console.log("ETH/USD Price (scaled, 18 decimals):", scaledPrice);
        console.log("ETH/USD Price (in USD, 18 decimals):", "$", scaledPrice / 1e18);
    }
}

// ============= DEPLOY SCRIPT =======================//

import {FundMe} from "../src/FundMe.sol";

contract DeployFundMe is Script {
    function run() external returns (FundMe) {
        address sepoliaPriceFeed = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
        vm.startBroadcast();
        FundMe fundMe = new FundMe(AggregatorV3Interface(sepoliaPriceFeed));
        vm.stopBroadcast();
        return fundMe;
    }

    // 0x61Ce8F8e157AaE4125eEfa7f507837Fb85Ce01E6
}
