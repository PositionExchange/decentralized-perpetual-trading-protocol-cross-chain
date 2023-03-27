import { ethers } from "hardhat";
import {
  BEP20Mintable,
  DptpFuturesGatewayMock,
  FuturesAdapter,
  VaultMock,
  WETH,
} from "../typeChain";
import { expect } from "chai";
import { BigNumber } from "ethers";

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
    [deployer, trader, trader2] = await ethers.getSigners();

    const wbnbFactory = await ethers.getContractFactory("WETH");
    weth = (await wbnbFactory.deploy("WETH", "WETH", 18)) as unknown as WETH;

    const bep20MintableFactory = await ethers.getContractFactory(
      "BEP20Mintable"
    );
    whitelistedToken = (await bep20MintableFactory.deploy(
      "whitelistedToken",
      "whitelistedToken"
    )) as unknown as BEP20Mintable;

    notWhitelistedToken = (await bep20MintableFactory.deploy(
      "notWhitelistedToken",
      "notWhitelistedToken"
    )) as unknown as BEP20Mintable;

    stableToken = (await bep20MintableFactory.deploy(
      "stableToken",
      "stableToken"
    )) as unknown as BEP20Mintable;

    const vaultMockFactory = await ethers.getContractFactory("VaultMock");
    vault = (await vaultMockFactory.deploy()) as unknown as VaultMock;

    // Deploy futures adapter
    const futuresAdapterFactory = await ethers.getContractFactory(
      "FuturesAdapter"
    );
    futuresAdapter =
      (await futuresAdapterFactory.deploy()) as unknown as FuturesAdapter;
    await futuresAdapter.initialize(910000, 86400);

    // Deploy futures gateway
    const futuresGatewayFactory = await ethers.getContractFactory(
      "DptpFuturesGatewayMock"
    );
    futuresGateway =
      (await futuresGatewayFactory.deploy()) as unknown as DptpFuturesGatewayMock;

    await futuresGateway.initialize();
    await futuresGateway.setWeth(weth.address);
    await futuresGateway.setVault(vault.address);
    await futuresGateway.setFuturesAdapter(futuresAdapter.address);
    await futuresGateway.setPositionManagerConfigData(
      whitelistedToken.address,
      100,
      100,
      100,
      10000,
      0,
      0,
      0,
      0
    );
    await futuresGateway.setMinExecutionFee(BigNumber.from("1000000000000000"));

    await weth
      .connect(trader)
      .approve(futuresGateway.address, BigNumber.from("10000000000000000000"));
    await whitelistedToken
      .connect(trader)
      .approve(futuresGateway.address, BigNumber.from("10000000000000000000"));
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
          BigNumber.from("1000000000000000"),
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
      expect(request.amountInUsd).to.be.eq(
        BigNumber.from("10000000000000000000000")
      );
      expect(request.feeUsd).to.be.eq(BigNumber.from("1000000000000000000000"));
      expect(request.sizeDelta).to.be.eq(
        BigNumber.from("100000000000000000000000")
      );
      expect(request.executionFee).to.be.eq(BigNumber.from("1000000000000000"));
      expect(request.isLong).to.be.true;
      expect(request.hasCollateralInETH).to.be.false;
    });
  });

  describe("test createIncreasePositionETH", async () => {
    it("given valid request, when calling createIncreasePositionETH, should success", async () => {
      await futuresGateway
        .connect(trader)
        .createIncreasePositionETH(
          [whitelistedToken.address],
          whitelistedToken.address,
          BigNumber.from("10"),
          true,
          BigNumber.from("1000000000000000"),
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
      expect(request.indexToken).to.be.eq(whitelistedToken.address);
      expect(request.amountInToken).to.be.eq(
        BigNumber.from("10000000000000000000")
      );
      expect(request.amountInUsd).to.be.eq(
        BigNumber.from("10000000000000000000000")
      );
      expect(request.feeUsd).to.be.eq(BigNumber.from("1000000000000000000000"));
      expect(request.sizeDelta).to.be.eq(
        BigNumber.from("100000000000000000000000")
      );
      expect(request.executionFee).to.be.eq(BigNumber.from("1000000000000000"));
      expect(request.isLong).to.be.true;
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
            true,
            0
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
            true,
            0
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
            BigNumber.from("1000000000000000"),
            {
              value: BigNumber.from("2000000000000000"),
            }
          )
      ).to.be.revertedWith("val");
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
            BigNumber.from("1000000000000000"),
            {
              value: BigNumber.from("2000000000000000"),
            }
          )
      ).to.be.revertedWith("val");
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
            BigNumber.from("1000000000000000"),
            {
              value: BigNumber.from("100"),
            }
          )
      ).to.be.revertedWith("val");
    });
  });
});
