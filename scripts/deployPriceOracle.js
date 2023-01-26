const main = async () => {
  const priceOracleFactory = await hre.ethers.getContractFactory(
    "PriceOracleProxy"
  );
  const priceOracle = await priceOracleFactory.deploy(
    //guardian
    "0x659CE0FC2499E1Fa14d30F5CD88aD058ba490e39",
    // v1PriceOracle_
    "0x8009E32302342D3F29977D0D7Ea55cA5a43E1eBb",
    //fetheraddress
    "0xEf27dEc223ED218Ad5AfE0F211dB6Eb3a9918c4C",
    //fusdcaddress
    "0x160Def7e19bF719f8620a36e1C95aEB0bf460b1F",
    //fusdt
    "0xa42Dc52912358688DA648050c3B439b20B2e74e7"
  );
  await priceOracle.deployed();
  console.log("price oracle Contract deployed to:", priceOracle.address);
};

const runMain = async () => {
  try {
    await main();
    process.exit(0);
  } catch (error) {
    console.log(error);
    process.exit(1);
  }
};

runMain();
