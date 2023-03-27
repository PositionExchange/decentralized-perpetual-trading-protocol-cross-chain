import { MockToken, WETH } from "../../typeChain";

type BigNumberish = import("ethers").BigNumberish;

export function getBnbConfig(bnb: MockToken, _tokenWeight = 1) {
  return [
    bnb.address, // _token
    18, // _tokenDecimals
    75, // _minProfitBps,
    _tokenWeight, // _tokenWeight
    0, // _maxUsdgAmount
    false, // _isStable
    true // _isShortable
  ] as BigNumberish[]
}

export function getDaiConfig(dai: MockToken, _tokenWeight = 1) {
  return [
    dai.address, // _token
    18, // _tokenDecimals
    75, // _minProfitBps
    _tokenWeight, // _tokenWeight
    0, // _maxUsdgAmount
    true, // _isStable
    false // _isShortable
  ] as BigNumberish[]
}
export function getBtcConfig(btc: MockToken, _tokenWeight = 1) {
  return [
    btc.address, // _token
    8, // _tokenDecimals
    75, // _minProfitBps
    _tokenWeight, // _tokenWeight
    0, // _maxUsdgAmount
    false, // _isStable
    true // _isShortable
  ] as BigNumberish[]
}
export function getEthConfig(eth: WETH) {
  return [
    eth.address, // _token
    18, // _tokenDecimals
    75, // _minProfitBps
    10000, // _tokenWeight
    0, // _maxUsdgAmount
    false, // _isStable
    true // _isShortable
  ] as BigNumberish[]
}
