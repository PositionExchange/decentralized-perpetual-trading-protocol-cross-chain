import {
  BEP20Mintable,
  DptpFuturesGatewayMock,
  FuturesAdapter,
  VaultMock,
  WETH,
} from "../../typeChain";
import { expect } from "chai";
import { BigNumber } from "ethers";
import { deployContract } from "./common";

describe.skip("DPTP Futures Gateway", async function () {
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

  describe("test createIncreasePosition", async () => {
    it("given valid request, when calling createIncreasePosition, should success", async () => {
      await whitelistedToken
        .connect(trader)
        .mint(trader.address, BigNumber.from("10000000000000000000"));
      await futuresGateway
        .connect(trader)
        .createIncreasePosition(
          [whitelistedToken.address],
          whitelistedToken.address,
          BigNumber.from("10000000000000000000"),
          BigNumber.from("10"),
          true,
          {
            value: BigNumber.from("1000000000000000"),
          }
        );

      const requestKey = await futuresGateway.getRequestKey(
        trader.address,
        BigNumber.from(1)
      );
      const request = await futuresGateway.increasePositionRequests(requestKey);

      expect(request.account).to.be.eq(trader.address);
      expect(request.indexToken).to.be.eq(whitelistedToken.address);
      expect(request.amountInToken).to.be.eq(
        BigNumber.from("10000000000000000000")
      );
      expect(request.feeUsd).to.be.eq(BigNumber.from("1000000000000000000000"));
      expect(request.hasCollateralInETH).to.be.false;
    });
  });

  describe("test createIncreasePositionETH", async () => {
    it("given valid request, when calling createIncreasePositionETH, should success", async () => {
      await futuresGateway
        .connect(trader)
        .createIncreasePositionETH(
          [weth.address],
          weth.address,
          BigNumber.from("10"),
          true,
          {
            value: BigNumber.from("10001000000000000000"),
          }
        );

      const requestKey = await futuresGateway.getRequestKey(
        trader.address,
        BigNumber.from(1)
      );
      const request = await futuresGateway.increasePositionRequests(requestKey);

      expect(request.account).to.be.eq(trader.address);
      expect(request.indexToken).to.be.eq(weth.address);
      expect(request.amountInToken).to.be.eq(
        BigNumber.from("10000000000000000000")
      );
      expect(request.feeUsd).to.be.eq(BigNumber.from("1000000000000000000000"));
      expect(request.hasCollateralInETH).to.be.false;
    });
  });

  describe("test common validation", async () => {
    it("given execution fee less than minimum execution fee, when calling createIncreasePosition, should revert", async () => {
      await expect(
        futuresGateway
          .connect(trader)
          .createIncreasePosition(
            [whitelistedToken.address],
            whitelistedToken.address,
            0,
            BigNumber.from("10"),
            true
          )
      ).to.be.revertedWith("fee");
    });
    it("given execution fee less than minimum execution fee, when calling createIncreasePositionETH, should revert", async () => {
      await expect(
        futuresGateway
          .connect(trader)
          .createIncreasePositionETH(
            [whitelistedToken.address],
            whitelistedToken.address,
            BigNumber.from("10"),
            true
          )
      ).to.be.revertedWith("fee");
    });
    it("given execution fee and msg.value not equal, when calling createIncreasePosition, should revert", async () => {
      await expect(
        futuresGateway
          .connect(trader)
          .createIncreasePosition(
            [whitelistedToken.address],
            whitelistedToken.address,
            0,
            BigNumber.from("10"),
            true,
            {
              value: BigNumber.from("2000000000000000"),
            }
          )
      ).to.be.revertedWith("fee");
    });
    it("given execution fee and msg.value not equal, when calling createIncreasePosition, should revert", async () => {
      await expect(
        futuresGateway
          .connect(trader)
          .createIncreasePosition(
            [whitelistedToken.address],
            whitelistedToken.address,
            0,
            BigNumber.from("10"),
            true,
            {
              value: BigNumber.from("2000000000000000"),
            }
          )
      ).to.be.revertedWith("fee");
    });
    it("given execution fee less than msg.value, when calling createIncreasePositionETH, should revert", async () => {
      await expect(
        futuresGateway
          .connect(trader)
          .createIncreasePosition(
            [whitelistedToken.address],
            whitelistedToken.address,
            0,
            BigNumber.from("10"),
            true,
            {
              value: BigNumber.from("100"),
            }
          )
      ).to.be.revertedWith("fee");
    });
  });
});
