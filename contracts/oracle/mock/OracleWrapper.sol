// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.4;

import "@openzeppelin/contracts/access/Ownable.sol";

contract OracleWrapper is Ownable {
    bool internal _isMarketClosed;
    bool internal _isTerminated;
    string internal _collateral;
    string internal _underlyingAsset;
    int256 internal _indexPrice;
    uint256 internal _indexPriceTimestamp;
    int256 internal _markPrice;
    uint256 internal _markPriceTimestamp;

    // @dev if the time since _markPriceTimestamp exceeds this threshold, isTerminated will
    //      be true automatically. maxHeartBeat = 0 means no limit
    uint256 public maxHeartBeat;

    constructor(string memory collateral_, string memory underlyingAsset_) Ownable() {
        _collateral = collateral_;
        _underlyingAsset = underlyingAsset_;
    }

    function setIndexPrice(int256 price, uint256 timestamp) external onlyOwner {
        if (checkHeartStop()) {
            // keep the old price
            return;
        }
        _indexPrice = price;
        _indexPriceTimestamp = timestamp;
    }

    function setMarkPrice(int256 price, uint256 timestamp) external onlyOwner {
        if (checkHeartStop()) {
            // keep the old price
            return;
        }
        _markPrice = price;
        _markPriceTimestamp = timestamp;
    }

    function setMarketClosed(bool isClosed) external onlyOwner {
        _isMarketClosed = isClosed;
    }

    function setAll(
        int256 markPrice,
        int256 indexPrice,
        uint256 timestamp,
        bool _isMarketClosed_
    ) external onlyOwner {
        _markPrice = markPrice;
        _markPriceTimestamp = timestamp;
        _indexPrice = indexPrice;
        _indexPriceTimestamp = timestamp;
        _isMarketClosed = _isMarketClosed_;
    }

    function setTerminated(bool isTerminated_) external onlyOwner {
        _isTerminated = isTerminated_;
    }

    function setMaxHeartBeat(uint256 maxHeartBeat_) external onlyOwner {
        maxHeartBeat = maxHeartBeat_;
    }

    function collateral() external view returns (string memory) {
        return _collateral;
    }

    function underlyingAsset() external view returns (string memory) {
        return _underlyingAsset;
    }

    function priceTWAPLong() external view returns (int256 newPrice, uint256 newTimestamp) {
        return (_markPrice, _markPriceTimestamp);
    }

    function priceTWAPShort() external view returns (int256 newPrice, uint256 newTimestamp) {
        return (_indexPrice, _indexPriceTimestamp);
    }

    function isMarketClosed() external view returns (bool) {
        return _isMarketClosed;
    }

    function isTerminated() external returns (bool) {
        checkHeartStop();
        return _isTerminated;
    }

    function checkHeartStop() public returns (bool) {
        if (maxHeartBeat == 0 || _markPriceTimestamp == 0) {
            return false;
        }
        if (block.timestamp > _markPriceTimestamp + maxHeartBeat) {
            _isTerminated = true;
            return true;
        }
        return false;
    }
}
