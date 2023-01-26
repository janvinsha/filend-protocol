const main = async () => {
  const lensFactory = await hre.ethers.getContractFactory("lensImmutable");
  const lens = await lensFactory.deploy(
    //underlyng address
    "0xe802376580c10fe23f027e1e19ed9d54d4c9311e", //for usdt
    //filtrollerAddress
    "0xAeaD8eE43f8DD6ac2d286f4a07Ff96dD2cAe292B",
    //interestRateModel_
    "0x3435bB7C5EF81E606acf3fb221be1619cFe5080A",
    //initialExchangeRateMantissa_
    "200000000000000000000000000",
    //name_
    "Filend USD Tether",
    //symbol_
    "fUSDT",
    //decinmals
    8,
    //admin_
    "0x659CE0FC2499E1Fa14d30F5CD88aD058ba490e39"
  );

  await lens.deployed();
  console.log("fUSDT Contract deployed to:", lens.address);
};

const runMain = async () => {
  try {
    await main();
    process.exit(0);
  } catch (error) {
    console.log(error);
    process.exit(1);
    E;
  }
};

runMain();
