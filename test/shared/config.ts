import { MockToken } from "../../typeChain";

export function getBnbConfig(bnb: MockToken, _tokenWeight = 1) {
  return [
    bnb.address, // _token
    18, // _tokenDecimals
    75, // _minProfitBps,
    _tokenWeight, // _tokenWeight
    0, // _maxUsdgAmount
    false, // _isStable
    true // _isShortable
  ]
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
  ]
}
