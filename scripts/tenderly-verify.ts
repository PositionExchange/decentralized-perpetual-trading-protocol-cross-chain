// File: scripts/greeter/manual-simple-public.ts
import { tenderly } from "hardhat";

async function main() {
  const contractName = "FuturesAdapter";
  const contractAddress = "0x2CBDD1E334e94f221c0764F4E3133c5aBC3418D5";

  await tenderly.verify({
    name: contractName,
    address: contractAddress,
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
