import {
  BEP20Mintable,
  DptpFuturesGatewayMock,
  FuturesAdapter,
  VaultMock,
  WETH,
} from "../../typeChain";
import { deployContract } from "./common";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import {formatEther} from "@ethersproject/units/src.ts";

describe("DPTP Futures Gateway", async function () {
  let deployer: any;
  let trader: any;
  let trader2: any;

  let vault: VaultMock;
  let futuresGateway: DptpFuturesGatewayMock;
  let futuresAdapter: FuturesAdapter;

  let weth: WETH;
  let whitelistedToken: BEP20Mintable;
  let notWhitelistedToken: BEP20Mintable;
  let stableToken: BEP20Mintable;

  beforeEach(async () => {
    [
      deployer,
      trader,
      trader2,
      vault,
      futuresGateway,
      futuresAdapter,
      weth,
      whitelistedToken,
      notWhitelistedToken,
      stableToken,
    ] = await deployContract();
  });

  describe("test createIncreaseOrder", async () => {
    it("given valid request, when calling createIncreasePosition, should success", async () => {
      await whitelistedToken
        .connect(trader)
        .mint(trader.address, ethers.utils.parseEther("1000"));
      await whitelistedToken
          .connect(trader)
          .approve(futuresGateway.address, ethers.utils.parseEther("1000"));
      const balanceBefore = await whitelistedToken.balanceOf(trader.address);

      await futuresGateway
        .connect(trader)
        .createIncreaseOrder(
          [whitelistedToken.address],
          whitelistedToken.address,
          BigNumber.from("1800000"),
          ethers.utils.parseEther("0.1"),
          BigNumber.from("10"),
          true,
          {
            value: BigNumber.from("1000000000000000"),
          }
        );

      const balanceAfter = await whitelistedToken.balanceOf(trader.address)
      console.log(ethers.utils.formatEther(balanceBefore.sub(balanceAfter)))
    });
  });
});
