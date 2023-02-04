const main = async () => {
  const priceOracleFactory = await hre.ethers.getContractFactory(
    "PriceOracleProxy"
  );
  const priceOracle = await priceOracleFactory.deploy(
    //guardian
    "0x659CE0FC2499E1Fa14d30F5CD88aD058ba490e39",
    // v1PriceOracle_
    "0xfc6f773c76f63EFe8BB8584fa5E124C49A270349",
    //fetheraddress
    "0xC411eED88310e6A79024D14eeD8cbbe6918F9119",
    //fusdcaddress
    "0x9E5cFe1F5A81DAB8Ba0F8ceea094B28907Ce4202",
    //fusdt
    "0x88Af7ae8e7d4c598e278f9c6dfd55312c1B4117B"
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
